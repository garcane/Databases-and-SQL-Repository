USE QAStore
GO

SELECT * FROM  sale

SELECT order_no, DATEPART(YEAR,order_date) AS order_year,
order_no, DATEPART(month,order_date) AS order_month,
order_no, DATEPART(DAY,order_date) AS order_day
from sale