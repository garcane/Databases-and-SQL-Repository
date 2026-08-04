-- ============================================================================
-- 00_presentation_views.sql
--
-- The consumer-facing layer. Analysts and BI tools connect here and nowhere
-- else, which is what makes the warehouse schema free to change underneath.
--
-- Rules this layer follows:
--   * No surrogate keys are exposed. They are an implementation detail; an
--     analyst joining on customer_key would couple a dashboard to the loader.
--   * Business names, not table names. `net_revenue`, not `net_amount`.
--   * Current dimension versions by default. Views that deliberately expose
--     history say so in their name and comment.
--   * No view depends on another view more than one level deep, so a query
--     plan stays legible in EXPLAIN.
-- ============================================================================

SET search_path = presentation, warehouse, public;

-- ============================================================================
-- Role-playing date dimensions
--
-- dim_date is joined three times by the sales fact, in three different roles.
-- Aliasing it inline in every query works but produces column names like
-- d1.year_number that nobody can read. These views give each role its own name
-- and its own column prefix - the standard Kimball treatment, and effectively
-- free: PostgreSQL inlines a simple view into the calling query, so there is no
-- extra scan.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.dim_order_date AS
SELECT date_key       AS order_date_key,
       full_date      AS order_date,
       year_number    AS order_year,
       quarter_name   AS order_quarter,
       month_number   AS order_month_number,
       month_name     AS order_month,
       year_month     AS order_year_month,
       fiscal_year    AS order_fiscal_year,
       is_weekend     AS order_is_weekend
  FROM warehouse.dim_date;

CREATE OR REPLACE VIEW presentation.dim_shipped_date AS
SELECT date_key       AS shipped_date_key,
       full_date      AS shipped_date,
       year_number    AS shipped_year,
       quarter_name   AS shipped_quarter,
       month_name     AS shipped_month
  FROM warehouse.dim_date;

COMMENT ON VIEW presentation.dim_order_date IS
    'Role-playing view of dim_date in the order-date role.';
COMMENT ON VIEW presentation.dim_shipped_date IS
    'Role-playing view of dim_date in the shipped-date role.';

-- ============================================================================
-- presentation.sales
--
-- The workhorse: the sales star, fully resolved, one row per order line.
-- Almost every question below can be answered by aggregating this view.
--
-- Inner joins throughout, and that is safe by construction: every fact foreign
-- key is NOT NULL and points at a real dimension row, falling back to the
-- Unknown member rather than NULL. There is no row this join can drop.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.sales AS
SELECT
    -- Degenerate dimension
    f.order_id,

    -- When
    od.order_date,
    od.order_year,
    od.order_quarter,
    od.order_month,
    od.order_year_month,
    od.order_fiscal_year,
    sd.shipped_date,

    -- Who bought
    c.customer_id,
    c.company_name        AS customer,
    c.city                AS customer_city,
    c.country             AS customer_country,

    -- Who sold
    e.full_name           AS employee,
    e.title               AS employee_title,
    e.manager_name        AS employee_manager,
    e.country             AS employee_country,

    -- What
    p.product_id,
    p.product_name        AS product,
    p.category_name       AS category,
    p.supplier_name       AS supplier,
    p.supplier_country,

    -- How shipped
    s.company_name        AS shipper,

    -- Measures
    f.quantity,
    f.unit_price,
    f.discount_pct,
    f.gross_amount        AS gross_revenue,
    f.discount_amount     AS discount_given,
    f.net_amount          AS net_revenue
FROM warehouse.fact_sales_order_line f
JOIN warehouse.dim_customer      c  ON c.customer_key = f.customer_key
JOIN warehouse.dim_employee      e  ON e.employee_key = f.employee_key
JOIN warehouse.dim_product       p  ON p.product_key  = f.product_key
JOIN warehouse.dim_shipper       s  ON s.shipper_key  = f.shipper_key
JOIN presentation.dim_order_date od ON od.order_date_key = f.order_date_key
LEFT JOIN presentation.dim_shipped_date sd ON sd.shipped_date_key = f.shipped_date_key;

COMMENT ON VIEW presentation.sales IS
    'Fully resolved sales star, one row per order line. The default starting '
    'point for revenue analysis.';

