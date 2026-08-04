# PostgreSQL — Setup and Run

Build the ported warehouse from an empty database, load it, and verify it.

## Prerequisites

- **PostgreSQL 14 or later** (verified on 18.4)
  `GENERATED ALWAYS AS ... STORED` needs 12; `INCLUDE` on indexes needs 11.
  Nothing here requires 15+.
- **`btree_gist`** — ships with the standard `postgresql-contrib` package. Needed
  for the `EXCLUDE` constraints that make overlapping SCD2 versions impossible.
- **Python 3.9+** — only if you want to regenerate the CSVs. The generated CSVs
  are committed, so this is optional.

## Quick start

Run from the **repository root** — `\copy` is a client-side command and resolves
relative paths against `psql`'s working directory.

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

Expected output from the load:

```
NOTICE:  batch 1 (initial_load) started
NOTICE:    dim_date              +3287 rows
NOTICE:    dim_customer          +91 new, 0 versioned
NOTICE:    dim_product           +77 new, 0 versioned
NOTICE:    dim_employee          +9 new, 0 versioned
NOTICE:    dim_shipper           +3 new, 0 updated
NOTICE:    fact_sales_order_line +2155 new, 0 updated
NOTICE:    fact_order_fulfilment +830 new, 0 updated
NOTICE:  batch 1 SUCCEEDED: 6452 inserted, 0 updated in 00:00:00.697271
```

Then verify:

```bash
psql -d northwind_dw -v ON_ERROR_STOP=1 -f tests/validation.sql
psql -d northwind_dw -v ON_ERROR_STOP=1 -f tests/quality-checks.sql
```

Both should end with `PASSED` and exit `0`. 71 checks in total.

## Build order, and why

| Script | Creates | Depends on |
|---|---|---|
| `database/00_schemas.sql` | `btree_gist`, 5 schemas, `etl.load_batch` | — |
| `database/10_staging.sql` | 13 staging tables | `00` |
| `database/15_reference_schemas.sql` | 14 reference tables | `00` |
| `database/20_dimensions.sql` | 5 dimensions + Unknown members | `00` (btree_gist) |
| `database/30_facts.sql` | 2 fact tables | `20` |
| `functions/00_helpers.sql` | `scd_hash`, `to_date_key`, `populate_dim_date` | `20` |
| `functions/10_load_dimensions.sql` | 4 dimension loaders | `00_helpers` |
| `functions/20_load_facts.sql` | 2 fact loaders | `10_load_dimensions` |
| `functions/30_run_full_load.sql` | Orchestrator procedure | all loaders |
| `functions/40_reference_objects.sql` | Reference UDFs, procedure, 2 views | `15` |
| `views/00_presentation_views.sql` | 8 analytical views | `30_facts` |
| `views/10_ported_views.sql` | 6 ports of the SQL Server views | `10_staging` |

`00_schemas.sql` is fully idempotent. Scripts `10`–`30` **drop and recreate** the
tables they own, so re-run the whole sequence from the first script you touched
rather than one in isolation.

## Regenerating the seed data

The CSVs are generated from the golden source, which is read and never written:

```bash
python postgres/seed/tools/extract_northwind_data.py
```

```
Reading sqlserver\database\northwind\northwind.sql (1,048,433 bytes)
  categories                 8 rows -> categories.csv
  customers                 91 rows -> customers.csv
  ...
3,308 rows extracted to postgres\seed\data/
```

The extractor handles the three INSERT shapes in the source, doubled-quote
escapes, the `N'...'` national-literal prefix, and **cp1252** decoding. It drops
the embedded bitmap columns (`Categories.Picture`, `Employees.Photo`) — 40 KB
OLE-wrapped Windows bitmaps with no analytical value.

## Using the warehouse

Query the **presentation** layer, not `warehouse` directly:

```sql
-- Revenue by category and year
SELECT order_year, category, net_revenue
  FROM presentation.sales_by_category_year
 ORDER BY order_year, net_revenue DESC;

-- Top customers by lifetime value
SELECT customer, customer_country, orders, lifetime_revenue, avg_order_value
  FROM presentation.customer_sales_summary
 ORDER BY lifetime_revenue DESC
 LIMIT 10;

-- Delivery performance by carrier (order grain — freight is correct here)
SELECT shipper, orders, late_pct, avg_days_to_ship, total_freight
  FROM presentation.order_fulfilment_performance
 WHERE order_year = 1997;

-- SCD Type 2 history
SELECT * FROM presentation.customer_history WHERE customer_id = 'ALFKI';
```

All 14 views: `sales`, `sales_by_category_year`, `customer_sales_summary`,
`employee_performance`, `order_fulfilment_performance`, `customer_history`,
`dim_order_date`, `dim_shipped_date`, `contact_directory`,
`new_contact_directory`, `managers`, `current_product_list`, `order_subtotals`,
`products_above_average_price`.

## Operating the load

```sql
-- Run a load
CALL warehouse.run_full_load('nightly');

-- Batch history, successes and failures alike
SELECT load_batch_id, batch_name, status, rows_inserted, rows_updated,
       completed_at - started_at AS duration, error_message
  FROM etl.load_batch ORDER BY load_batch_id DESC LIMIT 10;
```

Re-running with no source change is a genuine no-op: **0 inserted, 0 updated**.

### After a large load

```sql
VACUUM (ANALYZE) warehouse.fact_sales_order_line;
```

Worth doing explicitly. A pure-`INSERT` load creates no dead tuples, so
autovacuum may not fire at all, leaving the visibility map unset — and covering
indexes cannot serve index-only scans without it. Measured on 2M rows: **227 ms
before `VACUUM`, 31 ms after**. See
[`postgres/tuning/`](../postgres/tuning/explain-analyze-examples.sql).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `ERROR: extension "btree_gist" is not available` | Install `postgresql-contrib` (Debian/Ubuntu: `apt install postgresql-contrib`) |
| `ERROR: could not open file ".../categories.csv"` | `\copy` resolves paths client-side — run from the repository root |
| `ERROR: conflicting key value violates exclusion constraint "ex_dim_..."` | A loader inserted before closing the prior version. This is the constraint working; check the loader order |
| `ERROR: value too long for type character(5)` | The extractor is not stripping the `N'...'` prefix. Regenerate the CSVs |
| `duplicate key value violates unique constraint "uix_load_batch_single_running"` | A previous load died leaving a `RUNNING` batch. Inspect `etl.load_batch`, then resolve it before loading again |
| `CALL cannot be executed from a function` / in a transaction | `run_full_load` commits, so it cannot run inside an explicit transaction block. Use autocommit (psql's default) |
| Mojibake in customer addresses | The CSVs are UTF-8; check `client_encoding` |

## Verified results

Measured on PostgreSQL 18.4:

| Check | Result |
|---|---|
| Clean build, all 12 scripts | pass |
| Staging vs canonical Northwind counts | 11/11 tables, 3,308 rows |
| Full load | 6,452 rows in 0.70 s |
| Re-run, no source change | 0 inserted, 0 updated |
| SCD2 change detection | 1 version closed, 1 opened, history intact |
| Load failure on bad data | rolled back, batch `FAILED`, `SQLSTATE 23514` re-raised, audit row survived |
| Revenue reconciliation | £1,265,793.04 across all three layers |
| Test suites | 71/71 pass |
