-- ============================================================================
-- 10_load_dimensions.sql
--
-- Dimension loaders. Run after 00_helpers.sql.
--
-- ----------------------------------------------------------------------------
-- The SCD Type 2 pattern used by every Type 2 loader here
-- ----------------------------------------------------------------------------
-- 1. Fingerprint each source row (warehouse.scd_hash).
-- 2. CLOSE the current warehouse version of every entity whose fingerprint has
--    changed, by stamping valid_to = p_effective_from.
-- 3. INSERT a new current version for every source entity that now has no
--    current row - which is exactly the union of "brand new" and "just closed
--    in step 2".
--
-- Step 3 needs no knowledge of which rows step 2 touched. That is what keeps
-- the loader short, and it is why new and changed entities cannot diverge.
--
-- Order matters: closing before inserting is what keeps the two versions'
-- validity ranges adjacent rather than overlapping, so the EXCLUDE constraint
-- on each dimension is satisfied. Reverse the two statements and the load
-- fails loudly with SQLSTATE 23P01 - which is the intended behaviour.
--
-- p_effective_from defaults to CURRENT_TIMESTAMP, which in PostgreSQL is the
-- START of the transaction, not the clock at statement time. Every row written
-- by one batch therefore shares an instant, and the version chain is exactly
-- contiguous with no gaps. clock_timestamp() would introduce microsecond gaps
-- between the close and the insert.
-- ============================================================================

