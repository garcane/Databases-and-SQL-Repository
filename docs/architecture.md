# Architecture

## Overview

A Kimball-style dimensional warehouse on PostgreSQL, built from a preserved
Microsoft SQL Server OLTP source. Four layers, dependencies flowing one way only:

```
staging  →  warehouse  →  presentation
                ↑
          etl (control)
```

Diagrams: [data pipeline](../architecture/data-pipeline.md) ·
[star schema](../architecture/star-schema.md)

## Layers

| Schema | Responsibility | Constraints | Read by |
|---|---|---|---|
| `staging` | Land the extract, structurally 1:1 with the source | Primary keys **only** | ETL |
| `warehouse` | Conformed dimensional model | PK, FK, CHECK, EXCLUDE, indexes | ETL, presentation |
| `presentation` | Business-facing views, no storage | — | Analysts, BI |
| `etl` | Batch control, lineage, audit | PK, CHECK | Orchestrator |
| `reference` | Ports of the smaller training databases | Full | Nothing downstream |

### Why staging has no foreign keys

Deliberate. A landing zone that rejects rows destroys the evidence needed to
diagnose the upstream problem — you learn that *something* failed, not what.
Staging accepts whatever the source produces; referential integrity is asserted
by [`tests/validation.sql`](../tests/validation.sql), which reports violations as
data rather than aborting the load.

Primary keys *are* kept: they are the declared grain of each source table, and a
duplicate arriving there is a genuine extract failure worth stopping on.

### Why presentation exposes no surrogate keys

Surrogate keys are an implementation detail. An analyst joining on
`customer_key` couples a dashboard to the loader; the presentation layer is what
lets the warehouse schema change underneath without breaking consumers.

## Data flow

1. **Extract** — [`extract_northwind_data.py`](../postgres/seed/tools/extract_northwind_data.py)
   reads the golden source (never writes it) and emits 11 CSVs, 3,308 rows.
2. **Load** — `\copy` into `staging`, then `setval()` to resynchronise identity
   sequences.
3. **Transform** — PL/pgSQL loaders build dimensions, then facts.
4. **Serve** — 14 presentation views.
5. **Verify** — 71 checks across two suites.

## ETL design

### Orchestration

`warehouse.run_full_load()` is a **procedure**, not a function, so it can issue
`COMMIT`. It runs: calendar → dimensions → facts. Dimensions must precede facts
because facts resolve surrogate keys from them.

### Error handling

A PL/pgSQL block with an `EXCEPTION` clause is already a subtransaction —
PostgreSQL sets a savepoint on entry and rolls back to it when the handler fires.
That has a consequence worth stating explicitly: an audit row written *inside*
the handler would be rolled back along with everything else.

So the batch row is `INSERT`ed and **committed before the work begins**, then
updated to `FAILED` and committed independently by the handler. Bare `RAISE`
re-raises the original error with its `SQLSTATE` intact.

Verified: injected bad data produced a rolled-back load, a surviving `FAILED`
batch row, and `SQLSTATE 23514` re-raised to the caller.

### Idempotency

Every loader is safe to re-run. SCD2 loaders detect change by hash; fact loaders
use `ON CONFLICT` on the grain constraint, guarded by `IS DISTINCT FROM` so
unchanged rows are not rewritten. A re-run with no source change reports
**0 inserted, 0 updated**.

### Lineage

Every warehouse row carries `dw_load_batch_id` referencing `etl.load_batch`,
making a bad load traceable and reversible without restoring a backup. A unique
partial index permits only one `RUNNING` batch — concurrent loads against the
same SCD2 dimensions would interleave versions and corrupt the validity chain.

## Integrity model

Guarantees are enforced by the database wherever possible, because a rule
enforced by convention is a rule that eventually breaks.

| Guarantee | Mechanism | Verified |
|---|---|---|
| No overlapping SCD2 versions | `EXCLUDE USING gist (natural_key =, validity &&)` | rejected, `23P01` |
| One current version per entity | Partial unique index `WHERE is_current` | rejected |
| Fact grain holds | `UNIQUE` on the grain columns | rejected, `23505` |
| No orphan facts | `FOREIGN KEY` + Unknown member default | rejected, `23503` |
| Measures cannot be overwritten | Generated columns | rejected, `428C9` |
| Surrogate keys ETL-only | `GENERATED ALWAYS AS IDENTITY` | rejected, `428C9` |
| One load at a time | Unique partial index on `status = 'RUNNING'` | rejected, `23505` |

What the database *cannot* enforce — cross-table rules, non-immutable
predicates, and the continued existence of the constraints themselves — is
covered by [`tests/`](../tests/).

## Technology choices

| Decision | Rationale |
|---|---|
| PostgreSQL 14+ | `EXCLUDE`, range types, generated columns, partial indexes — the features the integrity model is built on |
| `btree_gist` | Required to mix `=` and `&&` in one `EXCLUDE` constraint |
| `numeric(19,4)` for money | Exact and locale-independent, unlike PostgreSQL's `money` |
| `\copy` for bulk load | Orders of magnitude faster than row-by-row `INSERT`; needs no superuser or server-side file access |
| Plain SQL + PL/pgSQL | No framework to install, no version to keep current, runs anywhere `psql` runs |

### Deliberately not used

**Kafka, Spark, a distributed lakehouse.** Wrong for 3,308 rows. Including them
would demonstrate tool familiarity at the cost of demonstrating judgement.

**An ORM or code-generated DDL.** The constraints here — exclusion constraints,
generated columns, partial indexes — are precisely what ORMs abstract away.

**Materialised views.** The presentation layer answers in milliseconds at this
volume. They would add refresh scheduling and staleness for no gain; the right
time to add them is when a measured query is actually too slow.

## Scaling path

The design holds well beyond the current volume, but these are the points where
it would need attention:

| Volume | Change needed |
|---|---|
| ~10M fact rows | Partition facts by `order_date_key` range; `VACUUM (ANALYZE)` at end of load becomes mandatory |
| ~100M | Consider BRIN indexes on the date key; move heavy aggregates to materialised views |
| Multiple sources | Add a source-system column to the natural keys; conform dimensions across sources |
| Sub-daily loads | Introduce Airflow for scheduling and retries; move to incremental extraction with a watermark |

`VACUUM (ANALYZE)` at the end of the load is worth flagging now, not later: a
pure-`INSERT` load creates no dead tuples, so autovacuum may not fire at all
before morning reports run — leaving every covering index unable to serve
index-only scans. Measured, that difference was **227 ms versus 31 ms**.

## Non-functional characteristics

| Property | Current state |
|---|---|
| Full load | 0.70 s, 6,452 rows |
| Re-run | no-op |
| Recovery | re-runnable after failure; batch audit retained |
| Traceability | every row → batch → timestamp, status, row counts |
| Testability | 71 automated checks, both suites exit non-zero on failure |
| Portability | any PostgreSQL 14+; no extensions beyond `btree_gist` |
