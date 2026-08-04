-- ============================================================================
-- quality-checks.sql
--
-- Reconciliation and structural verification. Complements validation.sql:
--
--     validation.sql       is the data internally consistent?
--     quality-checks.sql   does it still agree with the source, and is the
--                          schema still shaped the way it was designed?
--
--     psql -d northwind_dw -v ON_ERROR_STOP=1 -f tests/quality-checks.sql
--
-- Exits non-zero if any ERROR-severity check fails.
--
-- ----------------------------------------------------------------------------
-- The structural checks are the ones that earn their keep over time
-- ----------------------------------------------------------------------------
-- Data tests catch bad loads. Structural tests catch bad MIGRATIONS - a
-- constraint that silently failed to port, an index dropped during a refactor,
-- a foreign key with no supporting index quietly turning every dimension
-- filter into a sequential scan. None of these produce an error; they produce a
-- warehouse that is slower and less trustworthy than the one that was
-- designed, and nobody notices until it matters.
-- ============================================================================

\set ON_ERROR_STOP on
\timing off

DROP TABLE IF EXISTS quality_results;
CREATE TEMP TABLE quality_results (
    check_id     text,
    category     text,
    severity     text,
    description  text,
    expected     text,
    actual       text,
    status       text GENERATED ALWAYS AS (
                     CASE WHEN expected IS NOT DISTINCT FROM actual
                          THEN 'PASS' ELSE 'FAIL' END
                 ) STORED
);


-- ============================================================================
-- GROUP 1 - Source row counts against the canonical Northwind figures
--
-- These are the published Northwind counts. If the extractor is ever changed,
-- this is what catches a silently truncated or duplicated load.
-- ============================================================================
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'CNT-' || lpad(row_number() OVER (ORDER BY t.tbl)::text, 3, '0'),
       'row_counts', 'ERROR',
       'staging.' || t.tbl || ' row count',
       t.expected::text,
       t.actual::text
  FROM (
      SELECT 'categories'           AS tbl,    8 AS expected, (SELECT count(*) FROM staging.categories)           AS actual
      UNION ALL SELECT 'customers',            91, (SELECT count(*) FROM staging.customers)
      UNION ALL SELECT 'employees',             9, (SELECT count(*) FROM staging.employees)
      UNION ALL SELECT 'employee_territories',  49, (SELECT count(*) FROM staging.employee_territories)
      UNION ALL SELECT 'order_details',       2155, (SELECT count(*) FROM staging.order_details)
      UNION ALL SELECT 'orders',               830, (SELECT count(*) FROM staging.orders)
      UNION ALL SELECT 'products',              77, (SELECT count(*) FROM staging.products)
      UNION ALL SELECT 'region',                 4, (SELECT count(*) FROM staging.region)
      UNION ALL SELECT 'shippers',               3, (SELECT count(*) FROM staging.shippers)
      UNION ALL SELECT 'suppliers',             29, (SELECT count(*) FROM staging.suppliers)
      UNION ALL SELECT 'territories',           53, (SELECT count(*) FROM staging.territories)
  ) t;


-- ============================================================================
-- GROUP 2 - Staging to warehouse reconciliation
--
-- The tests that would have caught a partial load, a dropped join condition, or
-- a fact table loaded twice.
-- ============================================================================

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-001', 'reconciliation', 'ERROR',
       'fact_sales_order_line row count matches staging.order_details',
       (SELECT count(*)::text FROM staging.order_details),
       (SELECT count(*)::text FROM warehouse.fact_sales_order_line);

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-002', 'reconciliation', 'ERROR',
       'fact_order_fulfilment row count matches staging.orders',
       (SELECT count(*)::text FROM staging.orders),
       (SELECT count(*)::text FROM warehouse.fact_order_fulfilment);

