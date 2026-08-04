-- ============================================================================
-- 30_facts.sql
--
-- Fact tables. Run after 20_dimensions.sql.
--
-- ----------------------------------------------------------------------------
-- Two facts, two grains, on purpose
-- ----------------------------------------------------------------------------
-- The source Orders table mixes two different grains in one place: the order
-- lines (one row per product per order) and the order itself (freight, ship-to
-- address, shipment dates - one row per order). Modelling both in a single fact
-- is the most common dimensional modelling error there is: freight would repeat
-- on every line and SUM(freight) would be overstated.
--
-- Measured on this data: true freight is 64,942.69, but summed across the line
-- grain it becomes 207,306.10 - an overstatement of 3.19x. Note that this is
-- HIGHER than the 2.60 average lines per order, because larger orders carry
-- more freight and are weighted more heavily by the duplication. Guessing the
-- error as "about the average line count" would itself have been wrong.
--
-- So there are two facts:
--
--   fact_sales_order_line   transaction grain, one row per product per order.
--                           Owns ALL revenue measures.
--
--   fact_order_fulfilment   accumulating snapshot, one row per order.
--                           Owns freight and the delivery-cycle measures.
--                           Carries NO revenue measures - deliberately - so
--                           that no query can double-count by joining both.
--
-- The two are joined on the degenerate dimension order_id when a question needs
-- both, which is the correct way to combine facts of different grain.
-- ============================================================================

SET search_path = warehouse, staging, public;

DROP TABLE IF EXISTS warehouse.fact_sales_order_line CASCADE;
DROP TABLE IF EXISTS warehouse.fact_order_fulfilment CASCADE;

-- ============================================================================
-- fact_sales_order_line
--
-- GRAIN: exactly one row per product per order.
--        Declared, enforced by uq_fact_sales_order_line_grain, and tested in
--        tests/validation.sql. A grain that is only written down in a document
--        is a grain that drifts.
--
-- Measures are fully additive across every dimension, with one exception noted
-- on discount_pct.
-- ============================================================================
CREATE TABLE warehouse.fact_sales_order_line (
    sales_order_line_key  bigint         GENERATED ALWAYS AS IDENTITY,

    -- Degenerate dimensions: order identifiers carry no attributes of their own,
    -- so they live on the fact rather than in a one-column dimension table.
    order_id              integer        NOT NULL,
    product_id            integer        NOT NULL,   -- natural key, retained for grain and audit

    -- Dimension foreign keys. NOT NULL with a -1 default: an unresolved lookup
    -- points at the Unknown member rather than writing NULL, so every join is a
    -- plain inner join and no row is ever silently lost to a NULL key.
    customer_key          integer        NOT NULL DEFAULT -1,
    employee_key          integer        NOT NULL DEFAULT -1,
    product_key           integer        NOT NULL DEFAULT -1,
    shipper_key           integer        NOT NULL DEFAULT -1,

    -- Role-playing date keys, all pointing at dim_date.
    order_date_key        integer        NOT NULL DEFAULT -1,
    required_date_key     integer        NOT NULL DEFAULT -1,
    shipped_date_key      integer        NOT NULL DEFAULT -1,

    -- ------------------------------------------------------------------
    -- Measures
    -- ------------------------------------------------------------------
    quantity              smallint       NOT NULL,
    unit_price            numeric(19,4)  NOT NULL,

    -- Non-additive: a ratio. Never SUM this column - average it weighted by
    -- gross_amount, or derive it as SUM(discount_amount)/SUM(gross_amount).
    discount_pct          numeric(5,4)   NOT NULL DEFAULT 0,

    -- Derived measures are computed by the database, not by the loader and not
    -- by each analyst's own SQL. Stored generated columns mean the arithmetic
    -- is defined once, cannot drift between report and report, and cannot be
    -- left stale by a partial reload.
    gross_amount          numeric(21,4)
        GENERATED ALWAYS AS (quantity * unit_price) STORED,
    discount_amount       numeric(21,4)
        GENERATED ALWAYS AS (quantity * unit_price * discount_pct) STORED,
    net_amount            numeric(21,4)
        GENERATED ALWAYS AS (quantity * unit_price * (1 - discount_pct)) STORED,

    -- Lineage
    dw_load_batch_id      bigint         NULL,
    dw_inserted_at        timestamptz    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_fact_sales_order_line PRIMARY KEY (sales_order_line_key),

    -- THE GRAIN, enforced.
    CONSTRAINT uq_fact_sales_order_line_grain UNIQUE (order_id, product_id),

    CONSTRAINT fk_fsol_customer  FOREIGN KEY (customer_key)      REFERENCES warehouse.dim_customer (customer_key),
    CONSTRAINT fk_fsol_employee  FOREIGN KEY (employee_key)      REFERENCES warehouse.dim_employee (employee_key),
    CONSTRAINT fk_fsol_product   FOREIGN KEY (product_key)       REFERENCES warehouse.dim_product  (product_key),
    CONSTRAINT fk_fsol_shipper   FOREIGN KEY (shipper_key)       REFERENCES warehouse.dim_shipper  (shipper_key),
    CONSTRAINT fk_fsol_order_dt  FOREIGN KEY (order_date_key)    REFERENCES warehouse.dim_date     (date_key),
    CONSTRAINT fk_fsol_reqd_dt   FOREIGN KEY (required_date_key) REFERENCES warehouse.dim_date     (date_key),
    CONSTRAINT fk_fsol_ship_dt   FOREIGN KEY (shipped_date_key)  REFERENCES warehouse.dim_date     (date_key),
    CONSTRAINT fk_fsol_batch     FOREIGN KEY (dw_load_batch_id)  REFERENCES etl.load_batch         (load_batch_id),

    -- Ported verbatim from the source CHECK constraints on [Order Details].
    CONSTRAINT ck_fsol_quantity   CHECK (quantity > 0),
    CONSTRAINT ck_fsol_unit_price CHECK (unit_price >= 0),
    CONSTRAINT ck_fsol_discount   CHECK (discount_pct >= 0 AND discount_pct <= 1)
);

