--USE QASTORE
SELECT *
FROM company

--SELECT first three chars from the left of the field
SELECT name, county,
LEFT(county, 3) AS location
FROM company

--SELECT last three chars from the right of the field
SELECT name, county,
RIGHT(county, 3) AS location
FROM company

--Upper and Lower functions
SELECT Upper(county) as UpperCounty
FROM company


SELECT Lower(county) as LowerCounty
FROM company

SELECT post_code,tel, SUBSTRING(tel, 2,3) AS TelCode
FROM company




SELECT *
FROM contact

SELECT name, tel, SUBSTRING(name, 4,3) as ShortName
FROM contact

--dates

SELECT datediff(day, '2024-04-09','2025-04-09')
SELECT datediff(SECOND, '2024-04-09','2025-04-09')

SELECT DATEPART(year,GETDATE())
SELECT DATEPART(DAY,GETDATE())
SELECT DATEPART(MONTH,GETDATE())

SELECT order_no, description, order_date,
DATEPART(YEAR, order_date) AS OrderYear,
DATEPART(MONTH, order_date) AS OrderMonth,
DATEPART(DAY, order_date) AS OrderDay
from sale

select * from dept
SELECT * from company


use Northwind
--demo of ISNULL
SELECT CustomerID, CompanyName, Phone, FAX
from Customers

SELECT CustomerID, CompanyName, Phone, ISNULL(FAX, 'no fax') as FAX
from Customers

--NULLIF
SELECT UnitsInStock, UnitsOnOrder,
NULLIF(UnitsInStock, UnitsOnOrder) As AdjustedStock
from Products

--Coalesce returns the first non-null value.
SELECT CustomerID,CompanyName, Phone, Fax, COALESCE(Fax,'no comms') as COMMS
FROM Customers

--CAST
SELECT OrderID, OrderDate,
CAST(OrderDate AS varchar(20)) as OrderDate_String
FROM Orders
--CONVERT SAME AS ABOVE, BUT DIFFERENT SYNTAX
SELECT OrderID, OrderDate,
CONVERT(varchar(20),OrderDate) as OrderDate_String
FROM Orders


SELECT ROUND(5.67,0)
SELECT ROUND(5.67,1)
SELECT CAST(6.57 AS INT)

--select statement with rounding
SELECT ProductID,ProductName, UnitPrice, (UnitPrice*UnitsInStock) as Revenue,
ROUND(UnitPrice*UnitsInStock, 0) As RoundedRevenue
from Products
--cast statement to remove trailing zeros in the rounded revenue columns
SELECT ProductID,ProductName, UnitPrice, (UnitPrice*UnitsInStock) as Revenue,
cast(ROUND(UnitPrice*UnitsInStock, 0)as int) As RoundedRevenue
from Products


--USE QAstore
--select tel, 
--left(tel, charindex('-', tel) -1)
--from company
--where CHARINDEX('-', tel)>0
