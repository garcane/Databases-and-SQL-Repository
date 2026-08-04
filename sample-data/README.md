# Sample Data — Curated Demo Subset

A small, **referentially complete** slice of the Northwind extract for demos,
screenshots and quick experiments where loading all 3,308 rows is unnecessary.

| File | Rows |
|---|---:|
| `customers.csv` | 12 |
| `orders.csv` | 128 |
| `order_details.csv` | 362 |
| `products.csv` | 74 |
| `categories.csv` | 8 |
| `suppliers.csv` | 29 |
| `employees.csv` | 9 |
| `shippers.csv` | 3 |

**625 rows total**, about 19% of the full extract.

## Selection rule

The **12 customers with the most orders in 1997**, their 1997 orders, the lines
on those orders, and then — transitively — everything those rows reference.

Referential completeness is the point. Every foreign key in the subset resolves
*inside* the subset, including employees' managers, which are followed up the
reporting chain so the flattened hierarchy in `dim_employee` still builds. A
demo extract that dangles is worse than no demo extract, because it fails in
ways the real data never would.

The generator verifies this rather than assuming it, and refuses to write an
empty subset — a guard added after the first run reported "no dangling foreign
keys" on **zero rows**, which is true and useless.

## Regenerating

```bash
python sample-data/build_sample.py
```

Reads `postgres/seed/data/*.csv`. Adjust `CUSTOMER_LIMIT` and `YEAR` at the top
of the script to change the slice.

## Loading

Same structure as the full extract, so the same target tables apply. From the
repository root, against a database already built by
[`postgres/database/`](../postgres/database/):

```sql
TRUNCATE TABLE staging.order_details, staging.orders, staging.products,
               staging.categories, staging.suppliers, staging.shippers,
               staging.customers, staging.employees
    RESTART IDENTITY CASCADE;

\copy staging.categories (category_id, category_name, description) FROM 'sample-data/categories.csv' WITH (FORMAT csv, HEADER true)
\copy staging.customers  FROM 'sample-data/customers.csv'  WITH (FORMAT csv, HEADER true)
\copy staging.employees  (employee_id, last_name, first_name, title, title_of_courtesy, birth_date, hire_date, address, city, region, postal_code, country, home_phone, extension, notes, reports_to, photo_path) FROM 'sample-data/employees.csv' WITH (FORMAT csv, HEADER true)
\copy staging.shippers   FROM 'sample-data/shippers.csv'   WITH (FORMAT csv, HEADER true)
\copy staging.suppliers  FROM 'sample-data/suppliers.csv'  WITH (FORMAT csv, HEADER true)
\copy staging.products   FROM 'sample-data/products.csv'   WITH (FORMAT csv, HEADER true)
\copy staging.orders     FROM 'sample-data/orders.csv'     WITH (FORMAT csv, HEADER true)
\copy staging.order_details FROM 'sample-data/order_details.csv' WITH (FORMAT csv, HEADER true)
```

Then `CALL warehouse.run_full_load('sample');`.

> **Note.** The row-count checks in
> [`tests/quality-checks.sql`](../tests/quality-checks.sql) assert the *full*
> canonical Northwind figures and will fail against this subset. That is
> correct — the counts are a deliberate tripwire for a truncated load.
> `tests/validation.sql` passes against either.

## Dates are ISO 8601

Unlike the raw source, which writes dates as US `M/D/YYYY`, these files use
`YYYY-MM-DD`. That is not cosmetic: `7/4/1996` loads as **4 July** on a server
with `DateStyle=MDY` and **7 April** on one with `DateStyle=DMY`, silently and
without error. See
[`docs/migration-guide.md`](../docs/migration-guide.md#2-data-type-mappings).
