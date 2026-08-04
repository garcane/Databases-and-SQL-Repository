# Databases and SQL — Cross-Platform Data Warehouse

**A Microsoft SQL Server OLTP system, re-platformed onto PostgreSQL and
re-modelled as a Kimball dimensional warehouse — with the original preserved
byte for byte as a reference implementation.**

![SQL Server](https://img.shields.io/badge/SQL_Server-Reference-CC2927?style=flat-square&logo=microsoftsqlserver&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-14%2B-336791?style=flat-square&logo=postgresql&logoColor=white)
![Tests](https://img.shields.io/badge/tests-71%20passing-2ea44f?style=flat-square)
![Verified](https://img.shields.io/badge/verified_on-PostgreSQL_18.4-336791?style=flat-square)

---

## Executive summary

**The original system.** A Microsoft SQL Server estate built around Northwind —
13 tables, 16 views, 7 stored procedures, ~30 indexes and 3,308 rows of
transactional data — plus three smaller training databases. Entirely
third-normal-form OLTP: correct for recording orders, poorly shaped for
analysing them. Every revenue question required a five-table join, and the
reporting views had years hard-coded into their bodies, so 1998 sales were
invisible until somebody wrote another view.

**What was migrated, and why.** The schema, data, views and programmable objects
were ported to PostgreSQL and re-modelled dimensionally. The business drivers
are the usual ones and they are real here:

- **Licence cost.** SQL Server per-core licensing is a recurring cost that
  PostgreSQL removes entirely — it matters most for the non-production estate,
  where dev, test and analytics copies multiply.
- **Cloud and container portability.** PostgreSQL runs identically on RDS, Cloud
  SQL, Azure Database, Kubernetes and a laptop. No edition-specific features are
  used, so there is no lock-in to unwind later.
- **Modern data stack compatibility.** dbt, Airflow, Metabase and Superset all
  treat PostgreSQL as a first-class target.
- **Analytical shape.** Re-modelling was the point. A conformed star schema
  answers in one join what previously took five.

**What it cost.** Two constructs could not be ported and moved into the test
suite instead; both are documented at the point they occur. Eight pairs of
duplicate indexes in the source were deliberately not carried forward.

**Proof it worked.** Revenue reconciles at **£1,265,793.04** across staging,
warehouse and presentation, and **71 automated checks pass** — with the suites
themselves verified by deliberately breaking a copy of the warehouse and
confirming each defect was caught.

---

## Engineering decisions

The decisions a reviewer would ask about, and the reasoning.

<table>
<tr><td width="34%"><b>Two facts, not one</b></td>
<td>The source <code>Orders</code> table mixes order-line grain with order grain.
Combining them repeats freight on every line. <b>Measured:</b> true freight is
£64,942.69; summed across the line grain it becomes £207,306.10 — a
<b>3.19×</b> overstatement, <i>higher</i> than the 2.60 average lines per order,
because larger orders carry more freight. So revenue lives only in the
transaction fact, and freight only in the order-grain accumulating snapshot.</td></tr>

<tr><td><b>Overlapping SCD2 versions are impossible, not unlikely</b></td>
<td>Each Type 2 dimension carries
<code>EXCLUDE USING gist (natural_key WITH =, validity WITH &&)</code>. Two
overlapping versions cannot be committed whatever the loader does. SQL Server
has no declarative equivalent — it relies on procedural discipline plus an audit
query.</td></tr>

<tr><td><b>Hierarchies collapsed, never snowflaked</b></td>
<td>Category and supplier attributes are denormalised into
<code>dim_product</code>. Both are many-to-one, so a separate table costs a join
on every query and saves nothing on a 29-row table.</td></tr>

<tr><td><b>Unknown members, not NULL keys</b></td>
<td>Every dimension has a row at <code>-1</code>; every fact FK is
<code>NOT NULL DEFAULT -1</code>. Unattributable revenue stays visible and
countable rather than vanishing — and because no fact key is ever NULL, the
tests can treat <i>any</i> orphan as a hard failure.</td></tr>

<tr><td><b>Type 1 where Type 1 is correct</b></td>
<td>Product stock levels are overwritten, not versioned. Versioning them would
grow a 77-row dimension by ~28,000 rows a year. Inventory level is a fact
measure, not a product attribute.</td></tr>

<tr><td><b>Derived measures are generated columns</b></td>
<td><code>gross</code>, <code>discount</code>, <code>net</code>,
<code>days_to_ship</code> are computed by the database. The arithmetic is
defined once, cannot drift between reports, and cannot be left stale by a
partial reload.</td></tr>

<tr><td><b>Staging carries no foreign keys</b></td>
<td>Deliberate. A landing zone that rejects rows destroys the evidence needed to
diagnose the upstream problem. Integrity is asserted by the test suite, which
reports violations as data.</td></tr>

<tr><td><b>No Kafka, no Spark</b></td>
<td>Wrong for 3,308 rows. Including them would demonstrate tool familiarity at
the cost of demonstrating judgement.</td></tr>
</table>

---

## The golden source is untouched

The original SQL Server implementation is the **reference**, not legacy to be
tidied. It lives in [`sqlserver/`](sqlserver/) and is preserved absolutely:

- Moved with `git mv` at **100% rename similarity** — `git log --follow` works on
  every file
- **59 of 60 original blobs byte-identical** (the exception is `.gitattributes`,
  extended deliberately)
- Pinned with `sqlserver/** -text` so end-of-line normalisation can never rewrite
  it, even via `git add --renormalize`
- `create_qastore.sql` marked `binary` to protect its UTF-16LE BOM
- Pre-restructure state tagged **`archive/ms-sql-reference`**

Source quirks are preserved and *documented*, never silently corrected — the
`money` rounding idiom, a view whose self-join aliases read backwards, a `bit`
compared to the string `'N'`. See
[findings](docs/migration-guide.md#6-findings-in-the-source-implementation).

---

## Technology stack

| Layer | Technology |
|---|---|
| Source | Microsoft SQL Server 2016+, T-SQL |
| Target | PostgreSQL 14+ (verified 18.4), PL/pgSQL |
| Extensions | `btree_gist` — nothing else |
| Modelling | Kimball dimensional, SCD Type 1 and Type 2 |
| Extraction | Python 3.9+ (stdlib only) |
| Loading | `COPY` / `\copy`, PL/pgSQL procedures |
| Testing | SQL suites with non-zero exit on failure |

---

## Repository layout

```
├── README.md
├── docs/
│   ├── architecture.md          Layers, ETL design, integrity model, scaling
│   ├── dimensional-model.md     Grain, SCD strategy, measures, additivity
│   ├── sql-server.md            Setup and run — reference implementation
│   ├── postgres.md              Setup and run — ported warehouse
│   └── migration-guide.md       Dialect mappings, findings, strategy
├── architecture/
│   ├── star-schema.md           ERDs (Mermaid)
│   └── data-pipeline.md         Flow, load sequence, SCD2 pattern
├── sqlserver/                   GOLDEN SOURCE — do not modify
│   ├── database/                northwind · qatsqlplus · qastore · revenue
│   ├── exercises/               Day 1–4, demos, CSVs, normalisation workbooks
│   ├── queries/                 22 author-written analysis queries
│   └── views/                   2 author-written view definitions
├── postgres/
│   ├── database/                Schemas, staging, dimensions, facts
│   ├── functions/               Helpers, SCD loaders, orchestrator
│   ├── views/                   Presentation layer + ported views
│   ├── seed/                    \copy loader, CSVs, extractor
│   └── tuning/                  Measured EXPLAIN ANALYZE examples
├── tests/
│   ├── validation.sql           38 checks — internal consistency
│   └── quality-checks.sql       33 checks — reconciliation and structure
└── sample-data/
```

---

## Quick start

**PostgreSQL** — full instructions in [`docs/postgres.md`](docs/postgres.md):

```bash
createdb northwind_dw
for f in postgres/database/*.sql postgres/functions/*.sql postgres/views/*.sql; do
  psql -d northwind_dw -v ON_ERROR_STOP=1 -f "$f"
done
psql -d northwind_dw -v ON_ERROR_STOP=1 -f postgres/seed/00_load_staging.sql
psql -d northwind_dw -c "CALL warehouse.run_full_load('initial_load');"
psql -d northwind_dw -v ON_ERROR_STOP=1 -f tests/validation.sql
psql -d northwind_dw -v ON_ERROR_STOP=1 -f tests/quality-checks.sql
```

**SQL Server** — see [`docs/sql-server.md`](docs/sql-server.md):

```bash
sqlcmd -S localhost -E -i "sqlserver/database/northwind/northwind.sql"
```

---

## Verification

Everything below was measured on PostgreSQL 18.4, not estimated.

| Check | Result |
|---|---|
| Clean build, 12 scripts | pass |
| Staging vs canonical Northwind | 11/11 tables, 3,308 rows |
| Full warehouse load | 6,452 rows in **0.70 s** |
| Re-run with no source change | 0 inserted, 0 updated — a genuine no-op |
| SCD2 change detection | 1 version closed, 1 opened, chain intact |
| Load failure on bad data | rolled back · batch `FAILED` · `SQLSTATE 23514` re-raised · **audit row survived** |
| Revenue reconciliation | **£1,265,793.04** identical across all three layers |
| Freight (order grain) | £64,942.69 — vs £207,306.10 if wrongly taken from line grain |
| Facts on Unknown members | 0 |
| Test suites | **71/71 pass** |

**The tests were verified by breaking things.** Five defects were injected into a
loaded copy — an SCD2 entity left with no current version, an altered fact
measure, a dropped `EXCLUDE` constraint, an orphan staging row, and a future
birth date. Every one was caught; the last never reached a test, because the
schema's own check constraint refused the write. A suite that has never failed
is untested. See [`tests/README.md`](tests/README.md).

**Guarantees proven by asserting the violation is rejected:**

| Guarantee | Result |
|---|---|
| Overlapping SCD2 versions | blocked — `23P01` |
| Two current versions of one entity | blocked — `23P01` |
| Duplicate fact grain | blocked — `23505` |
| Orphan fact row | blocked — `23503` |
| Overwriting a generated measure | blocked — `428C9` |
| Hand-supplied surrogate key | blocked — `428C9` |
| Two concurrent load batches | blocked — `23505` |

---

## Performance tuning

Worked examples with measured plans in
[`postgres/tuning/`](postgres/tuning/explain-analyze-examples.sql). The most
useful finding:

> A covering index gave only **1.6×** improvement — because a bulk load leaves
> the visibility map unset, so `INCLUDE` buys nothing and every index entry still
> needs a heap fetch. After `VACUUM (ANALYZE)`: **366 ms → 31 ms**, I/O from
> **12,800 pages → 167**, `Heap Fetches: 0`.
>
> A load that bulk-inserts and does not `VACUUM` leaves every covering index in
> the degraded state — and autovacuum, driven by dead tuples, may not fire at all
> after a pure-`INSERT` load.

Also covered: the anti-pattern of wrapping a function around an indexed column
(**592 ms → 94 ms** when rewritten as a sargable range), partial indexes, and
extended statistics for correlated columns.

---

## Future improvements

Honest about sequence — these are worth doing *when a requirement appears*, not
before.

| | Improvement | Trigger |
|---|---|---|
| 1 | **Docker Compose** — PostgreSQL + seeded warehouse in one command | Immediately useful for reviewers |
| 2 | **CI/CD** — GitHub Actions building the schema, loading, and running both suites on every push | Immediately useful; the suites already exit non-zero |
| 3 | **dbt** — the `staging → warehouse → presentation` split maps directly onto dbt's staging/intermediate/marts convention, and `tests/` become schema tests | When transformation logic outgrows hand-written SQL |
| 4 | **Airflow** — one DAG, one task per loader; dependencies already expressed by load order | When scheduling, retries, backfills or SLAs are needed |
| 5 | **Incremental extraction** — watermark-based rather than full reload | When the source exceeds a few million rows |
| 6 | **Fact partitioning** by `order_date_key` | ~10M fact rows |

---

## Documentation

| Document | Contents |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | Layers, ETL design, error handling, integrity model, scaling path |
| [`docs/dimensional-model.md`](docs/dimensional-model.md) | Bus matrix, grain, SCD strategy per dimension, measures and additivity |
| [`docs/migration-guide.md`](docs/migration-guide.md) | Dialect mappings, unportable constructs, idiom upgrades, source findings |
| [`docs/sql-server.md`](docs/sql-server.md) | Reference implementation setup |
| [`docs/postgres.md`](docs/postgres.md) | Warehouse setup, operation, troubleshooting |
| [`architecture/star-schema.md`](architecture/star-schema.md) | Star schema and source ERDs |
| [`architecture/data-pipeline.md`](architecture/data-pipeline.md) | Pipeline, load sequence, SCD2 pattern |
| [`tests/README.md`](tests/README.md) | Test coverage and failure-detection evidence |
| [`sqlserver/README.md`](sqlserver/README.md) | Golden-source change policy |
