-- ============================================================================
-- 00_schemas.sql
--
-- Foundation objects: extensions, schemas and the ETL control layer.
-- Run first. Idempotent - safe to re-run.
--
-- Target: PostgreSQL 14+
-- Source: sqlserver/database/northwind/northwind.sql (reference implementation)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Extensions
--
-- btree_gist lets an EXCLUDE constraint mix an equality operator (natural key)
-- with an overlap operator (validity period). This is what makes it physically
-- impossible to write two overlapping SCD Type 2 versions of the same business
-- entity - a guarantee SQL Server cannot express declaratively and which is
-- otherwise left to procedural code or a nightly audit query.
-- ----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ----------------------------------------------------------------------------
-- Schemas
--
-- The SQL Server reference puts every object in `dbo`. The port separates the
-- warehouse into layers so that each has one job and dependencies flow in one
-- direction only:
--
--     staging  ->  warehouse  ->  presentation
--
-- `reference` holds the straight ports of the smaller training databases; it
-- feeds nothing downstream and exists to prove dialect coverage.
-- ----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS warehouse;
CREATE SCHEMA IF NOT EXISTS presentation;
CREATE SCHEMA IF NOT EXISTS reference;
CREATE SCHEMA IF NOT EXISTS etl;

COMMENT ON SCHEMA staging      IS
    'Landing zone. Structurally 1:1 with the Northwind OLTP source. Permissive '
    'by design: minimal constraints so that dirty source data lands rather than '
    'failing the extract, and is rejected later by the tests in /tests.';

COMMENT ON SCHEMA warehouse    IS
    'Kimball dimensional layer. Conformed dimensions and fact tables. '
    'Surrogate-keyed, constrained, indexed. The only schema loaded by ETL.';

COMMENT ON SCHEMA presentation IS
    'Consumer-facing views. No storage. Business naming, no surrogate keys '
    'exposed. This is what BI tools and analysts connect to.';

COMMENT ON SCHEMA reference    IS
    'Ports of the QAStore, QATSQLPLUS and REVENUE training schemas. Reference '
    'only - demonstrates composite foreign keys, CHECK constraints and identity '
    'columns surviving the migration. Not part of the warehouse.';

COMMENT ON SCHEMA etl          IS
    'ETL control and audit. Batch registry and run outcomes.';

-- ============================================================================
-- ETL control layer
-- ============================================================================

-- ----------------------------------------------------------------------------
-- etl.load_batch
--
-- One row per warehouse load run. Every fact and dimension row carries the
-- batch id that wrote it, which makes a bad load traceable and reversible
-- without restoring a backup.
--
-- IDENTITY(1,1)  ->  GENERATED ALWAYS AS IDENTITY
-- GETDATE()      ->  CURRENT_TIMESTAMP
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS etl.load_batch (
    load_batch_id     bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_name        varchar(100)  NOT NULL,
    source_system     varchar(50)   NOT NULL DEFAULT 'northwind_mssql',
    started_at        timestamptz   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at      timestamptz   NULL,
    status            varchar(20)   NOT NULL DEFAULT 'RUNNING',
    rows_inserted     bigint        NOT NULL DEFAULT 0,
    rows_updated      bigint        NOT NULL DEFAULT 0,
    rows_rejected     bigint        NOT NULL DEFAULT 0,
    error_message     text          NULL,

    CONSTRAINT ck_load_batch_status
        CHECK (status IN ('RUNNING', 'SUCCEEDED', 'FAILED')),

    -- A batch cannot finish before it started.
    CONSTRAINT ck_load_batch_timeline
        CHECK (completed_at IS NULL OR completed_at >= started_at),

    -- A finished batch must record when it finished.
    CONSTRAINT ck_load_batch_completion
        CHECK ((status = 'RUNNING') = (completed_at IS NULL))
);

COMMENT ON TABLE etl.load_batch IS
    'One row per warehouse load run. Referenced by dw_load_batch_id on every '
    'warehouse table for lineage and rollback.';

CREATE INDEX IF NOT EXISTS ix_load_batch_started
    ON etl.load_batch (started_at DESC);

-- Only one batch may be in flight at a time. Concurrent loads against the same
-- SCD2 dimensions would interleave versions and corrupt the validity chain.
CREATE UNIQUE INDEX IF NOT EXISTS uix_load_batch_single_running
    ON etl.load_batch ((status))
    WHERE status = 'RUNNING';