-- The money test. Revenue computed independently on each side and compared to
-- the penny. If any join, filter or type conversion in the ETL is wrong, this
-- is where it shows up.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-003', 'reconciliation', 'ERROR',
       'net revenue reconciles between staging and warehouse',
       (SELECT to_char(ROUND(SUM(unit_price * quantity * (1 - ROUND(discount::numeric, 4))), 2), 'FM9999999990.00')
          FROM staging.order_details),
       (SELECT to_char(ROUND(SUM(net_amount), 2), 'FM9999999990.00')
          FROM warehouse.fact_sales_order_line);

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-004', 'reconciliation', 'ERROR',
       'gross revenue reconciles between staging and warehouse',
       (SELECT to_char(ROUND(SUM(unit_price * quantity), 2), 'FM9999999990.00') FROM staging.order_details),
       (SELECT to_char(ROUND(SUM(gross_amount), 2), 'FM9999999990.00') FROM warehouse.fact_sales_order_line);

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-005', 'reconciliation', 'ERROR',
       'freight reconciles between staging and the order-grain fact',
       (SELECT to_char(ROUND(SUM(COALESCE(freight, 0)), 2), 'FM9999999990.00') FROM staging.orders),
       (SELECT to_char(ROUND(SUM(freight_amount), 2), 'FM9999999990.00') FROM warehouse.fact_order_fulfilment);

-- Cross-fact consistency. order_line_count is a convenience measure on the
-- order-grain fact and must agree with the line-grain fact it summarises;
-- nothing in the schema forces it to.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-006', 'reconciliation', 'ERROR',
       'fact_order_fulfilment.order_line_count agrees with the line fact',
       '0',
       count(*)::text
  FROM warehouse.fact_order_fulfilment f
  LEFT JOIN (SELECT order_id, count(*) AS n
               FROM warehouse.fact_sales_order_line GROUP BY order_id) l
    ON l.order_id = f.order_id
 WHERE f.order_line_count <> COALESCE(l.n, 0);

-- Dimension coverage: every source entity reached the warehouse.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-007', 'reconciliation', 'ERROR',
       'every staging customer has a current dimension row',
       (SELECT count(*)::text FROM staging.customers),
       (SELECT count(*)::text FROM warehouse.dim_customer WHERE is_current AND customer_key <> -1);

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-008', 'reconciliation', 'ERROR',
       'every staging product has a current dimension row',
       (SELECT count(*)::text FROM staging.products),
       (SELECT count(*)::text FROM warehouse.dim_product WHERE is_current AND product_key <> -1);

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-009', 'reconciliation', 'ERROR',
       'every staging employee has a current dimension row',
       (SELECT count(*)::text FROM staging.employees),
       (SELECT count(*)::text FROM warehouse.dim_employee WHERE is_current AND employee_key <> -1);

-- Presentation must not invent or lose revenue relative to the warehouse.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-010', 'reconciliation', 'ERROR',
       'presentation.sales revenue matches the fact table',
       (SELECT to_char(ROUND(SUM(net_amount), 2), 'FM9999999990.00') FROM warehouse.fact_sales_order_line),
       (SELECT to_char(ROUND(SUM(net_revenue), 2), 'FM9999999990.00') FROM presentation.sales);

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'REC-011', 'reconciliation', 'ERROR',
       'presentation.sales row count matches the fact table (no join fan-out)',
       (SELECT count(*)::text FROM warehouse.fact_sales_order_line),
       (SELECT count(*)::text FROM presentation.sales);


-- ============================================================================
-- GROUP 3 - Structural verification
--
-- Proof the designed schema is the deployed schema.
-- ============================================================================

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'STR-001', 'structure', 'ERROR',
       'every warehouse table has a primary key',
       '0',
       count(*)::text
  FROM information_schema.tables t
 WHERE t.table_schema = 'warehouse'
   AND t.table_type = 'BASE TABLE'
   AND NOT EXISTS (
         SELECT 1 FROM information_schema.table_constraints c
          WHERE c.table_schema = t.table_schema
            AND c.table_name  = t.table_name
            AND c.constraint_type = 'PRIMARY KEY');

-- The SCD2 guarantee is only real while the EXCLUDE constraints exist. If one
-- were dropped in a refactor, overlapping versions would become possible and
-- nothing else would notice until the history was already corrupt.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'STR-002', 'structure', 'ERROR',
       'all three SCD2 dimensions still carry an EXCLUDE constraint',
       '3',
       count(*)::text
  FROM pg_constraint c
  JOIN pg_class      t ON t.oid = c.conrelid
  JOIN pg_namespace  n ON n.oid = t.relnamespace
 WHERE n.nspname = 'warehouse'
   AND c.contype = 'x'
   AND t.relname IN ('dim_customer', 'dim_product', 'dim_employee');

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'STR-003', 'structure', 'ERROR',
       'both fact tables still enforce their declared grain (UNIQUE)',
       '2',
       count(*)::text
  FROM pg_constraint c
  JOIN pg_class      t ON t.oid = c.conrelid
  JOIN pg_namespace  n ON n.oid = t.relnamespace
 WHERE n.nspname = 'warehouse'
   AND c.contype = 'u'
   AND c.conname IN ('uq_fact_sales_order_line_grain', 'uq_fact_order_fulfilment_grain');

