USE Northwind


SELECT *
FROM Employees

select distinct Title
from [dbo].[Employees]

--sorting by 2 categories
SELECT ProductNAME, UnitPrice, CategoryID
FROM Products 
ORDER BY  CategoryID,UnitPrice desc

SELECT TOP 10 PERCENT ProductName,UnitPrice
from Products

select * 
from products

select ProductID, ProductName,
(UnitsInStock + UnitsOnOrder) *UnitPrice AS StockCost
from Products
--WHERE StockCost >1000
--WHERE (UnitsInStock + UnitsOnOrder) *UnitPrice >1000
ORDER BY StockCost
--ORDER BY (UnitsInStock + UnitsOnOrder) *UnitPrice



Select top 15 WITH TIES UnitPrice, ProductID, ProductName
FROM Products
ORDER BY UnitPrice DESC

Select top 15 UnitPrice, ProductID, ProductName
FROM Products
ORDER BY UnitPrice DESC