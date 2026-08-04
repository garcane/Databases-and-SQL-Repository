-- Task 1: Create a query that counts orders
SELECT * FROM Orders
SELECT COUNT(OrderID) AS NumberOfOrders FROM Orders


--Task 2: Write a query that groups orders based on the customer’s ID
SELECT * FROM Orders
SELECT COUNT(OrderID) AS NumberOfOrders,  CustomerID FROM Orders
GROUP BY CustomerID

--Task 3: Write a query that sorts order counts in descending order
SELECT COUNT(OrderID) AS NumberOfOrders, CustomerID 
FROM Orders
GROUP BY CustomerID
ORDER BY NumberOfOrders DESC