-- Hot-path dimension foreign keys on a fact must have a supporting index.
-- PostgreSQL creates none automatically, and the absence is invisible until the
-- fact table is large enough for the sequential scans to hurt.
--
-- Scoped deliberately to the five keys that queries actually filter and group
-- by. Six further foreign keys are intentionally left unindexed, and asserting
-- "every FK has an index" would fail on them forever:
--
--   required_date_key, shipped_date_key (both facts)  secondary role-playing
--       dates. Reports filter on order date and read the others as attributes;
--       an index on each would be written on every load and read almost never.
--   dw_load_batch_id (both facts)  lineage only, queried during incident
--       investigation against a table small enough to scan.
--
-- Indexing every foreign key by reflex is how a fact table ends up spending
-- more time maintaining indexes than storing data.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'STR-004', 'structure', 'ERROR',
       'every hot-path fact dimension FK has a supporting index',
       '0',
       count(*)::text
  FROM (
      SELECT c.conrelid,
             c.conkey[1] AS first_col
        FROM pg_constraint c
        JOIN pg_class      t ON t.oid = c.conrelid
        JOIN pg_namespace  n ON n.oid = t.relnamespace
        JOIN pg_attribute  a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
       WHERE n.nspname = 'warehouse'
         AND c.contype = 'f'
         AND t.relname LIKE 'fact_%'
         AND a.attname IN ('customer_key', 'employee_key', 'product_key',
                           'shipper_key', 'order_date_key')
  ) fk
 WHERE NOT EXISTS (
         SELECT 1 FROM pg_index i
          WHERE i.indrelid = fk.conrelid
            AND i.indkey[0] = fk.first_col
       );

-- Every dimension must have its Unknown member, or the loaders' COALESCE to -1
-- would violate the foreign key and the whole load would fail.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'STR-005', 'structure', 'ERROR',
       'all five dimensions have an Unknown member at key -1',
       '5',
       (
         (SELECT count(*) FROM warehouse.dim_customer WHERE customer_key = -1)
       + (SELECT count(*) FROM warehouse.dim_product  WHERE product_key  = -1)
       + (SELECT count(*) FROM warehouse.dim_employee WHERE employee_key = -1)
       + (SELECT count(*) FROM warehouse.dim_shipper  WHERE shipper_key  = -1)
       + (SELECT count(*) FROM warehouse.dim_date     WHERE date_key     = -1)
       )::text;

-- Duplicate indexes: the reference implementation carries eight pairs of them
-- (CustomerID and CustomersOrders both on Orders(CustomerID), and so on). They
-- cost write throughput and buy nothing. This asserts the port did not inherit
-- the habit.
--
-- indpred MUST be part of the grouping. Each SCD2 dimension carries both
-- ix_..._natural on the natural key and uix_..._current on the same key WHERE
-- is_current. Identical column list, entirely different indexes: one supports
-- as-at history lookups across all versions, the other enforces the
-- one-current-row constraint over a fraction of the rows. Grouping on indkey
-- alone reports all three dimensions as duplicated - a false positive that
-- would push someone to drop an index the correctness of the model depends on.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'STR-006', 'structure', 'WARN',
       'no duplicate indexes (same table, same columns, same predicate)',
       '0',
       count(*)::text
  FROM (
      SELECT i.indrelid, i.indkey, i.indpred, count(*) AS n
        FROM pg_index i
        JOIN pg_class     c  ON c.oid = i.indrelid
        JOIN pg_namespace ns ON ns.oid = c.relnamespace
       WHERE ns.nspname IN ('warehouse', 'staging')
       GROUP BY i.indrelid, i.indkey, i.indpred
      HAVING count(*) > 1
  ) d;

-- 14 = 8 analytical views (00_presentation_views.sql, including the two
-- role-playing date views) + 6 ports of the SQL Server originals
-- (10_ported_views.sql).
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'STR-007', 'structure', 'ERROR',
       'all expected presentation views exist',
       '14',
       count(*)::text
  FROM information_schema.views
 WHERE table_schema = 'presentation';


