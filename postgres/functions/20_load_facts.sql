-- ============================================================================
-- 20_load_facts.sql
--
-- Fact loaders. Run after 10_load_dimensions.sql - facts resolve surrogate
-- keys from the dimensions, so the dimensions must be current first.
--
-- ----------------------------------------------------------------------------
-- How surrogate keys are resolved, and the honest caveat
-- ----------------------------------------------------------------------------
-- Each fact row looks up the dimension version that is CURRENT at load time
-- (is_current), not the version that was in force on the order date.
--
-- That is the correct behaviour for this warehouse, but it is worth being
-- explicit about why, because "SCD Type 2" is often assumed to mean facts are
-- matched to historical versions:
--
--   * The source is a static extract. Every dimension row was created by the
--     initial load, so its validity begins at the load timestamp - long after
--     1996-1998, when the orders were placed. Matching an order date against
--     those ranges would resolve every fact to the Unknown member.
--
--   * Type 2 pays off from the load onward: once an attribute changes, orders
--     loaded before the change stay pointed at the old version and orders after
--     it point at the new one. History is preserved going forward, which is
--     what Type 2 is for.
--
--   * Retrospectively reconstructing pre-warehouse history is not possible from
--     this source: the OLTP system keeps no attribute history to reconstruct it
--     from. Inventing effective dates would fabricate data.
--
-- Both loaders are idempotent via ON CONFLICT on the grain constraint, so a
-- re-run corrects rather than duplicates.
-- ============================================================================

