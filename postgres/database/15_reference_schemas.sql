-- ============================================================================
-- 15_reference_schemas.sql
--
-- Ports of the three smaller training databases: QAStore, QATSQLPLUS and
-- REVENUE. Run after 00_schemas.sql. Independent of the warehouse - nothing
-- downstream reads these tables.
--
-- They are ported for completeness of the migration rather than for the
-- warehouse, and because between them they exercise the dialect features the
-- Northwind port does not:
--
--   QAStore     composite primary key and composite FOREIGN KEY (sale ->
--               contact on two columns), and a table named `sale` whose column
--               `description` is non-reserved in T-SQL but must still be
--               handled carefully in PL/pgSQL.
--   QATSQLPLUS  IDENTITY columns loaded with explicit values via
--               SET IDENTITY_INSERT, and a CHECK constraint on stock.
--   REVENUE     a column named `Year`, which is a reserved word in neither
--               dialect but collides with the SQL standard's YEAR keyword and
--               is renamed on principle.
--
-- Source files:
--   sqlserver/database/qastore/create_qastore.sql
--   sqlserver/database/qatsqlplus/qatsqlplus_setup.sql
--   sqlserver/database/revenue/create_revenue.sql
-- ============================================================================

SET search_path = reference, public;

DROP TABLE IF EXISTS reference.sale                CASCADE;
DROP TABLE IF EXISTS reference.salesperson         CASCADE;
DROP TABLE IF EXISTS reference.contact             CASCADE;
DROP TABLE IF EXISTS reference.dept                CASCADE;
DROP TABLE IF EXISTS reference.company             CASCADE;
DROP TABLE IF EXISTS reference.delegate_attendance CASCADE;
DROP TABLE IF EXISTS reference.course_run          CASCADE;
DROP TABLE IF EXISTS reference.delegate            CASCADE;
DROP TABLE IF EXISTS reference.trainer             CASCADE;
DROP TABLE IF EXISTS reference.course              CASCADE;
DROP TABLE IF EXISTS reference.vendor              CASCADE;
DROP TABLE IF EXISTS reference.book_transfers      CASCADE;
DROP TABLE IF EXISTS reference.book_stock          CASCADE;
DROP TABLE IF EXISTS reference.revenue             CASCADE;

-- ============================================================================
-- QAStore
-- ============================================================================

CREATE TABLE reference.company (
    company_no   integer      NOT NULL,
    name         varchar(20)  NOT NULL,
    tel          char(15)     NULL,
    county       varchar(15)  NULL,
    post_code    char(10)     NULL,

    CONSTRAINT pk_company PRIMARY KEY (company_no)
);

CREATE TABLE reference.dept (
    dept_no       integer         NOT NULL,
    dept_name     char(20)        NOT NULL,
    manager       char(20)        NULL,
    sales_target  numeric(12,4)   NULL,

    CONSTRAINT pk_dept PRIMARY KEY (dept_no)
);

-- Composite primary key. Ports unchanged - both dialects express this the same
-- way. The clustered/nonclustered distinction in the source is dropped:
-- PostgreSQL has no clustered indexes, and CLUSTER is a one-off physical
-- reorganisation rather than a maintained property. See docs/migration-guide.md.
CREATE TABLE reference.contact (
    company_no    integer      NOT NULL,
    contact_code  char(3)      NOT NULL,
    name          varchar(20)  NULL,
    job_title     varchar(30)  NULL,
    tel           char(25)     NULL,
    notes         varchar(60)  NULL,

    CONSTRAINT pk_contact PRIMARY KEY (company_no, contact_code),

    CONSTRAINT fk_contact_company
        FOREIGN KEY (company_no) REFERENCES reference.company (company_no)
);

CREATE TABLE reference.salesperson (
    emp_no        integer         NOT NULL,
    fname         varchar(15)     NULL,
    lname         varchar(15)     NOT NULL,
    dept_no       integer         NULL,
    sales_target  numeric(12,4)   NULL,
    county        varchar(15)     NULL,
    post_code     char(10)        NULL,
    tel           varchar(15)     NULL,
    notes         varchar(50)     NULL,

    CONSTRAINT pk_salesperson PRIMARY KEY (emp_no),

    CONSTRAINT fk_salesperson_dept
        FOREIGN KEY (dept_no) REFERENCES reference.dept (dept_no)
);

-- The composite foreign key is the reason this schema is worth porting: it
-- references the two-column primary key of `contact`. Column order in the
-- REFERENCES clause must match the referenced key's order, in both dialects.
CREATE TABLE reference.sale (
    order_no        integer       NOT NULL,
    emp_no          integer       NOT NULL,
    their_order_no  varchar(15)   NULL,
    company_no      integer       NOT NULL,
    contact_code    char(3)       NOT NULL,
    order_value     integer       NULL,
    order_date      timestamp(3)  NULL,
    description     varchar(140)  NOT NULL,

    CONSTRAINT pk_sale PRIMARY KEY (order_no),

    CONSTRAINT fk_sale_contact
        FOREIGN KEY (company_no, contact_code)
        REFERENCES reference.contact (company_no, contact_code),

    CONSTRAINT fk_sale_salesperson
        FOREIGN KEY (emp_no) REFERENCES reference.salesperson (emp_no)
);

