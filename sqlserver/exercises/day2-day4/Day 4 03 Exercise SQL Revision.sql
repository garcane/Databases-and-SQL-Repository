--Use Northwind

--Step 1
--List the OrderID, CustomerID and OrderDate of all Orders that were placed on or before 31
--December 1996 sorted in ascending order of OrderDate within CustomerID.

SELECT OrderID, CustomerID, OrderDate FROM Orders
WHERE OrderDate <= '1996-12-31'
ORDER BY CustomerID, OrderDate

--Step 2
--List the OrderID, CustomerID and OrderDate of all Orders that were placed between 
--16/06/1997 and 20/06/1997 sorted in ascending order OrderDate. 

SELECT OrderID, CustomerID, OrderDate FROM Orders
WHERE OrderDate BETWEEN '1997-06-16' AND '1997-06-20'
ORDER BY OrderDate

--Step 3
--List all the data for all Products where the the ReorderLevel is greater than 25 sorted in 
--descending order of UnitsInStock.

SELECT * FROM Products
WHERE ReorderLevel > 25
ORDER BY UnitsInStock DESC

--Step 4
--List the CompanyName, ContactName, Country, Region and Phone of Customers whose 
--Region is specified sorted in ascending order of Region within Country. 

SELECT CompanyName, ContactName, Country, Region, Phone 
FROM Customers
WHERE Region IS NOT NULL
ORDER BY Country, Region

--Step 5
--List the distinct Company Names of Customers who place their orders with employees whose 
--last names are either “Davolio” or “Fuller”. 
SELECT DISTINCT c.CompanyName
FROM Orders o 
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
	INNER JOIN Employees e ON o.EmployeeID = e.EmployeeID
WHERE e.LastName IN ('Davolio', 'Fuller')

--Step 6
--List the ProductName and UnitPrice of all Products with a CategoryID of 2 or 3 together with a 
--NewUnitPrice (rounded to 2 decimal places) calculated by adding 3% to the UnitPrice, sorted 
--in ascending order of ProductName. 
SELECT ProductName, UnitPrice, ROUND(UnitPrice*1.03,2) AS NewUnitPrice FROM Products
WHERE CategoryID IN (2,3)
ORDER BY ProductName

--Step 7
--Show the total value of all the products currently held in stock with no decimal places.
SELECT CAST(ROUND(SUM(UnitsInStock*UnitPrice),0) AS INT) AS TotalValue FROM Products

--Step 8 
--Show the total number of Customers. 
SELECT COUNT(*) FROM Customers

--Step 9
--List the CustomerID, CompanyName and the number of orders for each customer that has 
--more than 20 orders grouping by CustomerID and CompanyName.
SELECT o.CustomerID, c.CompanyName, COUNT(o.OrderID) AS NumOrders
FROM Orders o 
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
GROUP BY o.CustomerID, c.CompanyName
HAVING COUNT(o.OrderID) > 20

--Step 10 
--List the CustomerID, CompanyName and the number of orders for the Customer that has the 
--highest number of orders using appropriate grouping
SELECT TOP 2 o.CustomerID, c.CompanyName, COUNT(o.OrderID) AS NumOrders
FROM Orders o 
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
GROUP BY o.CustomerID, c.CompanyName
ORDER BY NumOrders DESC

--Step 11
--List the CustomerID and CompanyName for all customers who have had no dealings with 
--employees whose last names are either “Davolio” or “Fuller”. 
SELECT DISTINCT c.CompanyName
FROM Orders o 
INNER JOIN Customers c ON o.CustomerID = c.CustomerID
	INNER JOIN Employees e ON o.EmployeeID = e.EmployeeID
WHERE e.LastName NOT IN ('Davolio', 'Fuller')

