-- ============================================================================
-- 00_helpers.sql
--
-- Shared ETL helper functions. Run before the loaders.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- warehouse.scd_hash(VARIADIC text[]) -> text
--
-- Fingerprints the tracked attributes of a dimension row so that change
-- detection is one comparison rather than a fifteen-way OR of IS DISTINCT FROM
-- predicates that will drift out of step with the column list.
--
-- The NULL sentinel matters. array_to_string() drops NULLs by default, so
-- ('Smith', NULL, 'London') and ('Smith', 'London', NULL) would fingerprint
-- identically and a genuine change would be silently missed. Passing '~NULL~'
-- as the null_string keeps every position occupied.
--
-- IMMUTABLE so the planner may fold it and so it can be used in an index.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION warehouse.scd_hash(VARIADIC p_attributes text[])
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT md5(array_to_string(COALESCE(p_attributes, '{}'), '|', '~NULL~'));
$$;

COMMENT ON FUNCTION warehouse.scd_hash(text[]) IS
    'md5 fingerprint of an SCD attribute set. NULLs are positionally preserved.';

-- ----------------------------------------------------------------------------
-- warehouse.to_date_key(date) -> integer
--
-- Converts a calendar date to the yyyymmdd smart key used by dim_date, mapping
-- NULL to the Unknown member (-1) rather than propagating NULL into a fact
-- foreign key.
--
-- Deliberately typed `date`, not `timestamptz`: extracting date parts from a
-- timestamptz depends on the session TimeZone setting, which makes the result
-- STABLE rather than IMMUTABLE and would silently shift facts across midnight
-- for a session in a different time zone.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION warehouse.to_date_key(p_date date)
RETURNS integer
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
    SELECT CASE
             WHEN p_date IS NULL THEN -1
             ELSE (EXTRACT(YEAR FROM p_date) * 10000
                 + EXTRACT(MONTH FROM p_date) * 100
                 + EXTRACT(DAY FROM p_date))::integer
           END;
$$;

COMMENT ON FUNCTION warehouse.to_date_key(date) IS
    'Calendar date -> yyyymmdd dim_date key. NULL maps to the Unknown member -1.';

-- ============================================================================
-- warehouse.populate_dim_date(from, to) -> integer
--
-- Generates the calendar. Idempotent: existing rows are left alone, so
-- extending the range forward is a re-run with a later end date.
--
-- generate_series over dates is the PostgreSQL idiom here and replaces the
-- recursive CTE or WHILE loop a T-SQL implementation would use.
-- ============================================================================
CREATE OR REPLACE FUNCTION warehouse.populate_dim_date(
    p_from_date date DEFAULT '1994-01-01',
    p_to_date   date DEFAULT '2002-12-31'
)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_inserted integer;
BEGIN
    IF p_to_date < p_from_date THEN
        RAISE EXCEPTION 'populate_dim_date: end date % precedes start date %',
                        p_to_date, p_from_date
              USING ERRCODE = 'invalid_parameter_value';
    END IF;

    INSERT INTO warehouse.dim_date (
        date_key, full_date,
        day_of_month, day_of_week, day_name, day_of_year,
        week_of_year, iso_year,
        month_number, month_name, month_abbrev, month_end_date, year_month,
        quarter_number, quarter_name, year_number,
        fiscal_year, fiscal_quarter,
        is_weekend, is_last_day_of_month
    )
    SELECT
        warehouse.to_date_key(d::date),
        d::date,
        EXTRACT(DAY   FROM d)::smallint,
        EXTRACT(ISODOW FROM d)::smallint,
        TRIM(TO_CHAR(d, 'Day')),
        EXTRACT(DOY   FROM d)::smallint,
        EXTRACT(WEEK  FROM d)::smallint,
        EXTRACT(ISOYEAR FROM d)::smallint,
        EXTRACT(MONTH FROM d)::smallint,
        TRIM(TO_CHAR(d, 'Month')),
        TO_CHAR(d, 'Mon'),
        (date_trunc('month', d) + INTERVAL '1 month - 1 day')::date,
        (EXTRACT(YEAR FROM d) * 100 + EXTRACT(MONTH FROM d))::integer,
        EXTRACT(QUARTER FROM d)::smallint,
        'Q' || EXTRACT(QUARTER FROM d)::text,
        EXTRACT(YEAR FROM d)::smallint,

        -- UK fiscal year: starts 1 April, named for the calendar year it ends in.
        CASE WHEN EXTRACT(MONTH FROM d) >= 4
             THEN EXTRACT(YEAR FROM d) + 1
             ELSE EXTRACT(YEAR FROM d)
        END::smallint,
        -- Fiscal quarter: Apr-Jun = 1 ... Jan-Mar = 4.
        ((((EXTRACT(MONTH FROM d)::integer - 4) + 12) % 12) / 3 + 1)::smallint,

        EXTRACT(ISODOW FROM d) IN (6, 7),
        d::date = (date_trunc('month', d) + INTERVAL '1 month - 1 day')::date
    FROM generate_series(p_from_date::timestamp, p_to_date::timestamp, INTERVAL '1 day') AS d
    ON CONFLICT (date_key) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RETURN v_inserted;
END;
$$;

COMMENT ON FUNCTION warehouse.populate_dim_date(date, date) IS
    'Generates calendar rows for the given range. Idempotent - existing keys '
    'are skipped. Returns the number of rows inserted.';
