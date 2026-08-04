--Ex 1 Task1
--USE Northwind

SELECT [CompanyName],[ContactName],[Phone]
FROM Customers

--Task 2
SELECT [CompanyName],[ContactName],[Phone]
FROM Suppliers

--Task 3 
SELECT Extension,
(FirstName +' '+ LastName) AS FullName
FROM Employees

--Task 4
SELECT [CompanyName],[ContactName],[Phone]
FROM Customers UNION
SELECT [CompanyName],[ContactName],[Phone]
FROM Suppliers

SELECT [CompanyName],[ContactName],[Phone]
FROM Customers UNION
SELECT [CompanyName],[ContactName],[Phone]
FROM Suppliers UNION
SELECT 'NorthWind Traders', Extension,
(FirstName+' '+LastName) AS FullName
FROM Employees

SELECT [CompanyName],[ContactName],[Phone]
FROM Customers UNION ALL
SELECT [CompanyName],[ContactName],[Phone]
FROM Suppliers UNION ALL
SELECT 'NorthWind Traders', Extension,
(FirstName+' '+LastName) AS FullName
FROM Employees

--USE QATSQLPLUS
--EX2 Task 1
SELECT [DelegateID]
FROM DelegateAttendance da 
Join CourseRun cr on da.CourseRunID=cr.CourseRunID
Join Course c on cr.CourseID = c.CourseID
Where c.CourseName = 'QATSQL'


--Task2
SELECT [DelegateID]
FROM DelegateAttendance da 
	Inner Join CourseRun cr on da.CourseRunID=cr.CourseRunID
	Inner Join Course c on cr.CourseID = c.CourseID
Where c.CourseName = 'QATSQLPLUS'

--Task3
SELECT [DelegateID]
FROM DelegateAttendance da 
Join CourseRun cr on da.CourseRunID=cr.CourseRunID
Join Course c on cr.CourseID = c.CourseID
Where c.CourseName = 'QATSQL'

INTERSECT

SELECT [DelegateID]
FROM DelegateAttendance da 
Join CourseRun cr on da.CourseRunID=cr.CourseRunID
Join Course c on cr.CourseID = c.CourseID
Where c.CourseName = 'QATSQLPLUS'

--EX3. Task1
SELECT [DelegateID]
FROM DelegateAttendance da 
Join CourseRun cr on da.CourseRunID=cr.CourseRunID
Join Course c on cr.CourseID = c.CourseID
Where c.CourseName = 'QATSQL'

EXCEPT

SELECT [DelegateID]
FROM DelegateAttendance da 
Join CourseRun cr on da.CourseRunID=cr.CourseRunID
Join Course c on cr.CourseID = c.CourseID
Where c.CourseName = 'QATSQLPLUS'

--NOT QATSQL....order of queries important
SELECT [DelegateID]
FROM DelegateAttendance da 
Join CourseRun cr on da.CourseRunID=cr.CourseRunID
Join Course c on cr.CourseID = c.CourseID
Where c.CourseName = 'QATSQLPLUS'

EXCEPT

SELECT [DelegateID]
FROM DelegateAttendance da 
Join CourseRun cr on da.CourseRunID=cr.CourseRunID
Join Course c on cr.CourseID = c.CourseID
Where c.CourseName = 'QATSQL'


