--COMPARISON OPERATORS

--= : EQUALS TO
--< : LESS THAN
--<=: LESS THAN OR EQUAL TO
--> : MORE THAN
-->=: MORE THANK OR EQUAL TO
--<>: NOT EQUAL TO
--!=: NOT EQUAL TO

--Use Northwind

SELECT FirstName, LastName, City, Country
FROM [dbo].[Employees]
WHERE Country = 'Usa'

SELECT ProductID, ProductName, UnitPrice
FROM Products
WHERE UnitPrice <=30

SELECT FirstName, LastName, City, Country
FROM [dbo].[Employees]
WHERE Country = 'Usa' AND City='SEATTLE'

SELECT FirstName, LastName, City, Country
FROM [dbo].[Employees]
WHERE Country = 'Usa' OR City='SEATTLE'

--EXAMPLE OF Precedant
SELECT ProductID, ProductName, CategoryID, UnitPrice
FROM Products
WHERE CategoryID = 7 OR CategoryID = 8 AND UnitPrice > 40

SELECT ProductID, ProductName, CategoryID, UnitPrice
FROM Products
WHERE (CategoryID = 7 OR CategoryID = 8) AND UnitPrice > 40

SELECT ProductID, ProductName, UnitsInStock + UnitsOnOrder AS  FutureStock 
FROM dbo.Products 
WHERE (UnitsInStock + UnitsOnOrder) < 10


SELECT CONCAT(FirstName, ' ',LastName) as Fullname, Extension
FROM Employees

--using between
Select ProductID, ProductName, CategoryID, UnitPrice
FROM Products
WHERE  UnitPrice between 40 and 70
--and AND
Select ProductID, ProductName, CategoryID, UnitPrice
FROM Products
WHERE CategoryID IN (3,7,4) AND UnitPrice< 30

--using LIKE
Select CustomerID,CompanyName, City, Country
FROM Customers
WHERE Country LIKE '__r%'

Select CustomerID,CompanyName, City, Country
FROM Customers
WHERE Country LIKE '%r_'

Select CustomerID,CompanyName, City, Country
FROM Customers
WHERE Country LIKE 'g__M%'

--including starting with b,s,r
Select CustomerID,CompanyName, City, Country
FROM Customers
WHERE Country LIKE '[b,s,r]%'

--excluding starting with b,s,r
Select CustomerID,CompanyName, City, Country
FROM Customers
WHERE Country LIKE '[^b,s,r]%'


Select CustomerID,CompanyName, City, Country
FROM Customers
WHERE Country LIKE '[g-s]%'

--SELECT NULL RECORDS
SELECT CompanyName,Phone,Fax
FROM Customers
WHERE Fax is NOT  NULL

--case statement

SELECT ProductID,ProductName, UnitPrice,
CASE
	WHEN unitprice > 100 then 'Price level 1'
	WHEN unitprice <= 100 AND UnitPrice > 70 then 'Price level 2'
	WHEN unitprice <= 70 AND UnitPrice > 40 then 'Price level 3'
	WHEN unitprice <= 40 AND UnitPrice > 20 then 'Price level 4'
	ELSE 'Price Level 5'
	END As 'Price Level'
FROM Products
Order by UnitPrice DESC

