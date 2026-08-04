-- ============================================================================
-- validation.sql
--
-- Data integrity tests: duplicates, unexpected NULLs, referential integrity,
-- orphaned facts, and SCD Type 2 chain correctness.
--
--     psql -d northwind_dw -v ON_ERROR_STOP=1 -f tests/validation.sql
--
-- Exits non-zero if any ERROR-severity check fails, so it can gate a CI
-- pipeline or a post-load step. WARN-severity checks report but do not fail.
--
-- ----------------------------------------------------------------------------
-- Why these tests exist when the schema already has constraints
-- ----------------------------------------------------------------------------
-- Three reasons, and each maps to a group of checks below:
--
--   1. Rules PostgreSQL cannot express declaratively. The source's
--      CK_Birthdate (BirthDate < GETDATE()) is rejected as a CHECK constraint
--      because the expression is not immutable. It is asserted here instead.
--
--   2. Rules that span tables. "Every order in staging has a customer that
--      exists" cannot be a constraint, because staging deliberately carries no
--      foreign keys - a landing zone that rejects rows destroys the evidence
--      needed to diagnose the upstream problem.
--
--   3. Proof that the constraints are actually present and working. A
--      constraint dropped during a migration fails silently and forever. These
--      tests re-derive the guarantees from the data itself, so a missing
--      constraint shows up as failing data rather than as nothing at all.
--
-- A check that can never fail is not worth running; every check below has a
-- failure mode that has actually occurred in a real warehouse.
-- ============================================================================

\set ON_ERROR_STOP on
\timing off

DROP TABLE IF EXISTS test_results;
CREATE TEMP TABLE test_results (
    check_id     text,
    category     text,
    severity     text,   -- ERROR | WARN
    description  text,
    expected     text,
    actual       text,
    status       text GENERATED ALWAYS AS (
                     CASE WHEN expected IS NOT DISTINCT FROM actual
                          THEN 'PASS' ELSE 'FAIL' END
                 ) STORED
);


-- ============================================================================
-- GROUP 1 - Duplicate detection (declared grain must hold)
-- ============================================================================

-- The single most important test in a dimensional warehouse. If the grain of a
-- fact table drifts, every measure silently doubles and no error is raised.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'DUP-001', 'duplicates', 'ERROR',
       'fact_sales_order_line: one row per (order_id, product_id)',
       '0',
       count(*)::text
  FROM (SELECT order_id, product_id
          FROM warehouse.fact_sales_order_line
         GROUP BY order_id, product_id
        HAVING count(*) > 1) d;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'DUP-002', 'duplicates', 'ERROR',
       'fact_order_fulfilment: one row per order_id',
       '0',
       count(*)::text
  FROM (SELECT order_id
          FROM warehouse.fact_order_fulfilment
         GROUP BY order_id
        HAVING count(*) > 1) d;

-- More than one CURRENT version of a business entity makes every join to that
-- dimension fan out, inflating measures without any error.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'DUP-003', 'duplicates', 'ERROR',
       'dim_customer: exactly one current row per customer_id',
       '0',
       count(*)::text
  FROM (SELECT customer_id FROM warehouse.dim_customer
         WHERE is_current GROUP BY customer_id HAVING count(*) > 1) d;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'DUP-004', 'duplicates', 'ERROR',
       'dim_product: exactly one current row per product_id',
       '0',
       count(*)::text
  FROM (SELECT product_id FROM warehouse.dim_product
         WHERE is_current GROUP BY product_id HAVING count(*) > 1) d;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'DUP-005', 'duplicates', 'ERROR',
       'dim_employee: exactly one current row per employee_id',
       '0',
       count(*)::text
  FROM (SELECT employee_id FROM warehouse.dim_employee
         WHERE is_current GROUP BY employee_id HAVING count(*) > 1) d;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'DUP-006', 'duplicates', 'ERROR',
       'dim_shipper: shipper_id unique (Type 1, no versioning)',
       '0',
       count(*)::text
  FROM (SELECT shipper_id FROM warehouse.dim_shipper
         GROUP BY shipper_id HAVING count(*) > 1) d;

-- Source-side duplicates. staging has primary keys, so this should hold - but
-- if the extract were ever changed to drop them, this is what would catch it.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'DUP-007', 'duplicates', 'ERROR',
       'staging.order_details: one row per (order_id, product_id)',
       '0',
       count(*)::text
  FROM (SELECT order_id, product_id FROM staging.order_details
         GROUP BY order_id, product_id HAVING count(*) > 1) d;