-- ============================================================================
-- GROUP 4 - ETL health
-- ============================================================================

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'ETL-001', 'etl', 'ERROR',
       'the most recent load batch succeeded',
       'SUCCEEDED',
       COALESCE((SELECT status FROM etl.load_batch ORDER BY load_batch_id DESC LIMIT 1), 'NO BATCHES');

-- A batch left RUNNING means a load died without its handler firing. The unique
-- partial index blocks a second concurrent batch, so a stuck row also blocks
-- every future load until it is resolved.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'ETL-002', 'etl', 'ERROR',
       'no load batch stuck in RUNNING',
       '0',
       (SELECT count(*)::text FROM etl.load_batch WHERE status = 'RUNNING');

INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'ETL-003', 'etl', 'WARN',
       'no failed batches in the last 24 hours',
       '0',
       (SELECT count(*)::text FROM etl.load_batch
         WHERE status = 'FAILED' AND started_at > CURRENT_TIMESTAMP - INTERVAL '24 hours');

-- Lineage completeness: every warehouse row traceable to the batch that wrote it.
INSERT INTO quality_results (check_id, category, severity, description, expected, actual)
SELECT 'ETL-004', 'etl', 'ERROR',
       'every fact row references a real load batch',
       '0',
       count(*)::text
  FROM warehouse.fact_sales_order_line f
 WHERE f.dw_load_batch_id IS NULL
    OR NOT EXISTS (SELECT 1 FROM etl.load_batch b WHERE b.load_batch_id = f.dw_load_batch_id);


-- ============================================================================
-- Report
-- ============================================================================
\echo ''
\echo '================= QUALITY CHECK RESULTS ================='

SELECT check_id, severity, description, expected, actual, status
  FROM quality_results
 ORDER BY CASE status WHEN 'FAIL' THEN 0 ELSE 1 END,
          CASE severity WHEN 'ERROR' THEN 0 ELSE 1 END,
          check_id;

\echo ''
\echo '----------------- DATA PROFILE (informational) -----------------'

SELECT 'dim_customer'  AS table_name, count(*) AS rows,
       count(*) FILTER (WHERE is_current) AS current_rows,
       count(DISTINCT customer_id)        AS distinct_entities
  FROM warehouse.dim_customer
UNION ALL
SELECT 'dim_product', count(*), count(*) FILTER (WHERE is_current), count(DISTINCT product_id)
  FROM warehouse.dim_product
UNION ALL
SELECT 'dim_employee', count(*), count(*) FILTER (WHERE is_current), count(DISTINCT employee_id)
  FROM warehouse.dim_employee
UNION ALL
SELECT 'dim_shipper', count(*), count(*), count(DISTINCT shipper_id)
  FROM warehouse.dim_shipper
UNION ALL
SELECT 'dim_date', count(*), count(*), count(DISTINCT date_key)
  FROM warehouse.dim_date
UNION ALL
SELECT 'fact_sales_order_line', count(*), count(*), count(DISTINCT order_id)
  FROM warehouse.fact_sales_order_line
UNION ALL
SELECT 'fact_order_fulfilment', count(*), count(*), count(DISTINCT order_id)
  FROM warehouse.fact_order_fulfilment
ORDER BY table_name;

\echo ''
\echo '----------------- SUMMARY -----------------'

SELECT category,
       count(*)                                                     AS checks,
       count(*) FILTER (WHERE status = 'PASS')                       AS passed,
       count(*) FILTER (WHERE status = 'FAIL' AND severity = 'ERROR') AS failed_error,
       count(*) FILTER (WHERE status = 'FAIL' AND severity = 'WARN')  AS failed_warn
  FROM quality_results
 GROUP BY ROLLUP (category)
 ORDER BY category NULLS LAST;

DO $$
DECLARE
    v_failed integer;
    v_detail text;
BEGIN
    SELECT count(*), string_agg(check_id || ' (' || description || ')', E'\n  ')
      INTO v_failed, v_detail
      FROM quality_results
     WHERE status = 'FAIL' AND severity = 'ERROR';

    IF v_failed > 0 THEN
        RAISE EXCEPTION E'QUALITY CHECKS FAILED: % error-severity check(s)\n  %',
                        v_failed, v_detail
              USING ERRCODE = 'data_exception';
    END IF;

    RAISE NOTICE 'QUALITY CHECKS PASSED: no error-severity failures.';
END $$;
