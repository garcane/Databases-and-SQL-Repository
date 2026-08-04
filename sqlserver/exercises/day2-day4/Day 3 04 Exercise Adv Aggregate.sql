USE QATSQLPLUS
--EX1 Task1
SELECT VendorName,CourseName,StartDate,NumberDelegates
FROM  [dbo].[VendorCourseDateDelegateCount]

SELECT VendorName,CourseName,StartDate,
SUM(NumberDelegates) AS TotalDelegates
FROM  [dbo].[VendorCourseDateDelegateCount]
GROUP BY VendorName, CourseName, StartDate

SELECT VendorName,CourseName,StartDate,
SUM(NumberDelegates) AS TotalDelegates
FROM  [dbo].[VendorCourseDateDelegateCount]
GROUP BY VendorName, CourseName, StartDate
WITH ROLLUP 

SELECT VendorName,CourseName,StartDate,
SUM(NumberDelegates) AS TotalDelegates
FROM  [dbo].[VendorCourseDateDelegateCount]
GROUP BY VendorName, CourseName, StartDate
WITH CUBE 

SELECT VendorName,CourseName,
SUM(NumberDelegates) AS TotalDelegates
FROM  [dbo].[VendorCourseDateDelegateCount]
GROUP BY VendorName, CourseName
WITH CUBE 

--Task 2a:
SELECT Vendorname, CourseName, StartDate, NumberDelegates
	FROM VendorCourseDateDelegateCount

--Task 2b:
SELECT Vendorname, CourseName, StartDate, 
		SUM(NumberDelegates) AS TotalDelegates
	FROM VendorCourseDateDelegateCount
	GROUP BY GROUPING SETS (
		(VendorName),
		(Vendorname, CourseName, StartDate)
	)

