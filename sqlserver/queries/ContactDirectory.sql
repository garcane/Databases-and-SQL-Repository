--Exercise 1: Create a telephone directory

USE Northwind
GO
--Task 1: Write a query that retrieves Customer contact details

--SELECT * FROM Customers -- To view the table itself
SELECT CompanyName, ContactName, Phone FROM Customers


---Task 2: Write a query that retrieves Supplier contact details
SELECT CompanyName, ContactName, Phone FROM Suppliers

--Task 3: Write a query that retrieves Employee contact details
SELECT CONCAT(FirstName, ' ', LastName) AS FullName, Extension FROM Employees



---Task 4: Combine the results using the UNION operator

-- Initial queries (step 1-2)
SELECT CompanyName, ContactName, Phone FROM Customers;
SELECT CompanyName, ContactName, Phone FROM Suppliers;

-- Combined with UNION (step 3-7)
SELECT CompanyName, ContactName, Phone FROM Customers
UNION
SELECT CompanyName, ContactName, Phone FROM Suppliers
UNION
SELECT 'Northwind Traders' AS CompanyName, 
       CONCAT(FirstName, ' ', LastName) AS ContactName, 
       Extension AS Phone 
FROM Employees;

-- Using UNION ALL (step 8)
SELECT CompanyName, ContactName, Phone FROM Customers
UNION ALL
SELECT CompanyName, ContactName, Phone FROM Suppliers
UNION ALL
SELECT 'Northwind Traders' AS CompanyName, 
       CONCAT(FirstName, ' ', LastName) AS ContactName, 
       Extension AS Phone 
FROM Employees;

-- With ORDER BY (step 9)
SELECT CompanyName, ContactName, Phone FROM Customers
UNION ALL
SELECT CompanyName, ContactName, Phone FROM Suppliers
UNION ALL
SELECT 'Northwind Traders' AS CompanyName, 
       CONCAT(FirstName, ' ', LastName) AS ContactName, 
       Extension AS Phone 
FROM Employees
ORDER BY CompanyName;


