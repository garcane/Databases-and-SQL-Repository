
--Use QAStore
--Ex 1 
SELECT emp_no,lname,
(LEFT(fname, 1)' ',lname),
FROM Salesperson

--selects first five chars from the left of the field
SELECT CustomerID, ContactName, 
LEFT(ContactName, 5) AS ShortName
FROM Customers

--selects first five chars from the left of the field
SELECT CustomerID, ContactName, 
right(ContactName, 5) AS ShortName
FROM Customers

SELECT CustomerID, 
Upper(CompanyName) AS UpperCaseCoName, CompanyName
FROM Customers

SELECT CustomerID,
Lower(CompanyName) AS LowerCaseCoName, CompanyName
FROM Customers


Select CustomerID, SUBSTRING(CustomerID, 2, 3) AS CustCode
from Customers

Select CustomerID, SUBSTRING(CompanyName, 5, 6) AS CompanySegment
from Customers

SELECT Phone, SUBSTRING(Phone, 2,3) AS AreaCode
from Customers

SELECT LOWER(CustomerID) AS CustomerID,
SUBSTRING(CompanyName, 3, 4) AS Company,
LEFT(ContactName, 1) as Initial
from Customers

---dates
Select DATEDIFF(day, '2023-01-01', '2023-09-30')
Select DATEDIFF(hour, '2023-01-01', '2023-09-30')

--select part of the date in number and name form
SELECT DATEPART(year,GETDATE())
SELECT DATEPART(day,GETDATE())
SELECT DATEname(month,GETDATE())

SELECT [OrderID],[CustomerID],[OrderDate],[ShippedDate],
DATEDIFF(DAY,[OrderDate],[ShippedDate] ) AS ElapsedDays,
DATEPART(DAY, [OrderDate]) AS OrderDay,
DATEPART(MONTH, [OrderDate]) AS OrderMonth,
DATENAME(MONTH, OrderDate)AS OrderMonthName,
DATEPART(YEAR, [OrderDate]) AS Orderyear,

from Orders

SELECT * FROM Customers

SELECT CustomerID, CompanyName, Phone, ISNULL(FAX, 'no fax') as FAX
from Customers

SELECT * FROM Products

--The NULLIF() function returns NULL if two expressions are equal, otherwise it returns the first expression.
SELECT UnitsInStock, UnitsOnOrder, 
NULLIF(UnitsInStock, UnitsOnOrder) As AdjustedStock
FROM Products

--Coalesce returns the first non-null value in a list. If all the values in the list are NULL, then the function returns null.
SELECT CustomerID, CompanyName, Phone, Fax, COALESCE(FAX, Phone, 'no comms' ) as Comms
from Customers

--CAST change DataType
SELECT OrderID, OrderDate,
CAST(OrderDate AS varchar(20)) AS OrderDate_String
FROM Orders

SELECT OrderID, OrderDate,
CONVERT(varchar(20),OrderDate) AS OrderDate_String
FROM Orders

SELECT OrderID, OrderDate,
CONVERT(varchar(20),OrderDate,103) AS OrderDate_String
FROM Orders


SELECT ROUND(5.67,0)
SELECT ROUND(5.67,1)
SELECT CAST(6.57 AS INT)

SELECT ProductID, ProductName, UnitPrice,
ROUND(UnitPrice*UnitsInStock, 0) AS Revenue
from Products

--cast removing trailing zeros
SELECT ProductID, ProductName, UnitPrice,
CAST(ROUND(UnitPrice*UnitsInStock, 0)AS INT) AS Revenue
from Products
