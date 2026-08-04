-- ============================================================================
-- 40_reference_objects.sql
--
-- Ports of the programmable objects in the QATSQLPLUS training database:
-- two user-defined functions, one stored procedure and two views.
--
-- Source: sqlserver/database/qatsqlplus/qatsqlplus_setup.sql
--
-- These are the only author-adjacent procedures and functions in the reference
-- implementation, and they are ported because between them they exercise the
-- three T-SQL constructs with no direct PostgreSQL equivalent: inline
-- table-valued functions, multi-statement table-valued functions, and the
-- variable-accumulator string-aggregation idiom.
-- ============================================================================

SET search_path = reference, public;

-- ============================================================================
-- reference.udf_delegate_days(delegate_id)
--
-- T-SQL inline table-valued function:
--
--     CREATE FUNCTION dbo.udf_DelegateDays(@DelegateID INT)
--         RETURNS TABLE AS RETURN (SELECT count(*) AS NumberCourses,
--                                         sum(CR.DurationDays) AS NumberDays ...)
--
-- Ports to a SQL-language function RETURNS TABLE. Both are inlined by the
-- planner rather than executed row by row, so the performance characteristic
-- is preserved as well as the result.
--
-- Note COALESCE around the SUM: over zero matching rows SQL Server's SUM and
-- PostgreSQL's both return NULL, and a delegate who attended nothing should
-- report 0 days, not NULL. The original returns NULL here - a latent bug that
-- the port fixes deliberately rather than by accident. Flagged, not silent.
-- ============================================================================
CREATE OR REPLACE FUNCTION reference.udf_delegate_days(p_delegate_id integer)
RETURNS TABLE (number_courses bigint, number_days bigint)
LANGUAGE sql
STABLE
AS $$
    SELECT count(*)                              AS number_courses,
           COALESCE(sum(cr.duration_days), 0)    AS number_days
      FROM reference.course_run cr
      JOIN reference.delegate_attendance da
        ON cr.course_run_id = da.course_run_id
     WHERE da.delegate_id = p_delegate_id;
$$;

COMMENT ON FUNCTION reference.udf_delegate_days(integer) IS
    'Port of dbo.udf_DelegateDays. Returns course and day counts for a '
    'delegate. COALESCE added: the source returns NULL for a delegate with no '
    'attendance where 0 is meant.';

-- ============================================================================
-- reference.udf_delegate_course_string(delegate_id)
--
-- The interesting one. T-SQL multi-statement table-valued function building a
-- delimited list by assigning to a variable inside a SELECT:
--
--     SELECT @CourseString = ISNULL(@CourseString + ', ' + C.CourseName,
--                                   C.CourseName)
--         FROM ...
--
-- That idiom relies on SQL Server evaluating the assignment once per row in an
-- undefined order. Microsoft has never guaranteed it, and it silently produces
-- wrong results when the plan changes - it is a known-fragile pattern.
--
-- PostgreSQL has a first-class aggregate for this: string_agg, with an ORDER BY
-- inside the aggregate call so the output order is defined rather than
-- accidental. One line, deterministic, and parallelisable.
--
-- ISNULL() -> COALESCE(), and the `+` concatenation -> `||`, both visible in
-- the original expression above.
-- ============================================================================
CREATE OR REPLACE FUNCTION reference.udf_delegate_course_string(p_delegate_id integer)
RETURNS text
LANGUAGE sql
STABLE
AS $$
    SELECT string_agg(c.course_name, ', ' ORDER BY c.course_name)
      FROM reference.course_run cr
      JOIN reference.delegate_attendance da ON cr.course_run_id = da.course_run_id
      JOIN reference.course c               ON c.course_id      = cr.course_id
     WHERE da.delegate_id = p_delegate_id;
$$;

COMMENT ON FUNCTION reference.udf_delegate_course_string(integer) IS
    'Port of dbo.udf_DelegateCourseString. The source''s variable-accumulator '
    'idiom is replaced by string_agg with a deterministic ORDER BY.';

