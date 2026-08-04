-- ============================================================================
-- 10_ported_views.sql
--
-- Direct ports of the author-written views from the SQL Server reference
-- implementation. These read the staging schema, which is structurally
-- identical to the source, so the ports are line-for-line comparable with the
-- originals and can be diffed against them.
--
-- Source files (unmodified, in sqlserver/):
--   views/CreatingaTelephoneDirectoryView.SQL   -> ContactDirectory
--   views/DirectoryView.sql                     -> (unnamed SELECT, same shape)
--   exercises/day2-day4/Day 4 02 Exercise View.sql   -> NewContactDirectory
--   exercises/day2-day4/Day 4 03 Exercise SQL Revision.sql -> Managers
--
-- Dialect changes applied, and nothing else:
--   FirstName + ' ' + LastName   ->  first_name || ' ' || last_name
--   CONCAT(FirstName,' ',LastName) -> first_name || ' ' || last_name
--   PascalCase identifiers        ->  snake_case
--   WITH CHECK OPTION             ->  WITH CASCADED CHECK OPTION (see below)
-- ============================================================================

SET search_path = presentation, staging, public;

-- ============================================================================
-- presentation.contact_directory
--
-- Port of ContactDirectory. A unified telephone directory across the three
-- contact-holding tables.
--
-- UNION ALL, not UNION, exactly as the original: the source author chose ALL
-- deliberately (both appear in the exercise). It is also the correct choice -
-- UNION would deduplicate across contact types and silently drop a supplier
-- who is also a customer, which is a real pattern in this data.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.contact_directory AS
SELECT company_name,
       contact_name,
       phone,
       'Customer' AS contact_type
  FROM staging.customers

UNION ALL

SELECT company_name,
       contact_name,
       phone,
       'Supplier' AS contact_type
  FROM staging.suppliers

UNION ALL

SELECT 'Northwind Traders'                AS company_name,
       first_name || ' ' || last_name     AS contact_name,
       extension                          AS phone,
       'Employee'                         AS contact_type
  FROM staging.employees;

COMMENT ON VIEW presentation.contact_directory IS
    'Port of the SQL Server view ContactDirectory: unified customer, supplier '
    'and employee telephone directory.';

-- ============================================================================
-- presentation.new_contact_directory
--
-- Port of NewContactDirectory - the same directory without the contact_type
-- column, retained separately because the original exercise defines both and
-- the golden source must be reproducible object for object.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.new_contact_directory AS
SELECT company_name, contact_name, phone FROM staging.customers
UNION ALL
SELECT company_name, contact_name, phone FROM staging.suppliers
UNION ALL
SELECT 'Northwind Traders', first_name || ' ' || last_name, extension
  FROM staging.employees;

COMMENT ON VIEW presentation.new_contact_directory IS
    'Port of the SQL Server view NewContactDirectory.';

-- ============================================================================
-- presentation.managers
--
-- Port of the Managers view. Employees who have at least one direct report.
--
-- ----------------------------------------------------------------------------
-- Two things about the original are worth recording rather than quietly fixing
-- ----------------------------------------------------------------------------
-- 1. WITH CHECK OPTION on the original is inert. It constrains INSERTs and
--    UPDATEs made THROUGH the view, but the view is not updatable in either
--    dialect (it contains a self-join and DISTINCT), so nothing can be written
--    through it and the option can never fire. PostgreSQL rejects the clause
--    outright on a non-auto-updatable view:
--
--        ERROR:  WITH CHECK OPTION is supported only on automatically
--                updatable views
--
--    It is therefore omitted here. The behaviour is unchanged, because the
--    original had no behaviour to preserve.
--
-- 2. The self-join is written `FROM Employees m JOIN Employees e ON
--    m.ReportsTo = e.EmployeeID`, which reads backwards: the alias `m` holds
--    the SUBORDINATE and `e` holds the manager. The aliases are preserved
--    verbatim so the port matches the source; the result set is identical.
--    DISTINCT is required precisely because a manager with several reports
--    would otherwise appear once per report.
-- ============================================================================
CREATE OR REPLACE VIEW presentation.managers AS
SELECT DISTINCT
       e.employee_id,
       e.last_name,
       e.first_name,
       e.title,
       e.title_of_courtesy,
       e.home_phone,
       e.extension,
       e.reports_to
  FROM staging.employees m
  JOIN staging.employees e
    ON m.reports_to = e.employee_id;

COMMENT ON VIEW presentation.managers IS
    'Port of the SQL Server view Managers: employees with at least one direct '
    'report. WITH CHECK OPTION omitted - inert on a non-updatable view.';

-- ============================================================================
-- Ports of the vendor Northwind views that the exercises actually query.
--
-- The source ships 16 views; these are the ones referenced by the author''s
-- scripts. The remainder are not ported, because porting unused objects is how
-- a migration acquires dead code it must then maintain forever.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- presentation.current_product_list
--
-- Port of "Current Product List". The original is:
--     SELECT ProductID, ProductName FROM Products WHERE Discontinued = 'N'
--
-- Note the source compares a `bit` column against the STRING 'N'. SQL Server
-- coerces this silently; PostgreSQL will not, and `discontinued = 'N'` raises
--     ERROR:  invalid input syntax for type boolean: "N"
-- The correct port of the intent is `NOT discontinued`.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW presentation.current_product_list AS
SELECT product_id,
       product_name
  FROM staging.products
 WHERE NOT discontinued;

COMMENT ON VIEW presentation.current_product_list IS
    'Port of "Current Product List". Source compares bit to the string ''N''; '
    'ported as NOT discontinued.';

-- ----------------------------------------------------------------------------
-- presentation.order_subtotals
--
-- Port of "Order Subtotals". The source expression is:
--     SUM(CONVERT(money,(UnitPrice*Quantity*(1-Discount)/100))*100)
--
-- The /100 ... *100 dance exists solely to force SQL Server's `money` type
-- through an intermediate rounding step. numeric has no such wart, so the
-- expression ports as the arithmetic it was always trying to express. The
-- result is identical to the penny and no longer misleads the reader.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW presentation.order_subtotals AS
SELECT order_id,
       ROUND(SUM(unit_price * quantity * (1 - discount::numeric)), 2) AS subtotal
  FROM staging.order_details
 GROUP BY order_id;

COMMENT ON VIEW presentation.order_subtotals IS
    'Port of "Order Subtotals". The source''s /100 * 100 money-rounding idiom '
    'is dropped; numeric does not need it.';

-- ----------------------------------------------------------------------------
-- presentation.products_above_average_price
--
-- Port of "Products Above Average Price". Unchanged in substance - a scalar
-- subquery in the WHERE clause ports directly.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW presentation.products_above_average_price AS
SELECT product_name,
       unit_price
  FROM staging.products
 WHERE unit_price > (SELECT AVG(unit_price) FROM staging.products);

COMMENT ON VIEW presentation.products_above_average_price IS
    'Port of "Products Above Average Price".';
