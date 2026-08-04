-- ============================================================================
-- explain-analyze-examples.sql
--
-- Query tuning worked examples. Every plan and timing below was MEASURED on
-- PostgreSQL 18.4 against this warehouse - none are illustrative or from
-- memory. Re-run any block to reproduce them.
--
-- Read EXPLAIN plans bottom-up and inside-out. The numbers that matter:
--   actual rows vs estimated rows  - a large gap means bad statistics, and the
--                                    planner is choosing joins on bad guesses
--   Buffers                        - pages touched; the truest measure of work,
--                                    and unlike timing it is not noisy
--   Rows Removed by Filter         - work done to produce nothing
--   Heap Fetches (index-only scan) - non-zero means the visibility map is stale
--
-- ALWAYS use EXPLAIN (ANALYZE, BUFFERS). Plain EXPLAIN shows estimates only,
-- and estimates are exactly what you are trying to verify.
-- ============================================================================


-- ============================================================================
-- 1. The warehouse at its real size: 2,155 fact rows
--
-- The honest starting point. At this volume the whole fact table is 28 pages
-- and fits in shared buffers, so index choice is nearly irrelevant - and the
-- planner knows it.
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT p.category_name, sum(f.net_amount)
  FROM warehouse.fact_sales_order_line f
  JOIN warehouse.dim_product p ON p.product_key = f.product_key
 WHERE f.order_date_key BETWEEN 19970101 AND 19971231
 GROUP BY p.category_name;

-- MEASURED:
--   HashAggregate (actual rows=8)
--     ->  Hash Join (actual rows=1059)
--           ->  Index Scan using ix_fsol_order_date  (actual rows=1059)
--                 Index Cond: (order_date_key >= 19970101 AND <= 19971231)
--           ->  Hash (actual rows=78)
--     Buffers: shared hit=31
--
-- 31 buffer hits, zero reads. The index is used even here because the date
-- predicate selects half the table and the index is small.
--
-- The lesson for a portfolio warehouse: do not claim a tuning win you cannot
-- measure. On 2,155 rows there is nothing to win. The examples below therefore
-- scale the data to 2,000,000 rows, where the differences are real.


-- ============================================================================
-- 2. Build a 2,000,000-row fact for the tuning examples
-- ============================================================================
DROP TABLE IF EXISTS scaled_fact;

CREATE TABLE scaled_fact AS
SELECT warehouse.to_date_key(d)       AS order_date_key,
       d                              AS order_date,
       (random() * 77)::int + 1       AS product_key,
       (random() * 91)::int + 1       AS customer_key,
       (random() * 1000)::numeric(10,2) AS net_amount
  FROM (SELECT ('1996-01-01'::date + (random() * 1460)::int) AS d
          FROM generate_series(1, 2000000)) g;

ANALYZE scaled_fact;
-- 2,000,000 rows; 42,302 of them fall in January 1997 (2.1% selectivity).


-- ============================================================================
-- 3. No index: the baseline
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT sum(net_amount) FROM scaled_fact
 WHERE order_date_key BETWEEN 19970101 AND 19970131;

-- MEASURED:
--   Parallel Seq Scan on scaled_fact (actual rows=14100 loops=3)
--     Rows Removed by Filter: 652566
--   Buffers: shared hit=2586 read=10214
--   Execution Time: 366.850 ms
--
-- Three workers read all 12,800 pages and discard 97.9% of what they read.
-- "Rows Removed by Filter: 652566" per worker is the tell.


-- ============================================================================
-- 4. Add a covering index
-- ============================================================================
CREATE INDEX ix_scaled_date ON scaled_fact (order_date_key) INCLUDE (net_amount);
ANALYZE scaled_fact;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT sum(net_amount) FROM scaled_fact
 WHERE order_date_key BETWEEN 19970101 AND 19970131;

-- MEASURED, immediately after the index build:
--   Bitmap Index Scan on ix_scaled_date (actual rows=42302)
--   Execution Time: 227.590 ms          <- only 1.6x better. Why?
--
-- Not an Index ONLY Scan, despite the INCLUDE clause covering net_amount.
-- The planner refuses index-only scans when it cannot prove the rows are
-- visible to every transaction, and that proof lives in the visibility map -
-- which is populated by VACUUM. After a bulk load the map is empty, so every
-- index entry still requires a heap fetch and the INCLUDE buys nothing.
--
-- This is the single most common reason a "covering index" underdelivers, and
-- it is invisible unless you read the node type rather than trusting the index
-- to be used as designed.


-- ============================================================================
-- 5. VACUUM, then the same query again
-- ============================================================================
VACUUM (ANALYZE) scaled_fact;

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT sum(net_amount) FROM scaled_fact
 WHERE order_date_key BETWEEN 19970101 AND 19970131;