COMMENT ON TABLE warehouse.fact_sales_order_line IS
    'GRAIN: one row per product per order. Transaction fact. Owns all revenue '
    'measures. Join to fact_order_fulfilment on order_id for freight.';

COMMENT ON COLUMN warehouse.fact_sales_order_line.discount_pct IS
    'NON-ADDITIVE ratio. Do not SUM. Use SUM(discount_amount)/SUM(gross_amount).';

COMMENT ON COLUMN warehouse.fact_sales_order_line.order_id IS
    'Degenerate dimension. Also the join key to fact_order_fulfilment.';

-- ----------------------------------------------------------------------------
-- Fact indexes
--
-- One index per dimension foreign key. PostgreSQL does not create these
-- automatically for foreign keys, and without them every dimension-filtered
-- query degrades to a sequential scan of the fact table as it grows.
--
-- Note the contrast with the reference implementation, which carries eight
-- pairs of duplicate indexes (see docs/migration-guide.md). Each index below
-- serves a distinct access path.
-- ----------------------------------------------------------------------------
CREATE INDEX ix_fsol_customer   ON warehouse.fact_sales_order_line (customer_key);
CREATE INDEX ix_fsol_employee   ON warehouse.fact_sales_order_line (employee_key);
CREATE INDEX ix_fsol_product    ON warehouse.fact_sales_order_line (product_key);
CREATE INDEX ix_fsol_shipper    ON warehouse.fact_sales_order_line (shipper_key);
CREATE INDEX ix_fsol_order_date ON warehouse.fact_sales_order_line (order_date_key);

-- Composite supporting the dominant query shape: a date range, then a rollup by
-- product. Column order matters - date first, because it is the selective
-- predicate; product second, so the grouping is fed pre-sorted.
CREATE INDEX ix_fsol_date_product
    ON warehouse.fact_sales_order_line (order_date_key, product_key)
    INCLUDE (net_amount, quantity);

