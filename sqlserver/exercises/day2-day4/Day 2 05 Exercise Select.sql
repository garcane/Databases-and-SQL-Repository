--Use Northwind
--Ex 1 Task 1
SELECT ProductID,ProductName,(UnitPrice * UnitsInStock) AS CurrentValueStock, 
FROM dbo.Products

--Task2
SELECT ProductID,ProductName,UnitPrice, UnitsInStock, UnitsOnOrder, (UnitPrice * UnitsInStock) AS CurrentValueStock,
	((UnitsInStock+UnitsOnOrder)*UnitPrice) AS FutureStockValue 
FROM dbo.Products

--Exercise 2

SELECT 
    ProductID,
    ProductName,
    UnitPrice,
    UnitsInStock,
    UnitsOnOrder,
    -- Calculate CurrentStockValue as UnitPrice * UnitsInStock
    (UnitPrice * UnitsInStock) AS CurrentStockValue,
    -- Calculate FutureStockValue as (UnitsInStock + UnitsOnOrder) * UnitPrice
    ((UnitsInStock + UnitsOnOrder) * UnitPrice) AS FutureStockValue
FROM 
    Products;

--Extension

SELECT (FirstName, +, LastName) AS FullName, Extension
FROM Employees

--SELECT CONCAT(FirstName, ' ',LastName), Extension
--FROM Employees