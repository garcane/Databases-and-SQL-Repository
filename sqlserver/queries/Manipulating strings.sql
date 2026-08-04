SELECT 
    emp_no,
 SUBSTRING(fname, 1, 1) + ' ' + lname AS name, UPPER(county) AS county FROM 
    salesperson
ORDER BY 
    emp_no;