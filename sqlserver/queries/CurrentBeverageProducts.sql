-- Task 2: Basic query to display product information
SELECT 
    ProductID, 
    ProductName, 
    CategoryID, 
    Discontinued, 
    UnitPrice
FROM 
    Products;

-- This should return 77 rows (Task 3)

-- Task 4: Adding WHERE clause for non-discontinued products
SELECT 
    ProductID, 
    ProductName, 
    CategoryID, 
    Discontinued, 
    UnitPrice
FROM 
    Products
WHERE 
    Discontinued = 0;