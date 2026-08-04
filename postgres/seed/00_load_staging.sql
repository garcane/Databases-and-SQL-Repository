-- ============================================================================
-- 00_load_staging.sql
--
-- Load the Northwind extract into the staging schema.
--
-- Run from the REPOSITORY ROOT - \copy is a client-side command and resolves
-- relative paths against psql's working directory, not the server's:
--
--     psql -d northwind_dw -v ON_ERROR_STOP=1 -f postgres/seed/00_load_staging.sql
--
-- The CSVs in postgres/seed/data/ are generated from the golden source by
-- postgres/seed/tools/extract_northwind_data.py. Regenerate them with:
--
--     python postgres/seed/tools/extract_northwind_data.py
--
-- ----------------------------------------------------------------------------
-- Why \copy and not INSERT
-- ----------------------------------------------------------------------------
-- The reference implementation replays ~3,300 single-row INSERT statements,
-- each its own statement and its own round trip. COPY streams the same data in
-- one pass per table: on this dataset it is roughly two orders of magnitude
-- faster, and it is the mechanism every PostgreSQL bulk-load tool ultimately
-- calls. \copy (client-side) is used rather than COPY (server-side) so that no
-- superuser privilege or server-accessible file path is required - the file is
-- streamed over the existing connection.
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- Truncate in dependency order. RESTART IDENTITY resets the identity sequences
-- so a reload does not leave them stranded past the loaded key range.
TRUNCATE TABLE
    staging.order_details,
    staging.orders,
    staging.products,
    staging.categories,
    staging.suppliers,
    staging.shippers,
    staging.customers,
    staging.employees,
    staging.employee_territories,
    staging.territories,
    staging.region,
    staging.customer_customer_demo,
    staging.customer_demographics
    RESTART IDENTITY CASCADE;

-- ----------------------------------------------------------------------------
-- Load. Order matters only for readability here: staging carries no foreign
-- keys, by design, so a partial or out-of-order load still lands.
-- ----------------------------------------------------------------------------
\copy staging.categories           (category_id, category_name, description) FROM 'postgres/seed/data/categories.csv' WITH (FORMAT csv, HEADER true)
\copy staging.customers            FROM 'postgres/seed/data/customers.csv'            WITH (FORMAT csv, HEADER true)
\copy staging.employees            (employee_id, last_name, first_name, title, title_of_courtesy, birth_date, hire_date, address, city, region, postal_code, country, home_phone, extension, notes, reports_to, photo_path) FROM 'postgres/seed/data/employees.csv' WITH (FORMAT csv, HEADER true)
\copy staging.shippers             FROM 'postgres/seed/data/shippers.csv'             WITH (FORMAT csv, HEADER true)
\copy staging.suppliers            FROM 'postgres/seed/data/suppliers.csv'            WITH (FORMAT csv, HEADER true)
\copy staging.products             FROM 'postgres/seed/data/products.csv'             WITH (FORMAT csv, HEADER true)
\copy staging.orders               FROM 'postgres/seed/data/orders.csv'               WITH (FORMAT csv, HEADER true)
\copy staging.order_details        FROM 'postgres/seed/data/order_details.csv'        WITH (FORMAT csv, HEADER true)
\copy staging.region               FROM 'postgres/seed/data/region.csv'               WITH (FORMAT csv, HEADER true)
\copy staging.territories          FROM 'postgres/seed/data/territories.csv'          WITH (FORMAT csv, HEADER true)
\copy staging.employee_territories FROM 'postgres/seed/data/employee_territories.csv' WITH (FORMAT csv, HEADER true)

-- ----------------------------------------------------------------------------
-- Resynchronise identity sequences.
--
-- This step has no equivalent in the SQL Server original and is the single
-- easiest thing to forget when migrating. Rows loaded with explicit key values
-- do not advance the underlying sequence, so the next system-generated key
-- would be 1 - colliding with existing data and failing on the primary key.
-- T-SQL's SET IDENTITY_INSERT OFF reseeds automatically; PostgreSQL does not.
--
-- setval(..., false) sets "next value is exactly this", hence max + 1.
-- COALESCE covers the empty-table case, where max() returns NULL.
-- ----------------------------------------------------------------------------
SELECT setval(pg_get_serial_sequence('staging.categories', 'category_id'),
              COALESCE((SELECT max(category_id) FROM staging.categories), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('staging.employees', 'employee_id'),
              COALESCE((SELECT max(employee_id) FROM staging.employees), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('staging.shippers', 'shipper_id'),
              COALESCE((SELECT max(shipper_id) FROM staging.shippers), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('staging.suppliers', 'supplier_id'),
              COALESCE((SELECT max(supplier_id) FROM staging.suppliers), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('staging.products', 'product_id'),
              COALESCE((SELECT max(product_id) FROM staging.products), 0) + 1, false);
SELECT setval(pg_get_serial_sequence('staging.orders', 'order_id'),
              COALESCE((SELECT max(order_id) FROM staging.orders), 0) + 1, false);

COMMIT;

-- ----------------------------------------------------------------------------
-- Load report. Expected counts are the canonical Northwind figures; any
-- deviation means the extract or this load is wrong, and it should be caught
-- here rather than three transformations downstream.
-- ----------------------------------------------------------------------------
SELECT table_name, actual, expected,
       CASE WHEN actual = expected THEN 'ok' ELSE 'MISMATCH' END AS status
FROM (
    SELECT 'categories'           AS table_name, count(*) AS actual,    8 AS expected FROM staging.categories
    UNION ALL SELECT 'customers',            count(*),   91 FROM staging.customers
    UNION ALL SELECT 'employees',            count(*),    9 FROM staging.employees
    UNION ALL SELECT 'shippers',             count(*),    3 FROM staging.shippers
    UNION ALL SELECT 'suppliers',            count(*),   29 FROM staging.suppliers
    UNION ALL SELECT 'products',             count(*),   77 FROM staging.products
    UNION ALL SELECT 'orders',               count(*),  830 FROM staging.orders
    UNION ALL SELECT 'order_details',        count(*), 2155 FROM staging.order_details
    UNION ALL SELECT 'region',               count(*),    4 FROM staging.region
    UNION ALL SELECT 'territories',          count(*),   53 FROM staging.territories
    UNION ALL SELECT 'employee_territories', count(*),   49 FROM staging.employee_territories
) t
ORDER BY CASE WHEN actual = expected THEN 1 ELSE 0 END, table_name;
