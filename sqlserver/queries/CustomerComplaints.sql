USE Northwind
Go

SELECT * FROM Orders;

SELECT CustomerID
FROM Orders
WHERE CustomerID in ('ALFKI' , 'ERNSH' ,'SIMOB') AND OrderDate < '19970831'

