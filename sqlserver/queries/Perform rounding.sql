----Task 1: Create a query that outputs a calculated column
select * from dept

Select dept_no, sales_target * 1.638 AS new_target
from dept


---Task 2: Round the values in the calculated column to one decimal place

Select dept_no, ROUND(sales_target * 1.638,1) AS new_target 
from dept


---Task 3: Round the values in the calculated column to integer

Select dept_no, CAST(sales_target * 1.638 AS INT) AS new_target 
from dept

----Task 4: Cast the values in the calculated column as integer