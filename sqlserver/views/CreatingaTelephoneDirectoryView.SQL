USE Northwind;
GO

CREATE VIEW ContactDirectory AS
-- Combined contact information from all sources
SELECT 
    CompanyName, 
    ContactName, 
    Phone,
    'Customer' AS ContactType
FROM Customers

UNION ALL

SELECT 
    CompanyName, 
    ContactName, 
    Phone,
    'Supplier' AS ContactType
FROM Suppliers

UNION ALL

SELECT 
    'Northwind Traders' AS CompanyName, 
    CONCAT(FirstName, ' ', LastName) AS ContactName, 
    Extension AS Phone,
    'Employee' AS ContactType
FROM Employees;
GO