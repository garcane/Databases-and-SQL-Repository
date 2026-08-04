USE QAStore
GO

SELECT * FROM salesperson

select emp_no, fname, lname from salesperson

---------------

SELECT 
    emp_no,
 SUBSTRING(fname, 1, 1) + ' ' + lname AS name FROM 
    salesperson
ORDER BY 
    emp_no;