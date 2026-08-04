--Use QAStore


SELECT fname, lname, sales_target, sales_target *1.2 as NewTarget
from salesperson
Where sales_target < 10

CREATE TABLE salesperson2 (
	fname varchar(50),
	lname varchar(50),
	sales_target DECIMAL(10,4)
	)
INSERT INTO salesperson2 (fname,lname,sales_target)
Values
	('Dick', 'Ernst', 11.000),
	('Frank', 'Shaw', 15.000),
	('George', 'Cassa', 13.000)

select * from salesperson2

select fname,lname,sales_target
from salesperson
union
select fname,lname,sales_target
from salesperson2

SELECT fname,lname, sales_target
from salesperson
INTERSECT
SELECT fname, lname, sales_target
from salesperson2

SELECT fname,lname, sales_target
from salesperson2
EXCEPT
SELECT fname, lname, sales_target
from salesperson

--Use Northwind

SELECT ProductID from Products
Where Discontinued=1
INTERSECT
SELECT DISTINCT od.ProductID
from [Order Details] od
Inner Join Orders o on od.OrderId= o.OrderID
Where o.OrderDate < '1997-01-01'