-- ============================================================================
-- GROUP 2 - SCD Type 2 chain correctness
--
-- These are the tests that distinguish a working Type 2 implementation from
-- one that merely has the columns. Overlaps are blocked by EXCLUDE constraints,
-- so OVERLAP-001..003 verify those constraints are still in place; the gap and
-- ordering checks cover conditions no constraint enforces.
-- ============================================================================

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'SCD-001', 'scd2', 'ERROR',
       'dim_customer: no overlapping validity periods for one customer',
       '0',
       count(*)::text
  FROM warehouse.dim_customer a
  JOIN warehouse.dim_customer b
    ON a.customer_id = b.customer_id
   AND a.customer_key < b.customer_key
   AND a.validity && b.validity;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'SCD-002', 'scd2', 'ERROR',
       'dim_product: no overlapping validity periods for one product',
       '0',
       count(*)::text
  FROM warehouse.dim_product a
  JOIN warehouse.dim_product b
    ON a.product_id = b.product_id
   AND a.product_key < b.product_key
   AND a.validity && b.validity;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'SCD-003', 'scd2', 'ERROR',
       'dim_employee: no overlapping validity periods for one employee',
       '0',
       count(*)::text
  FROM warehouse.dim_employee a
  JOIN warehouse.dim_employee b
    ON a.employee_id = b.employee_id
   AND a.employee_key < b.employee_key
   AND a.validity && b.validity;

-- A GAP is the mirror image of an overlap and no constraint prevents it: if a
-- version is closed and its successor starts later, the entity has a period
-- with no valid row, and any as-at query over that window silently returns
-- nothing for that customer.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'SCD-004', 'scd2', 'ERROR',
       'dim_customer: version chain is contiguous (no gaps between versions)',
       '0',
       count(*)::text
  FROM (
      SELECT customer_id,
             valid_to,
             lead(valid_from) OVER (PARTITION BY customer_id ORDER BY valid_from) AS next_from
        FROM warehouse.dim_customer
       WHERE customer_key <> -1
  ) chain
 WHERE valid_to IS NOT NULL
   AND next_from IS NOT NULL
   AND next_from <> valid_to;

-- Every entity must have exactly one open-ended version. Zero means the entity
-- has been closed out and nothing replaced it - it vanishes from every current
-- view without ever raising an error.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'SCD-005', 'scd2', 'ERROR',
       'dim_customer: every customer has exactly one current version',
       '0',
       count(*)::text
  FROM (SELECT customer_id
          FROM warehouse.dim_customer
         WHERE customer_key <> -1
         GROUP BY customer_id
        HAVING count(*) FILTER (WHERE is_current) <> 1) d;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'SCD-006', 'scd2', 'ERROR',
       'all SCD2 dimensions: valid_to is always after valid_from',
       '0',
       (
           (SELECT count(*) FROM warehouse.dim_customer WHERE valid_to IS NOT NULL AND valid_to <= valid_from)
         + (SELECT count(*) FROM warehouse.dim_product  WHERE valid_to IS NOT NULL AND valid_to <= valid_from)
         + (SELECT count(*) FROM warehouse.dim_employee WHERE valid_to IS NOT NULL AND valid_to <= valid_from)
       )::text;


-- ============================================================================
-- GROUP 3 - Referential integrity and orphaned facts
--
-- Foreign keys make true orphans impossible, so these checks target what the
-- foreign keys cannot see: rows pointing at the Unknown member (a resolution
-- FAILURE that the FK is perfectly happy with), and staging-side integrity
-- where there are deliberately no foreign keys at all.
-- ============================================================================

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'RI-001', 'referential', 'ERROR',
       'fact_sales_order_line: no dimension key outside its dimension',
       '0',
       count(*)::text
  FROM warehouse.fact_sales_order_line f
 WHERE NOT EXISTS (SELECT 1 FROM warehouse.dim_customer d WHERE d.customer_key = f.customer_key)
    OR NOT EXISTS (SELECT 1 FROM warehouse.dim_product  d WHERE d.product_key  = f.product_key)
    OR NOT EXISTS (SELECT 1 FROM warehouse.dim_employee d WHERE d.employee_key = f.employee_key)
    OR NOT EXISTS (SELECT 1 FROM warehouse.dim_shipper  d WHERE d.shipper_key  = f.shipper_key)
    OR NOT EXISTS (SELECT 1 FROM warehouse.dim_date     d WHERE d.date_key     = f.order_date_key);