-- ============================================================================
-- fact_order_fulfilment
--
-- GRAIN: exactly one row per order.
-- TYPE:  accumulating snapshot. Rows are updated in place as an order moves
--        through its milestones (ordered -> required-by -> shipped), unlike the
--        insert-only transaction fact above.
--
-- Carries no revenue measures by design (see header).
-- ============================================================================
CREATE TABLE warehouse.fact_order_fulfilment (
    order_fulfilment_key  bigint         GENERATED ALWAYS AS IDENTITY,

    order_id              integer        NOT NULL,   -- degenerate dimension and grain

    customer_key          integer        NOT NULL DEFAULT -1,
    employee_key          integer        NOT NULL DEFAULT -1,
    shipper_key           integer        NOT NULL DEFAULT -1,

    order_date_key        integer        NOT NULL DEFAULT -1,
    required_date_key     integer        NOT NULL DEFAULT -1,
    shipped_date_key      integer        NOT NULL DEFAULT -1,

    -- Milestone dates held natively as well as by key, so that the lag measures
    -- below can be generated columns. Recomputing a lag by joining dim_date
    -- three times in every query would be slower and easy to get wrong.
    order_date            date           NULL,
    required_date         date           NULL,
    shipped_date          date           NULL,

    -- ------------------------------------------------------------------
    -- Measures
    -- ------------------------------------------------------------------
    freight_amount        numeric(19,4)  NOT NULL DEFAULT 0,
    order_line_count      smallint       NOT NULL DEFAULT 0,

    -- Accumulating-snapshot lag measures. NULL until the milestone is reached,
    -- which is correct: an unshipped order has no shipping duration, and NULL
    -- keeps it out of AVG() rather than dragging the average toward zero.
    days_to_ship          integer
        GENERATED ALWAYS AS (shipped_date - order_date) STORED,
    days_late             integer
        GENERATED ALWAYS AS (shipped_date - required_date) STORED,
    is_shipped            boolean
        GENERATED ALWAYS AS (shipped_date IS NOT NULL) STORED,
    is_late               boolean
        GENERATED ALWAYS AS (shipped_date IS NOT NULL AND shipped_date > required_date) STORED,

    -- Ship-to details: attributes of the shipment event, not of the customer.
    -- An order may ship to an address the customer no longer uses, so these
    -- stay on the fact rather than being resolved through dim_customer.
    ship_name             varchar(40)    NULL,
    ship_address          varchar(60)    NULL,
    ship_city             varchar(15)    NULL,
    ship_region           varchar(15)    NULL,
    ship_postal_code      varchar(10)    NULL,
    ship_country          varchar(15)    NULL,

    -- Lineage
    dw_load_batch_id      bigint         NULL,
    dw_inserted_at        timestamptz    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    dw_updated_at         timestamptz    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_fact_order_fulfilment PRIMARY KEY (order_fulfilment_key),

    -- THE GRAIN, enforced.
    CONSTRAINT uq_fact_order_fulfilment_grain UNIQUE (order_id),

    CONSTRAINT fk_fof_customer  FOREIGN KEY (customer_key)      REFERENCES warehouse.dim_customer (customer_key),
    CONSTRAINT fk_fof_employee  FOREIGN KEY (employee_key)      REFERENCES warehouse.dim_employee (employee_key),
    CONSTRAINT fk_fof_shipper   FOREIGN KEY (shipper_key)       REFERENCES warehouse.dim_shipper  (shipper_key),
    CONSTRAINT fk_fof_order_dt  FOREIGN KEY (order_date_key)    REFERENCES warehouse.dim_date     (date_key),
    CONSTRAINT fk_fof_reqd_dt   FOREIGN KEY (required_date_key) REFERENCES warehouse.dim_date     (date_key),
    CONSTRAINT fk_fof_ship_dt   FOREIGN KEY (shipped_date_key)  REFERENCES warehouse.dim_date     (date_key),
    CONSTRAINT fk_fof_batch     FOREIGN KEY (dw_load_batch_id)  REFERENCES etl.load_batch         (load_batch_id),

    CONSTRAINT ck_fof_freight     CHECK (freight_amount >= 0),
    CONSTRAINT ck_fof_line_count  CHECK (order_line_count >= 0),

    -- Milestones cannot run backwards. The source data contains no violations;
    -- this stops a future load from introducing one.
    CONSTRAINT ck_fof_ship_after_order
        CHECK (shipped_date IS NULL OR order_date IS NULL OR shipped_date >= order_date)
);

COMMENT ON TABLE warehouse.fact_order_fulfilment IS
    'GRAIN: one row per order. Accumulating snapshot - updated in place as '
    'milestones complete. Owns freight and delivery-cycle measures only; all '
    'revenue lives in fact_sales_order_line.';

COMMENT ON COLUMN warehouse.fact_order_fulfilment.order_line_count IS
    'Count of lines on the order. A convenience measure - it must reconcile to '
    'COUNT(*) on fact_sales_order_line, which tests/quality-checks.sql asserts.';

CREATE INDEX ix_fof_customer   ON warehouse.fact_order_fulfilment (customer_key);
CREATE INDEX ix_fof_employee   ON warehouse.fact_order_fulfilment (employee_key);
CREATE INDEX ix_fof_shipper    ON warehouse.fact_order_fulfilment (shipper_key);
CREATE INDEX ix_fof_order_date ON warehouse.fact_order_fulfilment (order_date_key);

-- Partial index for the on-time-delivery reports, which only ever look at
-- shipped orders. Indexing the unshipped rows would be wasted space.
CREATE INDEX ix_fof_late_orders
    ON warehouse.fact_order_fulfilment (order_date_key, shipper_key)
    WHERE is_late;
