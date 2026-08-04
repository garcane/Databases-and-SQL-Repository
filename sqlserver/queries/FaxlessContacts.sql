 SELECT TOP 10 CustomerID, CompanyName, ContactName, ContactTitle, Phone,  Fax
from Customers
where Fax IS NULL 
--WHERE ContactTitle LIKE 'a%sales%'