-- Unknown-member usage is the check a foreign key can never perform. These rows
-- are valid and correctly retained, but each one is revenue that could not be
-- attributed, so the count must be watched rather than assumed to be zero.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'RI-002', 'referential', 'WARN',
       'fact_sales_order_line: rows resolved to the Unknown customer',
       '0',
       count(*)::text
  FROM warehouse.fact_sales_order_line WHERE customer_key = -1;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'RI-003', 'referential', 'WARN',
       'fact_sales_order_line: rows resolved to the Unknown product',
       '0',
       count(*)::text
  FROM warehouse.fact_sales_order_line WHERE product_key = -1;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'RI-004', 'referential', 'WARN',
       'fact_sales_order_line: order_date unresolved (date_key = -1)',
       '0',
       count(*)::text
  FROM warehouse.fact_sales_order_line WHERE order_date_key = -1;

-- Staging integrity: no foreign keys here by design, so these are the only
-- thing standing between a broken extract and a warehouse full of Unknowns.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'RI-005', 'referential', 'ERROR',
       'staging.order_details: every order_id exists in staging.orders',
       '0',
       count(*)::text
  FROM staging.order_details od
 WHERE NOT EXISTS (SELECT 1 FROM staging.orders o WHERE o.order_id = od.order_id);

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'RI-006', 'referential', 'ERROR',
       'staging.order_details: every product_id exists in staging.products',
       '0',
       count(*)::text
  FROM staging.order_details od
 WHERE NOT EXISTS (SELECT 1 FROM staging.products p WHERE p.product_id = od.product_id);

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'RI-007', 'referential', 'WARN',
       'staging.orders: every non-null customer_id exists in staging.customers',
       '0',
       count(*)::text
  FROM staging.orders o
 WHERE o.customer_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM staging.customers c WHERE c.customer_id = o.customer_id);

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'RI-008', 'referential', 'ERROR',
       'staging.products: every non-null category_id exists in staging.categories',
       '0',
       count(*)::text
  FROM staging.products p
 WHERE p.category_id IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM staging.categories c WHERE c.category_id = p.category_id);

-- The reverse direction: an order with no lines is not a constraint violation,
-- but it is either a data-entry error or a cancelled order that should have
-- been filtered. Either way somebody should know.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'RI-009', 'referential', 'WARN',
       'staging.orders: every order has at least one order line',
       '0',
       count(*)::text
  FROM staging.orders o
 WHERE NOT EXISTS (SELECT 1 FROM staging.order_details od WHERE od.order_id = o.order_id);


-- ============================================================================
-- GROUP 4 - Unexpected NULLs
--
-- Not "any NULL anywhere" - NULL is legitimate in most of these columns. These
-- target columns where a NULL means a broken load rather than absent data.
-- ============================================================================

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'NUL-001', 'nulls', 'ERROR',
       'dim_customer: company_name never null (business key attribute)',
       '0', count(*)::text
  FROM warehouse.dim_customer WHERE company_name IS NULL;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'NUL-002', 'nulls', 'ERROR',
       'dim_product: product_name never null',
       '0', count(*)::text
  FROM warehouse.dim_product WHERE product_name IS NULL;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'NUL-003', 'nulls', 'ERROR',
       'dim_employee: full_name populated for every real employee',
       '0', count(*)::text
  FROM warehouse.dim_employee WHERE employee_key <> -1 AND full_name IS NULL;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'NUL-004', 'nulls', 'ERROR',
       'SCD2 dimensions: row_hash populated for every real row',
       '0',
       (
         (SELECT count(*) FROM warehouse.dim_customer WHERE customer_key <> -1 AND row_hash IS NULL)
       + (SELECT count(*) FROM warehouse.dim_product  WHERE product_key  <> -1 AND row_hash IS NULL)
       + (SELECT count(*) FROM warehouse.dim_employee WHERE employee_key <> -1 AND row_hash IS NULL)
       )::text;

-- A fact row with no batch id cannot be traced to the load that produced it,
-- which removes the ability to roll back a bad load without a full restore.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'NUL-005', 'nulls', 'ERROR',
       'fact_sales_order_line: every row carries a load batch id',
       '0', count(*)::text
  FROM warehouse.fact_sales_order_line WHERE dw_load_batch_id IS NULL;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'NUL-006', 'nulls', 'WARN',
       'staging.orders: customer_id populated (null means unattributable revenue)',
       '0', count(*)::text
  FROM staging.orders WHERE customer_id IS NULL;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'NUL-007', 'nulls', 'WARN',
       'staging.orders: order_date populated',
       '0', count(*)::text
  FROM staging.orders WHERE order_date IS NULL;


-- ============================================================================
-- GROUP 5 - Business rules, including the constraint that could not be ported
-- ============================================================================

