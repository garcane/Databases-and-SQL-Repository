Use Northwind
--Deck fix questions

--SELECT ProductID, ProductName
--FROM Products
--WHERE UnitPrice BETWEEEN 40 AND 30

--Exercies 1 Task1
--Use Northwind

SELECT ProductID, [ProductName],[CategoryID],[Discontinued],[UnitPrice]
FROM Products

SELECT ProductID, [ProductName],[CategoryID],[Discontinued],[UnitPrice]
FROM Products
WHERE Discontinued = 0

--Task 2
SELECT ProductID, [ProductName],[CategoryID],[Discontinued],[UnitPrice]
FROM Products
WHERE Discontinued = 0 AND CategoryID =1

--Task 3
SELECT ProductID, [ProductName],[CategoryID],[Discontinued],[UnitPrice]
FROM Products
WHERE Discontinued = 0 AND CategoryID =1 AND UnitPrice >=40

--Exercies 2 Task1
SELECT *
FROM [dbo].[Orders]
WHERE [CustomerID] IN ('ALFKI','ERNSH','SIMOB') 

--Task 2
SELECT *
FROM [dbo].[Orders]
WHERE [CustomerID] IN ('ALFKI','ERNSH','SIMOB') AND 
OrderDate BETWEEN '19970801' AND '19970831'

--Extension
SELECT ProductID, [ProductName],[CategoryID],[Discontinued],[UnitPrice]
FROM Products
WHERE Discontinued = 0 AND (CategoryID =1 OR CategoryID=8) AND UnitPrice >=40

SELECT *
FROM [dbo].[Orders]
WHERE [CustomerID] IN ('ALFKI','ERNSH','SIMOB') AND 
OrderDate BETWEEN '19970801' AND '19971231' AND EmployeeID IN (1,3,5,7,9)


--Exercise 3 Task 1
USE Northwind

SELECT [CustomerID],[CompanyName],[ContactName],[ContactTitle],[Phone]
FROM Customers
WHERE ContactTitle Like 'sales%'


--Exercise 3 Task 2
SELECT [CustomerID],[CompanyName],[ContactName],[ContactTitle],[Phone]
FROM Customers
WHERE ContactTitle Like '%sales%'

--Exercise 3 Task 3
SELECT [CustomerID],[CompanyName],[ContactName],[ContactTitle],[Phone]
FROM Customers
WHERE ContactTitle Like '%Sales%'

--Use Northwind
--Exercise 4 Task 1
SELECT [CustomerID],[CompanyName],[ContactName],[ContactTitle],[Phone],[Fax]
FROM [dbo].[Customers]
WHERE Fax IS NULL


--extension
SELECT [CustomerID],[CompanyName],[ContactName],[ContactTitle],[Phone],[Fax]
FROM [dbo].[Customers]
WHERE Fax = NULL
