---Task 1: UK Customer Orders (Basic Join)
-- UKCustomerOrders.sql
USE Northwind;

-- Initial query (Task 1.1-1.3)
SELECT c.CustomerID, c.CompanyName, c.ContactName, c.City
FROM Customers AS c;

-- Modified with join (Task 1.4-1.6)
SELECT c.CustomerID, c.CompanyName, c.ContactName, c.City, 
       o.OrderID, o.OrderDate
FROM Customers AS c
INNER JOIN Orders AS o ON c.CustomerID = o.CustomerID;


----Task 2: Filtering and Sorting UK Orders
SELECT c.CustomerID, c.CompanyName, c.ContactName, c.City,
       o.OrderID, o.OrderDate
FROM Customers AS c
INNER JOIN Orders AS o ON c.CustomerID = o.CustomerID
WHERE c.Country = 'UK'
ORDER BY c.CompanyName, o.OrderDate;


---Task 3: Extended Query with Order Details and Products
-- UKCustomerOrders.sql (Task 3.1-3.6)
SELECT c.CustomerID, c.CompanyName, c.ContactName,
       o.OrderID, o.OrderDate,
       od.ProductID, od.Quantity,
       p.ProductName
FROM Customers AS c
INNER JOIN Orders AS o ON c.CustomerID = o.CustomerID
INNER JOIN [Order Details] AS od ON o.OrderID = od.OrderID
INNER JOIN Products AS p ON od.ProductID = p.ProductID
WHERE c.Country = 'UK'
ORDER BY c.CompanyName, o.OrderDate;

--Extra Credit: Seafood Category Only
-- UKCustomerOrders.sql (Extra Credit)
SELECT c.CustomerID, c.CompanyName, c.ContactName,
       o.OrderID, o.OrderDate,
       od.ProductID, od.Quantity,
       p.ProductName,
       cat.CategoryName
FROM Customers AS c
INNER JOIN Orders AS o ON c.CustomerID = o.CustomerID
INNER JOIN [Order Details] AS od ON o.OrderID = od.OrderID
INNER JOIN Products AS p ON od.ProductID = p.ProductID
INNER JOIN Categories AS cat ON p.CategoryID = cat.CategoryID
WHERE c.Country = 'UK'
AND cat.CategoryName = 'Seafood'
ORDER BY c.CompanyName, o.OrderDate;