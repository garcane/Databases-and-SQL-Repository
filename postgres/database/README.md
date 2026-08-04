# PostgreSQL — DDL build order

Run these in order against an empty database. Each script is safe to re-run, but
re-running `10`–`30` drops and rebuilds the tables it owns, so re-run the whole
sequence from the first script you touched rather than one in isolation.

```bash
createdb northwind_dw
for f in 00_schemas 10_staging 15_reference_schemas 20_dimensions 30_facts; do
  psql -d northwind_dw -v ON_ERROR_STOP=1 -f "postgres/database/$f.sql"
done
```

| Script | Creates | Notes |
|---|---|---|
| `00_schemas.sql` | `btree_gist`, the five schemas, `etl.load_batch` | Fully idempotent (`IF NOT EXISTS`) |
| `10_staging.sql` | 13 staging tables | 1:1 port of Northwind OLTP |
| `15_reference_schemas.sql` | 14 tables | QAStore, QATSQLPLUS, REVENUE ports — independent of the warehouse |
| `20_dimensions.sql` | 5 dimensions + Unknown members | Requires `00` (btree_gist) |
| `30_facts.sql` | 2 fact tables | Requires `20` |

Loading data is `postgres/seed/`; views are `postgres/views/`; the ETL functions
are `postgres/functions/`.

## Verified against PostgreSQL 18.4

The whole sequence was executed on a clean cluster and the behavioural
guarantees tested, not just the syntax:

| Guarantee | Result |
|---|---|
| Overlapping SCD2 versions rejected | blocked — `23P01` exclusion violation |
| Two current versions of one entity rejected | blocked — `23P01` |
| `valid_to` before `valid_from` rejected | blocked — `22000` |
| Surrogate key cannot be supplied by hand | blocked — `428C9` (`GENERATED ALWAYS`) |
| Adjacent, non-overlapping versions accepted | allowed — 2 versions, 1 current |
| Duplicate fact grain rejected | blocked — `23505` |
| Orphan fact row rejected | blocked — `23503` |
| Discount > 100%, zero quantity rejected | blocked — `23514` |
| Generated measure cannot be overwritten | blocked — `428C9` |
| `date_key` disagreeing with `full_date` rejected | blocked — `23514` |
| Two concurrent `RUNNING` batches rejected | blocked — `23505` |
| Employee managing themselves rejected | blocked — `23514` |
| Derived measures compute correctly | 10 × £18.00 @ 25% → gross 180, discount 45, net 135 |
| Unresolved dimension lookups | default to Unknown member `-1`, row retained |
| Accumulating snapshot lags | shipped order → 10 days to ship, 5 days late; unshipped → `NULL`, `is_late=false` |

Resulting inventory: 34 tables, 32 primary keys, 28 foreign keys, 24 check
constraints, 3 exclusion constraints, 64 indexes, 13 generated columns, 5
Unknown members.

Minimum version is **PostgreSQL 14** (`GENERATED ALWAYS AS … STORED` needs 12;
`INCLUDE` on indexes needs 11; nothing here requires 15+).
