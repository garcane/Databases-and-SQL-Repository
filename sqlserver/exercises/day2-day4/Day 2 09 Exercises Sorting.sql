--Ex1 task 1
SELECT  [ProductID],[ProductName],[CategoryID],[Discontinued],[UnitPrice]
FROM Products
WHERE Discontinued = 0

--TASK 2
SELECT  [ProductID],[ProductName],[CategoryID],[Discontinued],[UnitPrice]
FROM Products
WHERE Discontinued = 0
ORDER BY CategoryID

--TASK 3
SELECT  [ProductID],[ProductName],[CategoryID],[Discontinued],[UnitPrice]
FROM Products
WHERE Discontinued = 0
ORDER BY CategoryID,UnitPrice DESC


--EX 2 task 1

SELECT
 ProductID, ProductName, UnitPrice, UnitsInStock, UnitsOnOrder,
 UnitPrice * UnitsInStock AS CurrentStockValue,
 (UnitsInStock + UnitsOnOrder) * UnitPrice AS FutureStockValue
FROM
 Products

 --task 2
 SELECT
 ProductID, ProductName, UnitPrice, UnitsInStock, UnitsOnOrder,
 UnitPrice * UnitsInStock AS CurrentStockValue,
 (UnitsInStock + UnitsOnOrder) * UnitPrice AS FutureStockValue
FROM Products
ORDER BY FutureStockValue DESC

SELECT
 ProductID, ProductName, UnitPrice, UnitsInStock, UnitsOnOrder,
 UnitPrice * UnitsInStock AS CurrentStockValue,
 (UnitsInStock + UnitsOnOrder) * UnitPrice AS FutureStockValue
FROM Products
ORDER BY  (UnitsInStock + UnitsOnOrder) * UnitPrice DESC

SELECT
 ProductID, ProductName, UnitPrice, UnitsInStock, UnitsOnOrder,
 UnitPrice * UnitsInStock AS CurrentStockValue,
 (UnitsInStock + UnitsOnOrder) * UnitPrice AS FutureStockValue
FROM Products
ORDER BY   UnitPrice * UnitsInStock + (UnitsOnOrder * UnitPrice) DESC

--Exercise 3 Task 1
SELECT Country
FROM Customers

--Task 2
SELECT Distinct Country
FROM Customers

--Exercise 4 
SELECT ProductID, ProductName, UnitPrice
FROM Products
ORDER BY UnitPrice DESC

SELECT TOP 10 ProductID, ProductName, UnitPrice
FROM Products
ORDER BY UnitPrice DESC

SELECT Top 15 WITH TIES UnitPrice, ProductID, ProductName
FROM Products
ORDER BY UnitPrice DESC

SELECT Top 15 WITH TIES UnitPrice, ProductID, ProductName
FROM Products
ORDER BY UnitPrice DESC