-- MEASURED:
--   Index Only Scan using ix_scaled_date (actual rows=42302)
--     Heap Fetches: 0
--   Buffers: shared hit=167
--   Execution Time: 31.420 ms
--
--   vs baseline:  366.850 ms -> 31.420 ms      11.7x faster
--                 12,800 pages -> 167 pages    77x less I/O
--
-- "Heap Fetches: 0" is the confirmation the index is genuinely covering.
--
-- OPERATIONAL CONSEQUENCE: a warehouse load that bulk-inserts and does not
-- VACUUM leaves every covering index in the degraded state of step 4. VACUUM
-- (ANALYZE) belongs at the end of the load, not on autovacuum's schedule -
-- autovacuum is driven by dead tuples, and a pure INSERT load creates none, so
-- it may not fire at all before the morning's reports run.


-- ============================================================================
-- 6. Anti-pattern: a function wrapped around an indexed column
--
-- The most common cause of an unused index in a date-partitioned warehouse.
-- Both queries below ask the identical question over identical rows.
-- ============================================================================

-- SLOW - the index cannot be used.
EXPLAIN (ANALYZE, COSTS OFF)
SELECT sum(net_amount) FROM scaled_fact
 WHERE EXTRACT(YEAR FROM order_date) = 1997
   AND EXTRACT(MONTH FROM order_date) = 1;

-- MEASURED:
--   Parallel Seq Scan on scaled_fact (actual rows=14100 loops=3)
--   Execution Time: 591.902 ms
--
-- The index is on order_date_key, but the predicate is on
-- EXTRACT(... FROM order_date). A B-tree indexes the COLUMN's values, not the
-- values of an expression over it, so the whole index is unusable and the
-- planner falls back to a full scan. The term for a predicate the index can
-- use is "sargable"; this one is not.

-- FAST - the same intent expressed as a range against the bare column.
EXPLAIN (ANALYZE, COSTS OFF)
SELECT sum(net_amount) FROM scaled_fact
 WHERE order_date_key >= 19970101
   AND order_date_key <  19970201;

-- MEASURED:
--   Index Only Scan using ix_scaled_date (actual rows=42302)
--   Execution Time: 94.484 ms           (31 ms once fully warm)
--
--   591.902 ms -> 94.484 ms             6.3x faster, same answer
--
-- Note the half-open range: >= start AND < next-start. Using BETWEEN with an
-- explicit end date is where off-by-one boundary bugs are born, especially
-- against timestamps, where BETWEEN '...-01-31' silently excludes everything
-- after midnight on the 31st.
--
-- If an expression predicate is genuinely unavoidable, PostgreSQL can index
-- the expression itself - a feature SQL Server only reaches via a persisted
-- computed column:
--
--     CREATE INDEX ix_scaled_year ON scaled_fact ((EXTRACT(YEAR FROM order_date)));
--
-- Prefer rewriting the query. An expression index is another object to
-- maintain, and it only serves predicates written exactly that way.


-- ============================================================================
-- 7. Partial indexes: index only the rows queried
--
-- warehouse.dim_customer carries:
--     CREATE UNIQUE INDEX uix_dim_customer_current
--         ON warehouse.dim_customer (customer_id) WHERE is_current;
--
-- Almost every query wants the current version, and in a mature Type 2
-- dimension current rows are a small minority of all rows. A partial index
-- excludes the historical ones entirely: smaller index, fewer levels, and it
-- doubles as the constraint guaranteeing one current row per customer.
-- ============================================================================
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT customer_id, company_name
  FROM warehouse.dim_customer
 WHERE is_current AND country = 'Germany';


-- ============================================================================
-- 8. Statistics: when the planner is wrong, it is usually uninformed
--
-- Compare estimated against actual rows. A gap beyond ~10x means ANALYZE is
-- stale or the column has correlations the planner cannot see.
-- ============================================================================
EXPLAIN (ANALYZE, COSTS ON)
SELECT c.country, count(*)
  FROM warehouse.fact_sales_order_line f
  JOIN warehouse.dim_customer c ON c.customer_key = f.customer_key
 GROUP BY c.country;

-- For genuinely correlated columns - order_date_key and shipped_date_key are
-- correlated here, and the planner assumes independence - extended statistics
-- fix the estimate:
--
--     CREATE STATISTICS stx_fsol_dates (dependencies)
--         ON order_date_key, shipped_date_key
--         FROM warehouse.fact_sales_order_line;
--     ANALYZE warehouse.fact_sales_order_line;


-- ============================================================================
-- Clean up the scaled table
-- ============================================================================
DROP TABLE IF EXISTS scaled_fact;
