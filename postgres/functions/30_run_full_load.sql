-- ============================================================================
-- 30_run_full_load.sql
--
-- Load orchestration. Run after 20_load_facts.sql.
--
-- ----------------------------------------------------------------------------
-- TRY / CATCH  ->  BEGIN ... EXCEPTION
-- ----------------------------------------------------------------------------
-- The T-SQL idiom this replaces:
--
--     BEGIN TRY
--         BEGIN TRANSACTION
--         ...
--         COMMIT TRANSACTION
--     END TRY
--     BEGIN CATCH
--         IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION
--         INSERT INTO LoadAudit(...) VALUES (ERROR_MESSAGE(), ...)
--         THROW
--     END CATCH
--
-- Three differences matter when porting it, and all three are load-breaking if
-- missed:
--
-- 1. A PL/pgSQL block with an EXCEPTION clause is ALREADY a subtransaction.
--    PostgreSQL establishes a savepoint on entry and rolls back to it when the
--    handler fires. There is no @@TRANCOUNT to test and no explicit ROLLBACK to
--    issue - attempting one raises an error of its own.
--
-- 2. Because the handler rolls back everything the block did, an audit row
--    written inside the handler would be rolled back too if the exception were
--    simply re-raised. This is the single most common porting bug in this
--    pattern: the audit trail silently vanishes at exactly the moment it is
--    needed. The fix used here is a PROCEDURE with explicit COMMIT, so the
--    failure record is committed independently before the error is re-raised.
--
-- 3. `RAISE` with no arguments re-raises the original error with its stack
--    intact - the equivalent of bare `THROW`. Using `RAISE EXCEPTION '%'` with
--    the message text instead would discard the original SQLSTATE and turn a
--    diagnosable unique-violation into a generic P0001.
--
-- A PROCEDURE is used rather than a FUNCTION because only procedures may issue
-- transaction control statements (CALL, then COMMIT/ROLLBACK inside).
-- ============================================================================