-- ============================================================================
-- presentation.sales_by_category_year
--
-- Replaces the reference implementation's "Category Sales for 1997" and
-- "Product Sales for 1997" views, which hard-code the year in the view body -
-- so a new year means a new view, and 1998 sales were invisible until someone
-- wrote one. Parameterising by grouping instead of by literal is the fix.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.sales_by_category_year AS
SELECT order_year,
       category,
       count(DISTINCT order_id)     AS orders,
       sum(quantity)                AS units_sold,
       sum(gross_revenue)           AS gross_revenue,
       sum(discount_given)          AS discount_given,
       sum(net_revenue)             AS net_revenue,
       -- Discount rate is a ratio and cannot be averaged: it must be
       -- recomputed from the summed components at the reporting grain.
       ROUND(sum(discount_given) / NULLIF(sum(gross_revenue), 0) * 100, 2)
                                    AS discount_rate_pct
  FROM presentation.sales
 GROUP BY order_year, category;

COMMENT ON VIEW presentation.sales_by_category_year IS
    'Revenue by category and year. Replaces the hard-coded "... for 1997" '
    'views in the reference implementation.';

-- ============================================================================
-- presentation.customer_sales_summary
--
-- One row per customer. NULLIF guards the division; a customer with zero
-- orders would otherwise raise a division-by-zero at report time.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.customer_sales_summary AS
SELECT customer_id,
       customer,
       customer_country,
       count(DISTINCT order_id)                          AS orders,
       min(order_date)                                   AS first_order,
       max(order_date)                                   AS latest_order,
       sum(net_revenue)                                  AS lifetime_revenue,
       ROUND(sum(net_revenue) / NULLIF(count(DISTINCT order_id), 0), 2)
                                                         AS avg_order_value
  FROM presentation.sales
 GROUP BY customer_id, customer, customer_country;

COMMENT ON VIEW presentation.customer_sales_summary IS
    'Lifetime revenue and order statistics per customer.';

-- ============================================================================
-- presentation.employee_performance
--
-- Answers the exercise question "employee sales performance" without the
-- correlated subqueries the original scripts used.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.employee_performance AS
SELECT employee,
       employee_title,
       employee_manager,
       employee_country,
       count(DISTINCT order_id)          AS orders,
       count(DISTINCT customer_id)       AS customers_served,
       sum(net_revenue)                  AS net_revenue,
       ROUND(sum(net_revenue) / NULLIF(count(DISTINCT order_id), 0), 2)
                                         AS avg_order_value
  FROM presentation.sales
 GROUP BY employee, employee_title, employee_manager, employee_country;

COMMENT ON VIEW presentation.employee_performance IS
    'Sales performance per employee, including customers served.';

-- ============================================================================
-- presentation.order_fulfilment_performance
--
-- Reads the order-grain fact, NOT the sales view - which is the whole point of
-- modelling the two separately. Freight and order counts here are correct
-- because each order contributes exactly one row.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.order_fulfilment_performance AS
SELECT d.year_number                              AS order_year,
       d.quarter_name                             AS order_quarter,
       s.company_name                             AS shipper,
       c.country                                  AS customer_country,
       count(*)                                   AS orders,
       count(*) FILTER (WHERE f.is_shipped)       AS shipped_orders,
       count(*) FILTER (WHERE f.is_late)          AS late_orders,
       ROUND(100.0 * count(*) FILTER (WHERE f.is_late)
             / NULLIF(count(*) FILTER (WHERE f.is_shipped), 0), 2)
                                                  AS late_pct,
       ROUND(avg(f.days_to_ship), 1)              AS avg_days_to_ship,
       sum(f.freight_amount)                      AS total_freight,
       ROUND(avg(f.freight_amount), 2)            AS avg_freight
  FROM warehouse.fact_order_fulfilment f
  JOIN warehouse.dim_date     d ON d.date_key    = f.order_date_key
  JOIN warehouse.dim_shipper  s ON s.shipper_key = f.shipper_key
  JOIN warehouse.dim_customer c ON c.customer_key = f.customer_key
 GROUP BY d.year_number, d.quarter_name, s.company_name, c.country;

COMMENT ON VIEW presentation.order_fulfilment_performance IS
    'Delivery performance and freight cost at order grain. Freight is correct '
    'here and would be overstated if taken from the line-grain sales view.';

-- ============================================================================
-- presentation.customer_history
--
-- The one view that deliberately exposes SCD Type 2 history: every version of
-- every customer, with the period each was in force. This is what the Type 2
-- machinery is for, and without a view like it the history is invisible to
-- everyone who is not reading the DDL.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.customer_history AS
SELECT customer_id,
       company_name,
       contact_name,
       contact_title,
       city,
       country,
       valid_from,
       COALESCE(valid_to, 'infinity'::timestamptz) AS valid_to,
       is_current,
       row_number() OVER (PARTITION BY customer_id ORDER BY valid_from) AS version_number
  FROM warehouse.dim_customer
 WHERE customer_key <> -1;

COMMENT ON VIEW presentation.customer_history IS
    'Every SCD Type 2 version of every customer with its validity period.';
