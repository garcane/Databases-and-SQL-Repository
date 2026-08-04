use Northwind

SELECT CategoryID, COUNT(*) as NbRec
FROM Products
GROUP BY CategoryID
order by CategoryID

SELECT CategoryID, SUM(UnitsInStock) as InStock
FROM Products
GROUP BY CategoryID
order by CategoryID
--round avg price 2 dec pla.
SELECT CategoryID, round(AVG(UnitPrice),2) as AvgUnitPrice
FROM Products
GROUP BY CategoryID
order by CategoryID

SELECT CategoryID, MAX(UnitPrice) as MaxUnitPrice
FROM Products
GROUP BY CategoryID
order by CategoryID

--STDEV and STDEVP
SELECT CategoryID, round(STDEV(UnitPrice),2) as StdevPrice,
AVG(UnitPrice) as AVGUNITPRICE
FROM Products
GROUP BY CategoryID

SELECT CategoryID, round(AVG(UnitPrice),2) as AVGUNITPRICE
FROM Products
WHERE CategoryID >3 AND UnitPrice < 30
GROUP BY CategoryID
--HAVING AVG(UnitPrice) < 30
ORDER by CategoryID