CREATE OR REPLACE PROCEDURE warehouse.run_full_load(
    p_batch_name  varchar(100) DEFAULT 'full_load',
    p_date_from   date         DEFAULT '1994-01-01',
    p_date_to     date         DEFAULT '2002-12-31'
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_batch_id     bigint;
    v_ins          bigint;
    v_upd          bigint;
    v_total_ins    bigint := 0;
    v_total_upd    bigint := 0;
    v_dates        integer;
    v_started      timestamptz := clock_timestamp();
    v_error_text   text;
    v_error_state  text;
    v_error_detail text;
    v_error_ctx    text;
BEGIN
    -- Open the batch and commit immediately, so the batch row survives a later
    -- failure and the run is visible in etl.load_batch while it is in flight.
    INSERT INTO etl.load_batch (batch_name, status)
    VALUES (p_batch_name, 'RUNNING')
    RETURNING load_batch_id INTO v_batch_id;
    COMMIT;

    RAISE NOTICE 'batch % (%) started', v_batch_id, p_batch_name;

    BEGIN
        -- 1. Calendar first: the facts' date foreign keys resolve against it.
        v_dates := warehouse.populate_dim_date(p_date_from, p_date_to);
        v_total_ins := v_total_ins + v_dates;
        RAISE NOTICE '  dim_date              +% rows', v_dates;

        -- 2. Dimensions before facts, so surrogate keys exist to resolve.
        SELECT rows_inserted, rows_updated INTO v_ins, v_upd
          FROM warehouse.load_dim_customer(v_batch_id);
        v_total_ins := v_total_ins + v_ins; v_total_upd := v_total_upd + v_upd;
        RAISE NOTICE '  dim_customer          +% new, % versioned', v_ins, v_upd;

        SELECT rows_inserted, rows_updated INTO v_ins, v_upd
          FROM warehouse.load_dim_product(v_batch_id);
        v_total_ins := v_total_ins + v_ins; v_total_upd := v_total_upd + v_upd;
        RAISE NOTICE '  dim_product           +% new, % versioned', v_ins, v_upd;

        SELECT rows_inserted, rows_updated INTO v_ins, v_upd
          FROM warehouse.load_dim_employee(v_batch_id);
        v_total_ins := v_total_ins + v_ins; v_total_upd := v_total_upd + v_upd;
        RAISE NOTICE '  dim_employee          +% new, % versioned', v_ins, v_upd;

        SELECT rows_inserted, rows_updated INTO v_ins, v_upd
          FROM warehouse.load_dim_shipper(v_batch_id);
        v_total_ins := v_total_ins + v_ins; v_total_upd := v_total_upd + v_upd;
        RAISE NOTICE '  dim_shipper           +% new, % updated', v_ins, v_upd;

        -- 3. Facts.
        SELECT rows_inserted, rows_updated INTO v_ins, v_upd
          FROM warehouse.load_fact_sales_order_line(v_batch_id);
        v_total_ins := v_total_ins + v_ins; v_total_upd := v_total_upd + v_upd;
        RAISE NOTICE '  fact_sales_order_line +% new, % updated', v_ins, v_upd;

        SELECT rows_inserted, rows_updated INTO v_ins, v_upd
          FROM warehouse.load_fact_order_fulfilment(v_batch_id);
        v_total_ins := v_total_ins + v_ins; v_total_upd := v_total_upd + v_upd;
        RAISE NOTICE '  fact_order_fulfilment +% new, % updated', v_ins, v_upd;

    EXCEPTION WHEN OTHERS THEN
        -- Capture diagnostics BEFORE anything else: the handler's own
        -- statements would otherwise overwrite them.
        GET STACKED DIAGNOSTICS
            v_error_text   = MESSAGE_TEXT,
            v_error_state  = RETURNED_SQLSTATE,
            v_error_detail = PG_EXCEPTION_DETAIL,
            v_error_ctx    = PG_EXCEPTION_CONTEXT;

        -- Everything the block did has already been rolled back to the implicit
        -- savepoint. The batch row itself survives - it was committed above -
        -- so it can be marked failed and committed independently.
        UPDATE etl.load_batch
           SET status        = 'FAILED',
               completed_at  = CURRENT_TIMESTAMP,
               error_message = format('[%s] %s%s', v_error_state, v_error_text,
                                      COALESCE(' | ' || v_error_detail, ''))
         WHERE load_batch_id = v_batch_id;
        COMMIT;

        RAISE WARNING 'batch % FAILED [%]: %', v_batch_id, v_error_state, v_error_text;
        RAISE NOTICE 'context: %', v_error_ctx;

        -- Bare RAISE re-raises the original error, SQLSTATE and all.
        RAISE;
    END;

    UPDATE etl.load_batch
       SET status        = 'SUCCEEDED',
           completed_at  = CURRENT_TIMESTAMP,
           rows_inserted = v_total_ins,
           rows_updated  = v_total_upd
     WHERE load_batch_id = v_batch_id;
    COMMIT;

    RAISE NOTICE 'batch % SUCCEEDED: % inserted, % updated in %',
                 v_batch_id, v_total_ins, v_total_upd,
                 justify_interval(clock_timestamp() - v_started);
END;
$$;

COMMENT ON PROCEDURE warehouse.run_full_load(varchar, date, date) IS
    'Orchestrates the full warehouse load: calendar, dimensions, then facts. '
    'Records the outcome in etl.load_batch even when the load fails, then '
    're-raises the original error.';

-- ----------------------------------------------------------------------------
-- Usage
--
--     CALL warehouse.run_full_load('nightly');
--     SELECT * FROM etl.load_batch ORDER BY load_batch_id DESC LIMIT 5;
--
-- CALL cannot run inside an explicit transaction block, because the procedure
-- commits. From psql, invoke it with autocommit on (the default).
-- ----------------------------------------------------------------------------