-- ============================================================================
-- warehouse.load_fact_sales_order_line
--
-- Grain: one row per product per order, taken straight from staging.order_details.
-- ============================================================================
CREATE OR REPLACE FUNCTION warehouse.load_fact_sales_order_line(
    p_batch_id bigint
)
RETURNS TABLE (rows_inserted bigint, rows_updated bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_before   bigint;
    v_after    bigint;
    v_affected bigint;
BEGIN
    SELECT count(*) INTO v_before FROM warehouse.fact_sales_order_line;

    INSERT INTO warehouse.fact_sales_order_line (
        order_id, product_id,
        customer_key, employee_key, product_key, shipper_key,
        order_date_key, required_date_key, shipped_date_key,
        quantity, unit_price, discount_pct,
        dw_load_batch_id
    )
    SELECT
        od.order_id,
        od.product_id,
        -- COALESCE to the Unknown member: an unresolvable lookup must not drop
        -- the sale. Revenue that cannot be attributed is still revenue, and a
        -- fact silently missing from the warehouse is far worse than one
        -- attributed to 'Unknown' where it is visible and countable.
        COALESCE(dc.customer_key, -1),
        COALESCE(de.employee_key, -1),
        COALESCE(dp.product_key,  -1),
        COALESCE(ds.shipper_key,  -1),
        warehouse.to_date_key(o.order_date::date),
        warehouse.to_date_key(o.required_date::date),
        warehouse.to_date_key(o.shipped_date::date),
        od.quantity,
        od.unit_price,
        -- real -> numeric(5,4). The source stores discount as `real`, a binary
        -- float: 0.15 is held as 0.150000005960464. Rounding at the warehouse
        -- boundary stops that artefact propagating into every revenue figure.
        ROUND(od.discount::numeric, 4),
        p_batch_id
    FROM staging.order_details od
    JOIN staging.orders o
      ON o.order_id = od.order_id
    LEFT JOIN warehouse.dim_customer dc
      ON dc.customer_id = o.customer_id AND dc.is_current
    LEFT JOIN warehouse.dim_employee de
      ON de.employee_id = o.employee_id AND de.is_current
    LEFT JOIN warehouse.dim_product dp
      ON dp.product_id = od.product_id AND dp.is_current
    LEFT JOIN warehouse.dim_shipper ds
      ON ds.shipper_id = o.ship_via
    ON CONFLICT ON CONSTRAINT uq_fact_sales_order_line_grain DO UPDATE
       SET customer_key      = EXCLUDED.customer_key,
           employee_key      = EXCLUDED.employee_key,
           product_key       = EXCLUDED.product_key,
           shipper_key       = EXCLUDED.shipper_key,
           order_date_key    = EXCLUDED.order_date_key,
           required_date_key = EXCLUDED.required_date_key,
           shipped_date_key  = EXCLUDED.shipped_date_key,
           quantity          = EXCLUDED.quantity,
           unit_price        = EXCLUDED.unit_price,
           discount_pct      = EXCLUDED.discount_pct,
           dw_load_batch_id  = EXCLUDED.dw_load_batch_id
     -- Skip rows that have not actually changed. Without this guard every
     -- re-run rewrites all 2,155 rows: each rewrite is a new row version that
     -- VACUUM must later reclaim, and it destroys the audit value of
     -- dw_load_batch_id by restamping untouched facts with the latest batch.
     WHERE (warehouse.fact_sales_order_line.customer_key,
            warehouse.fact_sales_order_line.employee_key,
            warehouse.fact_sales_order_line.product_key,
            warehouse.fact_sales_order_line.shipper_key,
            warehouse.fact_sales_order_line.order_date_key,
            warehouse.fact_sales_order_line.required_date_key,
            warehouse.fact_sales_order_line.shipped_date_key,
            warehouse.fact_sales_order_line.quantity,
            warehouse.fact_sales_order_line.unit_price,
            warehouse.fact_sales_order_line.discount_pct)
           IS DISTINCT FROM
           (EXCLUDED.customer_key, EXCLUDED.employee_key, EXCLUDED.product_key,
            EXCLUDED.shipper_key, EXCLUDED.order_date_key,
            EXCLUDED.required_date_key, EXCLUDED.shipped_date_key,
            EXCLUDED.quantity, EXCLUDED.unit_price, EXCLUDED.discount_pct);

    GET DIAGNOSTICS v_affected = ROW_COUNT;
    SELECT count(*) INTO v_after FROM warehouse.fact_sales_order_line;

    RETURN QUERY SELECT v_after - v_before, v_affected - (v_after - v_before);
END;
$$;

COMMENT ON FUNCTION warehouse.load_fact_sales_order_line(bigint) IS
    'Loads the transaction-grain sales fact. Idempotent via the grain '
    'constraint. Unresolvable dimension lookups map to the Unknown member.';

-- ============================================================================
-- warehouse.load_fact_order_fulfilment
--
-- Grain: one row per order. Accumulating snapshot - re-running advances the
-- milestone columns of orders that have since shipped.
--
-- Note there is no join to staging.order_details except to count lines: freight
-- belongs to the order, and this is the fact that owns it.
-- ============================================================================
CREATE OR REPLACE FUNCTION warehouse.load_fact_order_fulfilment(
    p_batch_id bigint
)
RETURNS TABLE (rows_inserted bigint, rows_updated bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_before   bigint;
    v_after    bigint;
    v_affected bigint;
BEGIN
    SELECT count(*) INTO v_before FROM warehouse.fact_order_fulfilment;

    INSERT INTO warehouse.fact_order_fulfilment (
        order_id,
        customer_key, employee_key, shipper_key,
        order_date_key, required_date_key, shipped_date_key,
        order_date, required_date, shipped_date,
        freight_amount, order_line_count,
        ship_name, ship_address, ship_city, ship_region,
        ship_postal_code, ship_country,
        dw_load_batch_id
    )
    SELECT
        o.order_id,
        COALESCE(dc.customer_key, -1),
        COALESCE(de.employee_key, -1),
        COALESCE(ds.shipper_key,  -1),
        warehouse.to_date_key(o.order_date::date),
        warehouse.to_date_key(o.required_date::date),
        warehouse.to_date_key(o.shipped_date::date),
        o.order_date::date,
        o.required_date::date,
        o.shipped_date::date,
        -- ISNULL(Freight, 0) -> COALESCE(freight, 0). The fact's freight column
        -- is NOT NULL: an order with unknown freight cost zero to ship as far as
        -- any sum is concerned, and NULL would silently drop it from AVG().
        COALESCE(o.freight, 0),
        COALESCE(lines.line_count, 0),
        o.ship_name, o.ship_address, o.ship_city, o.ship_region,
        o.ship_postal_code, o.ship_country,
        p_batch_id
    FROM staging.orders o
    LEFT JOIN (
        SELECT order_id, count(*)::smallint AS line_count
          FROM staging.order_details
         GROUP BY order_id
    ) lines ON lines.order_id = o.order_id
    LEFT JOIN warehouse.dim_customer dc
      ON dc.customer_id = o.customer_id AND dc.is_current
    LEFT JOIN warehouse.dim_employee de
      ON de.employee_id = o.employee_id AND de.is_current
    LEFT JOIN warehouse.dim_shipper ds
      ON ds.shipper_id = o.ship_via
    ON CONFLICT ON CONSTRAINT uq_fact_order_fulfilment_grain DO UPDATE
       SET customer_key      = EXCLUDED.customer_key,
           employee_key      = EXCLUDED.employee_key,
           shipper_key       = EXCLUDED.shipper_key,
           order_date_key    = EXCLUDED.order_date_key,
           required_date_key = EXCLUDED.required_date_key,
           shipped_date_key  = EXCLUDED.shipped_date_key,
           order_date        = EXCLUDED.order_date,
           required_date     = EXCLUDED.required_date,
           shipped_date      = EXCLUDED.shipped_date,
           freight_amount    = EXCLUDED.freight_amount,
           order_line_count  = EXCLUDED.order_line_count,
           ship_name         = EXCLUDED.ship_name,
           ship_address      = EXCLUDED.ship_address,
           ship_city         = EXCLUDED.ship_city,
           ship_region       = EXCLUDED.ship_region,
           ship_postal_code  = EXCLUDED.ship_postal_code,
           ship_country      = EXCLUDED.ship_country,
           dw_load_batch_id  = EXCLUDED.dw_load_batch_id,
           dw_updated_at     = CURRENT_TIMESTAMP
     -- As above: only touch orders whose milestones or attributes moved. On an
     -- accumulating snapshot this is what makes dw_updated_at mean "when this
     -- order last progressed" rather than "when the loader last ran".
     WHERE (warehouse.fact_order_fulfilment.customer_key,
            warehouse.fact_order_fulfilment.employee_key,
            warehouse.fact_order_fulfilment.shipper_key,
            warehouse.fact_order_fulfilment.order_date,
            warehouse.fact_order_fulfilment.required_date,
            warehouse.fact_order_fulfilment.shipped_date,
            warehouse.fact_order_fulfilment.freight_amount,
            warehouse.fact_order_fulfilment.order_line_count,
            warehouse.fact_order_fulfilment.ship_name,
            warehouse.fact_order_fulfilment.ship_city,
            warehouse.fact_order_fulfilment.ship_country)
           IS DISTINCT FROM
           (EXCLUDED.customer_key, EXCLUDED.employee_key, EXCLUDED.shipper_key,
            EXCLUDED.order_date, EXCLUDED.required_date, EXCLUDED.shipped_date,
            EXCLUDED.freight_amount, EXCLUDED.order_line_count,
            EXCLUDED.ship_name, EXCLUDED.ship_city, EXCLUDED.ship_country);

    GET DIAGNOSTICS v_affected = ROW_COUNT;
    SELECT count(*) INTO v_after FROM warehouse.fact_order_fulfilment;

    RETURN QUERY SELECT v_after - v_before, v_affected - (v_after - v_before);
END;
$$;

COMMENT ON FUNCTION warehouse.load_fact_order_fulfilment(bigint) IS
    'Loads the order-grain accumulating snapshot. Re-running advances milestone '
    'columns for orders that have shipped since the previous run.';
