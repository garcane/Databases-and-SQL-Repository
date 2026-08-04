--Task 1: Create a query that counts customers
SELECT * FROM Orders
SELECT COUNT(OrderID) AS NumberOfOrders FROM Orders


---Task 2: Grouping Orders by Customer Name
SELECT c.CompanyName, COUNT(o.OrderID) AS NumOrders
FROM Customers AS c
INNER JOIN Orders AS o ON c.CustomerID = o.CustomerID
GROUP BY c.CompanyName
ORDER BY NumOrders;


---Task 3: Outer Joins with Additional Features
-- Left outer join (all customers, even those without orders)
SELECT c.CompanyName, COUNT(o.OrderID) AS NumOrders
FROM Customers AS c
LEFT OUTER JOIN Orders AS o ON c.CustomerID = o.CustomerID
GROUP BY c.CompanyName
ORDER BY NumOrders;


--Step 3.5: Right Outer Join returning 91 rows
-- Right outer join returning 91 rows (tables swapped)
SELECT c.CompanyName, COUNT(o.OrderID) AS NumOrders
FROM Orders AS o
RIGHT OUTER JOIN Customers AS c ON o.CustomerID = c.CustomerID
GROUP BY c.CompanyName
ORDER BY NumOrders;



---Step 3.6-3.7: Adding MIN OrderDate with NULL handling
-- Final query with MIN OrderDate and NULL handling
SELECT 
    c.CompanyName, 
    COUNT(o.OrderID) AS NumOrders,
    CASE 
        WHEN MIN(o.OrderDate) IS NULL THEN 'No orders'
        ELSE CONVERT(VARCHAR, MIN(o.OrderDate), 120)
    END AS MinDate
FROM Customers AS c
LEFT OUTER JOIN Orders AS o ON c.CustomerID = o.CustomerID
GROUP BY c.CompanyName
ORDER BY NumOrders;