-- ============================================================================
-- reference.reset_book_stock()
--
-- Port of:
--     CREATE PROC dbo.ResetBookStock AS
--     BEGIN
--         DELETE FROM dbo.BookStock
--         INSERT INTO dbo.BookStock SELECT ProductID, SUM(TransferAmount)
--             FROM dbo.BookTransfers GROUP BY ProductID
--         DELETE FROM dbo.BookTransfers WHERE TransferDate >= '2015/01/01'
--     END
--
-- Ported as a PROCEDURE, matching CREATE PROC.
--
-- Two faithful-porting notes:
--
-- 1. The date literal '2015/01/01' is in a format that depends on the server's
--    DATEFORMAT setting in T-SQL. It is written as an unambiguous ISO date
--    here. This is a correctness fix: the same literal can mean different days
--    on differently configured SQL Server instances.
--
-- 2. The source's DELETE-then-INSERT is preserved rather than being rewritten
--    as an upsert. The procedure's contract is "rebuild stock from transfers",
--    and a truncate-and-rebuild expresses that honestly. Wrapping the whole
--    thing in a single transaction - which PL/pgSQL does implicitly - removes
--    the window in which SQL Server would leave BookStock empty if the INSERT
--    failed after the DELETE committed.
-- ============================================================================
CREATE OR REPLACE PROCEDURE reference.reset_book_stock()
LANGUAGE plpgsql
AS $$
DECLARE
    v_products integer;
    v_purged   integer;
BEGIN
    DELETE FROM reference.book_stock;

    INSERT INTO reference.book_stock (product_id, stock_amount)
    SELECT product_id, sum(transfer_amount)
      FROM reference.book_transfers
     GROUP BY product_id;

    GET DIAGNOSTICS v_products = ROW_COUNT;

    DELETE FROM reference.book_transfers
     WHERE transfer_date >= DATE '2015-01-01';

    GET DIAGNOSTICS v_purged = ROW_COUNT;

    RAISE NOTICE 'reset_book_stock: % product totals rebuilt, % transfers purged',
                 v_products, v_purged;
END;
$$;

COMMENT ON PROCEDURE reference.reset_book_stock() IS
    'Port of dbo.ResetBookStock. Rebuilds book_stock from book_transfers and '
    'purges transfers dated 2015-01-01 or later.';

-- ============================================================================
-- Views: reference.vendor_course_delegate_count
--        reference.vendor_course_date_delegate_count
--
-- Direct ports. Both are straightforward three-way joins with a COUNT, and
-- port without dialect changes beyond identifier casing.
-- ============================================================================
CREATE OR REPLACE VIEW reference.vendor_course_delegate_count AS
SELECT v.vendor_name,
       c.course_name,
       count(*) AS number_delegates
  FROM reference.vendor              v
  JOIN reference.course              c  ON c.vendor_id     = v.vendor_id
  JOIN reference.course_run          cr ON cr.course_id    = c.course_id
  JOIN reference.delegate_attendance da ON cr.course_run_id = da.course_run_id
 GROUP BY v.vendor_name, c.course_name;

CREATE OR REPLACE VIEW reference.vendor_course_date_delegate_count AS
SELECT v.vendor_name,
       c.course_name,
       cr.start_date,
       count(*) AS number_delegates
  FROM reference.vendor              v
  JOIN reference.course              c  ON c.vendor_id     = v.vendor_id
  JOIN reference.course_run          cr ON cr.course_id    = c.course_id
  JOIN reference.delegate_attendance da ON cr.course_run_id = da.course_run_id
 GROUP BY v.vendor_name, c.course_name, cr.start_date;

COMMENT ON VIEW reference.vendor_course_delegate_count IS
    'Port of dbo.VendorCourseDelegateCount.';
COMMENT ON VIEW reference.vendor_course_date_delegate_count IS
    'Port of dbo.VendorCourseDateDelegateCount.';