-- The reference implementation declares:
--     CONSTRAINT CK_Birthdate CHECK (BirthDate < getdate())
-- PostgreSQL rejects this as a CHECK constraint because CURRENT_TIMESTAMP is
-- STABLE, not IMMUTABLE. Asserted here instead - which is arguably where it
-- belonged all along, since SQL Server never re-verifies it against existing
-- rows either: the constraint is only evaluated on write, so a row that was
-- valid in 1998 is never re-checked.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'BIZ-001', 'business', 'ERROR',
       'dim_employee: birth_date in the past (ports source CK_Birthdate)',
       '0', count(*)::text
  FROM warehouse.dim_employee
 WHERE birth_date IS NOT NULL AND birth_date >= CURRENT_DATE;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'BIZ-002', 'business', 'ERROR',
       'dim_employee: nobody is their own manager',
       '0', count(*)::text
  FROM warehouse.dim_employee
 WHERE manager_employee_id IS NOT NULL AND manager_employee_id = employee_id;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'BIZ-003', 'business', 'ERROR',
       'fact_sales_order_line: discount between 0 and 1',
       '0', count(*)::text
  FROM warehouse.fact_sales_order_line
 WHERE discount_pct < 0 OR discount_pct > 1;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'BIZ-004', 'business', 'ERROR',
       'fact_sales_order_line: quantity strictly positive',
       '0', count(*)::text
  FROM warehouse.fact_sales_order_line WHERE quantity <= 0;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'BIZ-005', 'business', 'ERROR',
       'fact_sales_order_line: net never exceeds gross',
       '0', count(*)::text
  FROM warehouse.fact_sales_order_line WHERE net_amount > gross_amount;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'BIZ-006', 'business', 'ERROR',
       'fact_order_fulfilment: shipped never before ordered',
       '0', count(*)::text
  FROM warehouse.fact_order_fulfilment
 WHERE shipped_date IS NOT NULL AND order_date IS NOT NULL AND shipped_date < order_date;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'BIZ-007', 'business', 'ERROR',
       'fact_order_fulfilment: freight never negative',
       '0', count(*)::text
  FROM warehouse.fact_order_fulfilment WHERE freight_amount < 0;

-- dim_date must be gapless. A single missing day silently sends every fact for
-- that day to the Unknown member, and the revenue disappears from every
-- date-filtered report without any error.
INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'BIZ-008', 'business', 'ERROR',
       'dim_date: no missing days between min and max date',
       '0',
       (
         SELECT (max(full_date) - min(full_date) + 1) - count(*)
           FROM warehouse.dim_date WHERE date_key <> -1
       )::text;

INSERT INTO test_results (check_id, category, severity, description, expected, actual)
SELECT 'BIZ-009', 'business', 'ERROR',
       'dim_date: date_key always agrees with full_date',
       '0', count(*)::text
  FROM warehouse.dim_date
 WHERE date_key <> -1
   AND date_key <> warehouse.to_date_key(full_date);


-- ============================================================================
-- Report
-- ============================================================================
\echo ''
\echo '================= VALIDATION RESULTS ================='

SELECT check_id, severity, description, expected, actual, status
  FROM test_results
 ORDER BY CASE status WHEN 'FAIL' THEN 0 ELSE 1 END,
          CASE severity WHEN 'ERROR' THEN 0 ELSE 1 END,
          check_id;

\echo ''
\echo '----------------- SUMMARY -----------------'

SELECT category,
       count(*)                                                   AS checks,
       count(*) FILTER (WHERE status = 'PASS')                     AS passed,
       count(*) FILTER (WHERE status = 'FAIL' AND severity='ERROR') AS failed_error,
       count(*) FILTER (WHERE status = 'FAIL' AND severity='WARN')  AS failed_warn
  FROM test_results
 GROUP BY ROLLUP (category)
 ORDER BY category NULLS LAST;

-- ----------------------------------------------------------------------------
-- Gate: abort with a non-zero exit code if any ERROR-severity check failed, so
-- this script is usable as a CI step or a post-load guard rather than something
-- a human has to read and interpret.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    v_failed integer;
    v_detail text;
BEGIN
    SELECT count(*), string_agg(check_id || ' (' || description || ')', E'\n  ')
      INTO v_failed, v_detail
      FROM test_results
     WHERE status = 'FAIL' AND severity = 'ERROR';

    IF v_failed > 0 THEN
        RAISE EXCEPTION E'VALIDATION FAILED: % error-severity check(s)\n  %',
                        v_failed, v_detail
              USING ERRCODE = 'data_exception';
    END IF;

    RAISE NOTICE 'VALIDATION PASSED: no error-severity failures.';
END $$;
