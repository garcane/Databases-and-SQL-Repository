--create DATABASE ClientOrders

use ClientOrders

SELECT order_id FROM Orders

SELECT * FROM Clients

SELECT * FROM
Orders,Clients

SELECT *
FROM Clients INNER JOIN Orders
ON Clients.client_id=Orders.client_id

SELECT *
FROM Clients c INNER JOIN Orders o
ON c.client_id=o.client_id

--left join
SELECT * FROM Clients
SELECT * FROM Orders

SELECT * FROM Clients c
Left Join Orders o
ON c.client_id=o.client_id

--right join
SELECT * FROM Clients
SELECT * FROM Orders
SELECT * FROM Clients c
right Join Orders o
ON c.client_id=o.client_id

-- full join
SELECT * FROM Clients
SELECT * FROM Orders

SELECT * FROM Clients c
full outer Join Orders o
ON c.client_id=o.client_id


--Use Northwind
Select * from Products

SELECT p.CategoryID, c.CategoryName, ProductID, ProductName, Discontinued
FROM Products p Inner Join Categories c
On p.CategoryID=c.CategoryID
Where Discontinued = 0


