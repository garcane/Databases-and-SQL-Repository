# Data quality tests

Two suites. Both print a per-check result table and a summary, then exit
non-zero if any **ERROR**-severity check failed — so either can gate a CI
pipeline or run as a post-load guard.

```bash
psql -d northwind_dw -v ON_ERROR_STOP=1 -f tests/validation.sql
psql -d northwind_dw -v ON_ERROR_STOP=1 -f tests/quality-checks.sql
```

| Suite | Question it answers | Checks |
|---|---|---|
| [`validation.sql`](validation.sql) | Is the data internally consistent? | 38 |
| [`quality-checks.sql`](quality-checks.sql) | Does it still agree with the source, and is the schema still the one that was designed? | 33 |

**Severity:** `ERROR` fails the run. `WARN` reports but does not fail — used for
conditions that are legitimate but must stay visible, such as facts resolved to
an Unknown dimension member.

## What `validation.sql` covers

| Group | Checks | Examples |
|---|---|---|
| `duplicates` | 7 | declared fact grain holds; exactly one current row per dimension entity |
| `scd2` | 6 | no overlapping versions; **no gaps** in the version chain; exactly one open-ended version |
| `referential` | 9 | no key outside its dimension; Unknown-member usage; staging integrity (no FKs there by design) |
| `nulls` | 7 | NULLs only where a NULL means a broken load, not merely absent data |
| `business` | 9 | discount 0–1; net never exceeds gross; `dim_date` gapless; ported `CK_Birthdate` |

## What `quality-checks.sql` covers

| Group | Checks | Examples |
|---|---|---|
| `row_counts` | 11 | staging against the canonical Northwind figures |
| `reconciliation` | 11 | revenue, gross and freight reconciled to the penny across staging → warehouse → presentation |
| `structure` | 7 | EXCLUDE constraints still present; grain constraints intact; hot-path FKs indexed; no duplicate indexes |
| `etl` | 4 | last batch succeeded; none stuck `RUNNING`; every fact row traceable to a batch |

## Why the structural checks matter

Data tests catch bad loads. Structural tests catch bad *migrations* — a
constraint that silently failed to port, an index dropped in a refactor, an
`EXCLUDE` constraint removed so overlapping SCD2 versions quietly become
possible. None of these raise an error; they just produce a warehouse that is
slower and less trustworthy than the one designed.

Three checks were themselves wrong on first run and were fixed rather than
having their expected values bent to match:

- `STR-006` grouped indexes by column list alone, reporting all three SCD2
  dimensions as carrying duplicate indexes. They carry a **partial** unique
  index and a **full** index on the same column — different indexes with
  different jobs. Acting on that false positive would have meant dropping an
  index the model's correctness depends on. Fixed by including `indpred`.
- `STR-004` asserted every fact foreign key had an index, which would fail
  forever on six deliberately unindexed keys (secondary role-playing dates and
  the lineage key). Scoped to the five hot-path dimension keys.
- `STR-007` hard-coded 12 expected views; there are 14.

## Verified by deliberate breakage

A passing test suite proves nothing until it has been shown to fail. Five
defects were injected into a copy of a loaded warehouse:

| Injected defect | Caught by |
|---|---|
| Closed every version of one customer, leaving none current | `SCD-005`, `REC-007` |
| Altered a fact measure (`quantity + 100`) | `REC-003`, `REC-004` |
| Dropped an `EXCLUDE` constraint from `dim_product` | `STR-002` |
| Orphan row in `staging.order_details` | `RI-005`, `CNT-005`, `REC-001` |
| Future `birth_date` on an employee | *rejected by the schema itself* — `ck_dim_employee_hired_after_birth` refused the write |

Both suites exited non-zero. The fifth case is worth noting: the database
declined the bad write before any test ran, which is defence in depth working
as intended — the constraint is the first line, the test is the second.

## Baseline on a clean load

All 71 checks pass, with revenue reconciling at **£1,265,793.04** across
staging, warehouse and presentation.

```
validation.sql      38 checks   38 passed   0 error   0 warn
quality-checks.sql  33 checks   33 passed   0 error   0 warn
```
