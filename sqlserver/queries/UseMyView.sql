-- Basic view query
SELECT * FROM ContactDirectory;

-- Ordered by CompanyName
SELECT * FROM ContactDirectory ORDER BY CompanyName;

-- Filter by contact type
SELECT * FROM ContactDirectory WHERE ContactType = 'Employee';