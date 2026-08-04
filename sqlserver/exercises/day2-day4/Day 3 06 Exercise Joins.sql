Use Northwind
--Join Exercises
--Task 1
SELECT c.CustomerID, CompanyName, ContactName, City
FROM Customers c join Orders o
on c.CustomerID = o.CustomerID

--Task 2
SELECT c.CustomerID, CompanyName, ContactName, City
FROM Customers c join Orders o
on c.CustomerID = o.CustomerID
WHERE C.Country = 'UK'

SELECT c.CustomerID, CompanyName, ContactName, City, OrderDate
FROM Customers c join Orders o
on c.CustomerID = o.CustomerID
WHERE C.Country = 'UK'
ORDER BY CompanyName, OrderDate

--Task 3
SELECT c.CustomerID, CompanyName, ContactName,  OrderDate, od.ProductID, Quantity, p.ProductName
FROM Customers c JOIN Orders o 
on c.CustomerID = o.CustomerID
JOIN [dbo].[Order Details] od 
on o.OrderID = od.OrderID
JOIN [dbo].[Products] p
ON p.ProductID=od.ProductID
WHERE C.Country = 'UK'
ORDER BY CompanyName, OrderDate

--extension
SELECT c.CustomerID, CompanyName, ContactName,  OrderDate, od.ProductID, Quantity, p.ProductName
FROM Customers c JOIN Orders o 
on c.CustomerID = o.CustomerID
JOIN [dbo].[Order Details] od 
on o.OrderID = od.OrderID
JOIN [dbo].[Products] p
ON p.ProductID=od.ProductID
JOIN  Categories ca 
ON ca.[CategoryID] = p.CategoryID
WHERE C.Country = 'UK' AND CategoryName='Seafood'
ORDER BY CompanyName, OrderDate

--Exercise 2 Task 1:
USE Northwind

SELECT COUNT(*) FROM dbo.Customers

--Exercise 2 Task 2:

SELECT   c.CompanyName, COUNT(o.OrderID) AS NumOrders
FROM	    Customers AS c
JOIN	    Orders AS o
ON	    o.CustomerID = c.CustomerID
GROUP BY c.CompanyName
ORDER BY NumOrders

--Exercise 2 Task 3:

SELECT
	c.CompanyName, COUNT(o.OrderID) AS NumOrders,
	MIN(o.OrderDate) AS MinDate
FROM
	Orders AS o
RIGHT OUTER JOIN
	Customers AS c
ON
	o.CustomerID = c.CustomerID
GROUP BY
	c.CompanyName
ORDER BY
	NumOrders

	