-- ============================================================================
-- warehouse.load_dim_customer  -  SCD Type 2
-- ============================================================================
CREATE OR REPLACE FUNCTION warehouse.load_dim_customer(
    p_batch_id        bigint,
    p_effective_from  timestamptz DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (rows_inserted bigint, rows_updated bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_closed   bigint := 0;
    v_inserted bigint := 0;
BEGIN
    WITH source AS (
        SELECT s.customer_id,
               warehouse.scd_hash(
                   s.company_name, s.contact_name, s.contact_title, s.address,
                   s.city, s.region, s.postal_code, s.country, s.phone, s.fax
               ) AS row_hash
        FROM staging.customers s
    ),
    closed AS (
        UPDATE warehouse.dim_customer d
           SET valid_to      = p_effective_from,
               dw_updated_at = CURRENT_TIMESTAMP
          FROM source s
         WHERE d.customer_id = s.customer_id
           AND d.is_current
           AND d.row_hash IS DISTINCT FROM s.row_hash
        RETURNING 1
    )
    SELECT count(*) INTO v_closed FROM closed;

    WITH inserted AS (
        INSERT INTO warehouse.dim_customer (
            customer_id, company_name, contact_name, contact_title, address,
            city, region, postal_code, country, phone, fax,
            valid_from, row_hash, dw_load_batch_id
        )
        SELECT s.customer_id, s.company_name, s.contact_name, s.contact_title,
               s.address, s.city, s.region, s.postal_code, s.country, s.phone,
               s.fax,
               p_effective_from,
               warehouse.scd_hash(
                   s.company_name, s.contact_name, s.contact_title, s.address,
                   s.city, s.region, s.postal_code, s.country, s.phone, s.fax
               ),
               p_batch_id
          FROM staging.customers s
         WHERE NOT EXISTS (
                   SELECT 1 FROM warehouse.dim_customer d
                    WHERE d.customer_id = s.customer_id
                      AND d.is_current
               )
        RETURNING 1
    )
    SELECT count(*) INTO v_inserted FROM inserted;

    RETURN QUERY SELECT v_inserted, v_closed;
END;
$$;

COMMENT ON FUNCTION warehouse.load_dim_customer(bigint, timestamptz) IS
    'SCD Type 2 load of dim_customer from staging.customers. Returns '
    '(rows_inserted, rows_updated) where rows_updated counts closed versions.';

-- ============================================================================
-- warehouse.load_dim_product  -  SCD Type 2 + Type 1
--
-- The only loader with both. Stock levels are Type 1 and are refreshed on the
-- current row in place, whether or not a Type 2 change occurred. Doing this
-- BEFORE the Type 2 steps would waste the update on a row about to be closed.
-- ============================================================================
CREATE OR REPLACE FUNCTION warehouse.load_dim_product(
    p_batch_id        bigint,
    p_effective_from  timestamptz DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (rows_inserted bigint, rows_updated bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_closed   bigint := 0;
    v_inserted bigint := 0;
BEGIN
    -- Denormalised source: product with its category and supplier collapsed in.
    -- LEFT JOIN, not INNER: a product with a missing category must still load,
    -- carrying the Unknown label rather than vanishing from the warehouse.
    CREATE TEMP TABLE tmp_product_source ON COMMIT DROP AS
    SELECT p.product_id,
           p.product_name,
           p.quantity_per_unit,
           p.unit_price,
           p.discontinued,
           p.units_in_stock,
           p.units_on_order,
           p.reorder_level,
           p.category_id,
           COALESCE(c.category_name, 'Unknown')  AS category_name,
           c.description                         AS category_description,
           p.supplier_id,
           COALESCE(su.company_name, 'Unknown')  AS supplier_name,
           su.contact_name                       AS supplier_contact_name,
           su.city                               AS supplier_city,
           su.country                            AS supplier_country,
           warehouse.scd_hash(
               p.product_name, p.quantity_per_unit, p.unit_price::text,
               p.discontinued::text, p.category_id::text,
               COALESCE(c.category_name, 'Unknown'), c.description,
               p.supplier_id::text, COALESCE(su.company_name, 'Unknown'),
               su.contact_name, su.city, su.country
           ) AS row_hash
      FROM staging.products  p
      LEFT JOIN staging.categories c  ON c.category_id = p.category_id
      LEFT JOIN staging.suppliers  su ON su.supplier_id = p.supplier_id;

    WITH closed AS (
        UPDATE warehouse.dim_product d
           SET valid_to      = p_effective_from,
               dw_updated_at = CURRENT_TIMESTAMP
          FROM tmp_product_source s
         WHERE d.product_id = s.product_id
           AND d.is_current
           AND d.row_hash IS DISTINCT FROM s.row_hash
        RETURNING 1
    )
    SELECT count(*) INTO v_closed FROM closed;

    WITH inserted AS (
        INSERT INTO warehouse.dim_product (
            product_id, product_name, quantity_per_unit, unit_price, discontinued,
            category_id, category_name, category_description,
            supplier_id, supplier_name, supplier_contact_name,
            supplier_city, supplier_country,
            units_in_stock, units_on_order, reorder_level,
            valid_from, row_hash, dw_load_batch_id
        )
        SELECT s.product_id, s.product_name, s.quantity_per_unit, s.unit_price,
               s.discontinued, s.category_id, s.category_name, s.category_description,
               s.supplier_id, s.supplier_name, s.supplier_contact_name,
               s.supplier_city, s.supplier_country,
               s.units_in_stock, s.units_on_order, s.reorder_level,
               p_effective_from, s.row_hash, p_batch_id
          FROM tmp_product_source s
         WHERE NOT EXISTS (
                   SELECT 1 FROM warehouse.dim_product d
                    WHERE d.product_id = s.product_id
                      AND d.is_current
               )
        RETURNING 1
    )
    SELECT count(*) INTO v_inserted FROM inserted;

    -- Type 1 refresh of the volatile stock attributes on whatever row is now
    -- current. No new version, no history.
    UPDATE warehouse.dim_product d
       SET units_in_stock = s.units_in_stock,
           units_on_order = s.units_on_order,
           reorder_level  = s.reorder_level,
           dw_updated_at  = CURRENT_TIMESTAMP
      FROM tmp_product_source s
     WHERE d.product_id = s.product_id
       AND d.is_current
       AND (d.units_in_stock, d.units_on_order, d.reorder_level)
           IS DISTINCT FROM (s.units_in_stock, s.units_on_order, s.reorder_level);

    DROP TABLE IF EXISTS tmp_product_source;

    RETURN QUERY SELECT v_inserted, v_closed;
END;
$$;

COMMENT ON FUNCTION warehouse.load_dim_product(bigint, timestamptz) IS
    'SCD Type 2 load of dim_product (descriptive and pricing attributes) with a '
    'Type 1 in-place refresh of stock levels.';

-- ============================================================================
-- warehouse.load_dim_employee  -  SCD Type 2
--
-- Self-join to resolve the manager name from the same staging table. The join
-- is LEFT so that the head of the company, whose reports_to is NULL, still
-- loads.
-- ============================================================================
CREATE OR REPLACE FUNCTION warehouse.load_dim_employee(
    p_batch_id        bigint,
    p_effective_from  timestamptz DEFAULT CURRENT_TIMESTAMP
)
RETURNS TABLE (rows_inserted bigint, rows_updated bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_closed   bigint := 0;
    v_inserted bigint := 0;
BEGIN
    CREATE TEMP TABLE tmp_employee_source ON COMMIT DROP AS
    SELECT e.employee_id,
           e.first_name,
           e.last_name,
           -- T-SQL `FirstName + ' ' + LastName` -> `||`. Note the semantic
           -- difference: in T-SQL, concatenating a NULL yields NULL unless
           -- CONCAT_NULL_YIELDS_NULL is OFF; `||` behaves the same way, so
           -- both names being NOT NULL is what makes this safe.
           e.first_name || ' ' || e.last_name       AS full_name,
           e.title,
           e.title_of_courtesy,
           e.birth_date::date                       AS birth_date,
           e.hire_date::date                        AS hire_date,
           e.address, e.city, e.region, e.postal_code, e.country,
           e.home_phone, e.extension, e.photo_path,
           e.reports_to                             AS manager_employee_id,
           m.first_name || ' ' || m.last_name       AS manager_name,
           EXISTS (SELECT 1 FROM staging.employees r
                    WHERE r.reports_to = e.employee_id) AS is_manager,
           warehouse.scd_hash(
               e.first_name, e.last_name, e.title, e.title_of_courtesy,
               e.birth_date::text, e.hire_date::text, e.address, e.city,
               e.region, e.postal_code, e.country, e.home_phone, e.extension,
               e.photo_path, e.reports_to::text,
               m.first_name || ' ' || m.last_name
           ) AS row_hash
      FROM staging.employees e
      LEFT JOIN staging.employees m ON m.employee_id = e.reports_to;

    WITH closed AS (
        UPDATE warehouse.dim_employee d
           SET valid_to      = p_effective_from,
               dw_updated_at = CURRENT_TIMESTAMP
          FROM tmp_employee_source s
         WHERE d.employee_id = s.employee_id
           AND d.is_current
           AND d.row_hash IS DISTINCT FROM s.row_hash
        RETURNING 1
    )
    SELECT count(*) INTO v_closed FROM closed;

    WITH inserted AS (
        INSERT INTO warehouse.dim_employee (
            employee_id, first_name, last_name, full_name, title,
            title_of_courtesy, birth_date, hire_date, address, city, region,
            postal_code, country, home_phone, extension, photo_path,
            manager_employee_id, manager_name, is_manager,
            valid_from, row_hash, dw_load_batch_id
        )
        SELECT s.employee_id, s.first_name, s.last_name, s.full_name, s.title,
               s.title_of_courtesy, s.birth_date, s.hire_date, s.address,
               s.city, s.region, s.postal_code, s.country, s.home_phone,
               s.extension, s.photo_path, s.manager_employee_id, s.manager_name,
               s.is_manager, p_effective_from, s.row_hash, p_batch_id
          FROM tmp_employee_source s
         WHERE NOT EXISTS (
                   SELECT 1 FROM warehouse.dim_employee d
                    WHERE d.employee_id = s.employee_id
                      AND d.is_current
               )
        RETURNING 1
    )
    SELECT count(*) INTO v_inserted FROM inserted;

    DROP TABLE IF EXISTS tmp_employee_source;

    RETURN QUERY SELECT v_inserted, v_closed;
END;
$$;

COMMENT ON FUNCTION warehouse.load_dim_employee(bigint, timestamptz) IS
    'SCD Type 2 load of dim_employee with the reporting hierarchy flattened.';

-- ============================================================================
-- warehouse.load_dim_shipper  -  SCD Type 1
--
-- A plain upsert. ON CONFLICT DO UPDATE is the PostgreSQL equivalent of T-SQL's
-- MERGE, and is preferred to it: SQL Server's MERGE has a long history of
-- concurrency bugs, and ON CONFLICT resolves against a named unique constraint
-- atomically.
--
-- WHERE ... IS DISTINCT FROM on the update avoids rewriting rows that have not
-- changed, which keeps dw_updated_at meaningful instead of resetting it to
-- "the last time the loader ran".
-- ============================================================================
CREATE OR REPLACE FUNCTION warehouse.load_dim_shipper(
    p_batch_id bigint
)
RETURNS TABLE (rows_inserted bigint, rows_updated bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_before   bigint;
    v_affected bigint;
BEGIN
    SELECT count(*) INTO v_before FROM warehouse.dim_shipper;

    INSERT INTO warehouse.dim_shipper (shipper_id, company_name, phone, dw_load_batch_id)
    SELECT s.shipper_id, s.company_name, s.phone, p_batch_id
      FROM staging.shippers s
    ON CONFLICT ON CONSTRAINT uq_dim_shipper_natural DO UPDATE
       SET company_name     = EXCLUDED.company_name,
           phone            = EXCLUDED.phone,
           dw_load_batch_id = EXCLUDED.dw_load_batch_id,
           dw_updated_at    = CURRENT_TIMESTAMP
     WHERE (warehouse.dim_shipper.company_name, warehouse.dim_shipper.phone)
           IS DISTINCT FROM (EXCLUDED.company_name, EXCLUDED.phone);

    GET DIAGNOSTICS v_affected = ROW_COUNT;

    RETURN QUERY
    SELECT (SELECT count(*) FROM warehouse.dim_shipper) - v_before,
           v_affected - ((SELECT count(*) FROM warehouse.dim_shipper) - v_before);
END;
$$;

COMMENT ON FUNCTION warehouse.load_dim_shipper(bigint) IS
    'SCD Type 1 upsert of dim_shipper. Unchanged rows are not rewritten.';
