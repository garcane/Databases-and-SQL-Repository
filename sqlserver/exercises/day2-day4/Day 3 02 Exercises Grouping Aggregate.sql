Use Northwind

--EX1 Task1
Select COUNT(*) AS NumberOfOrders
FROM [dbo].[Orders]

--Task 2
Select COUNT(*) AS NumberOfOrders,
Min([OrderDate]) AS EarliestOrder,
MAX([OrderDate]) AS LatestOrder
FROM [dbo].[Orders]

Select COUNT(*) AS NumberOfOrders,
Min(Cast([OrderDate] AS Date)) AS EarliestOrder,
MAX(Cast([OrderDate] AS Date)) AS LatestOrder
FROM [dbo].[Orders]

--Task 3
Select COUNT(*) AS NumberOfOrders,
Min(Cast([OrderDate] AS Date)) AS EarlistOrder,
MAX(Cast([OrderDate] AS Date)) AS LatestOrder
FROM [dbo].[Orders]
WHERE EmployeeID =1



--EX2 Task 1
Select COUNT(OrderID) AS NumberOfOrders
FROM [dbo].[Orders]

--Task 2
Select COUNT(OrderID) AS NumberOfOrders, CustomerID
FROM [dbo].[Orders]
GROUP BY CustomerID



--Task 3
Select COUNT(*) AS NumberOfOrders, CustomerID
FROM [dbo].[Orders]
GROUP BY CustomerID
ORDER BY NumberOfOrders DESC

--EX3 Task1
Select ProductID, SUM([Quantity]) AS TotalSold
from [Order Details]
Group By ProductID

--Task2
Select ProductID, SUM(Quantity * UnitPrice) AS TotalValue
from [Order Details]
Group By ProductID
Order by TotalValue DESC

--Task3
Select ProductID, SUM(Quantity * UnitPrice) AS TotalValue
from [Order Details]
Group By ProductID
HAVING  SUM(Quantity * UnitPrice)<=5000
Order by TotalValue DESC



