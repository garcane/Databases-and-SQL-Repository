# PostgreSQL — end-to-end build

Full run order from an empty database. Run from the **repository root** (the
seed script uses `\copy`, which resolves paths client-side).

```bash
createdb northwind_dw

for f in postgres/database/00_schemas.sql \
         postgres/database/10_staging.sql \
         postgres/database/15_reference_schemas.sql \
         postgres/database/20_dimensions.sql \
         postgres/database/30_facts.sql \
         postgres/functions/00_helpers.sql \
         postgres/functions/10_load_dimensions.sql \
         postgres/functions/20_load_facts.sql \
         postgres/functions/30_run_full_load.sql \
         postgres/functions/40_reference_objects.sql \
         postgres/views/00_presentation_views.sql \
         postgres/views/10_ported_views.sql; do
  psql -d northwind_dw -v ON_ERROR_STOP=1 -f "$f"
done

psql -d northwind_dw -v ON_ERROR_STOP=1 -f postgres/seed/00_load_staging.sql
psql -d northwind_dw -c "CALL warehouse.run_full_load('initial_load');"
```

## Layout

| Directory | Contents |
|---|---|
| `database/` | DDL — schemas, staging, dimensions, facts, reference ports |
| `functions/` | PL/pgSQL — helpers, SCD loaders, fact loaders, orchestrator, reference objects |
| `views/` | Presentation layer and direct ports of the author's SQL Server views |
| `seed/` | `\copy` load script, extracted CSVs, and the extractor tool |
| `tuning/` | Measured `EXPLAIN ANALYZE` worked examples |

Regenerate the CSVs from the golden source at any time — the source is read,
never written:

```bash
python postgres/seed/tools/extract_northwind_data.py
```

## Verified end to end on PostgreSQL 18.4

| Check | Result |
|---|---|
| Clean build, all 12 scripts | pass |
| Staging load vs canonical Northwind counts | 11/11 tables match (3,308 rows) |
| Full warehouse load | 6,452 rows in 0.70 s |
| Re-run with no source change | 0 inserted, 0 updated (truly idempotent) |
| SCD Type 2 change detection | 1 version closed, 1 opened; history intact |
| Load failure (bad source data) | rolled back, batch marked `FAILED`, original SQLSTATE `23514` re-raised |
| Audit row survives the rollback | yes — the trap this port exists to avoid |
| Recovery after repair | clean `SUCCEEDED` |
| Revenue reconciliation | £1,265,793.04 identical across staging, warehouse and presentation |
| Freight double-count avoided | £64,942.69 at order grain vs £207,306.10 if taken from line grain (3.19×) |
| Facts on the Unknown member | 0 |
| All 12 views return rows | yes |

## Load batch audit

Every run is recorded, successes and failures alike:

```sql
SELECT load_batch_id, batch_name, status, rows_inserted, rows_updated, error_message
FROM etl.load_batch ORDER BY load_batch_id DESC LIMIT 10;
```
