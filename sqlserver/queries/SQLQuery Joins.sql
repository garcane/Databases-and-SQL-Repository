CREATE DATABASE ClientOrders

USE ClientOrders
GO

--- inner join
SELECT *  FROM Orders

SELECT * FROM Clients

SELECT * FROM Orders, Clients

SELECT * FROM Clients INNER JOIN Orders 
ON Clients.client_id=Orders.client_id




--- left join
SELECT *  FROM Orders

SELECT * FROM Clients

SELECT * FROM Clients c

Left JOIN Orders o
ON c.client_id=o.client_id



--- Right join
SELECT *  FROM Orders

SELECT * FROM Clients

SELECT * FROM Clients c

Right JOIN Orders o
ON c.client_id=o.client_id



--- Full join
SELECT *  FROM Orders

SELECT * FROM Clients

SELECT * FROM Clients c

Full JOIN Orders o
ON c.client_id=o.client_id



 
