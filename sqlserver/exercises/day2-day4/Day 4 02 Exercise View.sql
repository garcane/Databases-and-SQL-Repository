USE Northwind;

SELECT
	o.ShipName, 
	o.ShipAddress, 
	o.ShipCity, 
	o.ShipRegion, 
	o.ShipPostalCode, 
	o.ShipCountry, 
	o.CustomerID, 
	c.CompanyName AS CustomerName, 
	c.Address, 
	c.City,
	c.Region, 
	c.PostalCode, 
	c.Country, 
	e.FirstName + ' ' + e.LastName AS Salesperson,
	o.OrderID, 
	o.OrderDate, 
	o.RequiredDate, 
	o.ShippedDate,
	s.CompanyName AS ShipperName,
	od.ProductID, 
	p.ProductName, 
	od.UnitPrice, 
	od.Quantity, 
	od.Discount, 
	((od.UnitPrice * od.Quantity) * (1 - od.Discount) / 100) * 100 AS ExtendedPrice,
    o.Freight
FROM
	Orders AS o
INNER JOIN
	Customers AS c
ON
	c.CustomerID = o.CustomerID
	
INNER JOIN
	Employees AS e 
ON
	e.EmployeeID = o.EmployeeID
INNER JOIN
	Shippers AS s
ON 
	s.ShipperID = o.ShipVia
INNER JOIN
	[Order Details] AS od
ON
	o.OrderID = od.OrderID
INNER JOIN
	Products AS p
ON
	p.ProductID = od.ProductID


--USE Northwind;
--Ex1 Task 1
SELECT
	o.ShipName, 
	o.ShipAddress, 
	o.ShipCity, 
	o.ShipRegion, 
	o.ShipPostalCode, 
	o.ShipCountry, 
	o.CustomerID, 
	c.CompanyName AS CustomerName, 
	c.Address, 
	c.City,
	c.Region, 
	c.PostalCode, 
	c.Country, 
	e.FirstName + ' ' + e.LastName AS Salesperson,
	o.OrderID, 
	o.OrderDate, 
	o.RequiredDate, 
	o.ShippedDate,
	s.CompanyName AS ShipperName,
	od.ProductID, 
	p.ProductName, 
	od.UnitPrice, 
	od.Quantity, 
	od.Discount, 
	((od.UnitPrice * od.Quantity) * (1 - od.Discount) / 100) * 100 AS ExtendedPrice,
    o.Freight
FROM
	Orders AS o
INNER JOIN
	Customers AS c
ON
	c.CustomerID = o.CustomerID
	
INNER JOIN
	Employees AS e 
ON
	e.EmployeeID = o.EmployeeID
INNER JOIN
	Shippers AS s
ON 
	s.ShipperID = o.ShipVia
INNER JOIN
	[Order Details] AS od
ON
	o.OrderID = od.OrderID
INNER JOIN
	Products AS p
ON
	p.ProductID = od.ProductID
WHERE c.Country = 'UK'

--Task 2

SELECT * 
FROM Invoices

SELECT * 
FROM Invoices
WHERE Country='UK'

--EX2 Task1
SELECT
	CompanyName,
	ContactName,
	Phone
FROM
	dbo.Customers
UNION ALL
SELECT
	CompanyName,
	ContactName,
	Phone
FROM
	dbo.Suppliers

UNION ALL

SELECT
	'Northwind Traders',
	FirstName + ' ' + LastName,
	Extension
FROM
	dbo.Employees

--Task 2
CREATE VIEW  NewContactDirectory AS
SELECT
	CompanyName,
	ContactName,
	Phone
FROM
	dbo.Customers

UNION ALL

SELECT
	CompanyName,
	ContactName,
	Phone
FROM
	dbo.Suppliers

UNION ALL

SELECT
	'Northwind Traders',
	FirstName + ' ' + LastName,
	Extension
FROM
	dbo.Employees


--Task 3
SELECT *
FROM NewContactDirectory
WHERE ContactName LIKE 'a%'

