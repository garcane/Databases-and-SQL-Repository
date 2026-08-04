-- 1: Write a query that selects a count of rows

SELECT * FROM Orders
SELECT COUNT(*) AS NumberOfOrders FROM Orders


---Task 2: Write a query that selects maximums and minimums
SELECT * FROM Orders
SELECT COUNT(*) AS NumberOfOrders FROM Orders
SELECT MIN(OrderDate) AS EarliestOrder FROM Orders
SELECT MAX(OrderDate) AS LastestOrder FROM Orders

--Task 3: Write a query that selects aggregates for only one employee
SELECT * FROM Orders
SELECT COUNT(*) AS NumberOfOrders FROM Orders
SELECT MIN(OrderDate) AS EarliestOrder FROM Orders
SELECT MAX(OrderDate) AS LastestOrder FROM Orders
WHERE EmployeeID = 1