--Step 12
--Add the following new customer:
--ALAVO, Al's Avocados, Alan Tracy, Owner, 34 Porridge Pot Alley, Chelmsford, Essex, CM3 
--2BZ, UK, 01926 401697, 01926 401698.
INSERT INTO Customers(CustomerID, CompanyName,  ContactName, ContactTitle, [Address],City,Region,PostalCode,	Country, Phone, Fax)
VALUES('ALAVO', 'Al''s Avocados', 'Alan Tracy', 'Owner', '34 Porridge Pot Alley', 'Chelmsford', 'Essex',	'CM3 2BZ', 'UK', '01926 401697', '01926 401698')

--Step 13
--Update all the unit prices for Products with an increase of 5%. 
UPDATE Products
SET UnitPrice = ROUND(UnitPrice*1.05,2)

--Step 14
--List all the data for Products sorted in ascending order of ProductID. 
SELECT * FROM Products
ORDER BY ProductID

--Step 15 
--a) Add the following Region: 5, Europe
INSERT INTO Region(RegionID,RegionDescription)
VALUES(5, 'Europe')
--b) Add the following Territories:09000, UK, 5  and  09001, France, 5
INSERT INTO Territories(TerritoryID,TerritoryDescription,RegionID)
VALUES('09000', 'UK', 5)
INSERT INTO Territories(TerritoryID,TerritoryDescription,RegionID)
VALUES('09001', 'France', 5)
--c) List all the territories in ascending order of TerritoryID
SELECT TerritoryID, TerritoryDescription 
FROM Territories
ORDER BY TerritoryID
--d) List all the regions in ascending order of RegionID.
SELECT RegionID, RegionDescription 
FROM Region
ORDER BY RegionID
--e) Imagine that some time has passed and the region with an ID of 5 and all its 
--associated territories needs to be removed from the database. Delete the 
--appropriate records.
DELETE FROM Territories
WHERE RegionID = 5
DELETE FROM Region
WHERE RegionID = 5
--f) List all the territories in ascending order of TerritoryID.
SELECT TerritoryID, TerritoryDescription 
FROM Territories
ORDER BY TerritoryID
--g) List all the regions in ascending order of RegionID.:
SELECT RegionID, RegionDescription FROM Region
ORDER BY RegionID

--Step 16 
--Produce a list of Products showing Percentage Raises, ProductID and old and new UnitPrices. 
--Products with a CategoryID of 1, 3 or 5 are given a 5% rise, Products with a CategoryID of 2, 4 
--or 6 are given a 10% rise and other Products should not be given a rise. Display the results in 
--ascending PercentageRaise sequence and display the new UnitPrices with 2 decimal places. 
SELECT CategoryID, ProductID, UnitPrice as OldUnitPrice, 
	
CASE
	WHEN CategoryID IN (1,3,5) THEN 5
	WHEN CategoryID IN (2,4,6) THEN 10
	ELSE 0
END AS PercentageRaise,
	
CASE
	WHEN CategoryID IN (1,3,5) THEN ROUND(UnitPrice*1.05,2)
WHEN CategoryID IN (2,4,6) THEN ROUND(UnitPrice*1.1,2)
	ELSE UnitPrice
END AS NewUnitPrice

FROM Products
ORDER BY PercentageRaise
--Step 17
--Create a new view for all employees who are managers only using all the fields from the 
--employee table. Include the EmployeeID, LastName, FirstName, Title, TitleOfCourtesy, 
--HomePhone, Extension and ReportsTo columns. Apply a CHECK constraint. 
CREATE VIEW Managers AS
SELECT DISTINCT e.EmployeeID, e.LastName, e.FirstName, e.Title, e.TitleOfCourtesy, e.HomePhone, e.Extension, e.ReportsTo 
FROM Employees m JOIN Employees e ON m.ReportsTo = e.EmployeeID
WITH CHECK OPTION

--Step 18 
--Using the view for managers show all the fields for the manager(s) who don’t report to anyone 
--sorted in ascending order of EmployeeID.
SELECT * FROM Managers
WHERE ReportsTo IS NULL
ORDER BY EmployeeID