COMMENT ON CONSTRAINT fk_sale_contact ON reference.sale IS
    'Composite foreign key onto contact(company_no, contact_code).';

-- ============================================================================
-- QATSQLPLUS
--
-- IDENTITY(1,1) -> GENERATED BY DEFAULT AS IDENTITY throughout. The source
-- loads these tables with explicit key values wrapped in SET IDENTITY_INSERT
-- ON/OFF (course ids such as 20761 are Microsoft course codes, not sequence
-- values). BY DEFAULT accepts those explicit values without ceremony;
-- GENERATED ALWAYS would require OVERRIDING SYSTEM VALUE on every insert.
--
-- The sequences must be resynchronised after loading - see postgres/seed/.
-- ============================================================================

CREATE TABLE reference.vendor (
    vendor_id     integer       GENERATED BY DEFAULT AS IDENTITY,
    vendor_name   varchar(100)  NOT NULL,
    contact_name  varchar(100)  NOT NULL,
    phone_number  varchar(15)   NULL,

    CONSTRAINT pk_vendor PRIMARY KEY (vendor_id)
);

CREATE TABLE reference.course (
    course_id    integer       GENERATED BY DEFAULT AS IDENTITY,
    course_name  varchar(200)  NOT NULL,
    vendor_id    integer       NOT NULL,

    CONSTRAINT pk_course PRIMARY KEY (course_id),
    CONSTRAINT fk_course_vendor
        FOREIGN KEY (vendor_id) REFERENCES reference.vendor (vendor_id)
);

CREATE TABLE reference.trainer (
    trainer_id    integer       GENERATED BY DEFAULT AS IDENTITY,
    trainer_name  varchar(100)  NOT NULL,
    phone_number  varchar(15)   NULL,

    CONSTRAINT pk_trainer PRIMARY KEY (trainer_id)
);

CREATE TABLE reference.delegate (
    delegate_id    integer       GENERATED BY DEFAULT AS IDENTITY,
    delegate_name  varchar(100)  NOT NULL,
    company_name   varchar(50)   NULL,

    CONSTRAINT pk_delegate PRIMARY KEY (delegate_id)
);

CREATE TABLE reference.course_run (
    course_run_id  integer  GENERATED BY DEFAULT AS IDENTITY,
    course_id      integer  NOT NULL,
    trainer_id     integer  NOT NULL,
    start_date     date     NOT NULL,
    duration_days  integer  NOT NULL,

    CONSTRAINT pk_course_run PRIMARY KEY (course_run_id),
    CONSTRAINT fk_course_run_course
        FOREIGN KEY (course_id)  REFERENCES reference.course  (course_id),
    CONSTRAINT fk_course_run_trainer
        FOREIGN KEY (trainer_id) REFERENCES reference.trainer (trainer_id)
);

CREATE TABLE reference.delegate_attendance (
    attendance_id  integer  GENERATED BY DEFAULT AS IDENTITY,
    course_run_id  integer  NOT NULL,
    delegate_id    integer  NOT NULL,

    CONSTRAINT pk_delegate_attendance PRIMARY KEY (attendance_id),
    CONSTRAINT fk_attendance_course_run
        FOREIGN KEY (course_run_id) REFERENCES reference.course_run (course_run_id),
    CONSTRAINT fk_attendance_delegate
        FOREIGN KEY (delegate_id)   REFERENCES reference.delegate   (delegate_id)
);

-- No primary key in the source. Preserved as-is: adding one would change the
-- behaviour of the ResetBookStock procedure being ported alongside it.
CREATE TABLE reference.book_transfers (
    product_id       integer       NOT NULL,
    transfer_date    timestamp(3)  NOT NULL,
    transfer_reason  varchar(30)   NOT NULL,
    transfer_amount  integer       NOT NULL
);

CREATE TABLE reference.book_stock (
    product_id    integer  NOT NULL,
    stock_amount  integer  NOT NULL,

    CONSTRAINT ck_book_stock_non_negative CHECK (stock_amount >= 0)
);

COMMENT ON TABLE reference.book_transfers IS
    'Port of dbo.BookTransfers. No primary key in the source; preserved as-is.';

-- ============================================================================
-- REVENUE
--
-- The source column is named [Year]. Renamed to revenue_year: `year` is not
-- reserved in PostgreSQL, but it is a keyword in the SQL standard's interval
-- syntax (EXTRACT(YEAR FROM ...)), and a column that must be quoted to be read
-- safely is a column that will eventually be read unsafely.
-- ============================================================================
CREATE TABLE reference.revenue (
    department_id  integer  NULL,
    revenue        integer  NULL,
    revenue_year   integer  NULL
);

COMMENT ON COLUMN reference.revenue.revenue_year IS
    'Source column [Year], renamed to avoid keyword collision.';
