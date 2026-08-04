--Task 2: Use a view

SELECT * FROM  Invoices
WHERE Country = 'UK'

SELECT ShipName, ShipAddress, CustomerID
FROM Invoices
WHERE Country != 'UK'