-- Task 1: Query for non-discontinued products
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

-- Verify row count (should return 69)
-- SELECT COUNT(*) FROM Products WHERE Discontinued = 0;

-- Task 2: Sort non-discontinued products by CategoryID
SELECT 
    ProductID, 
    ProductName, 
    CategoryID, 
    Discontinued, 
    UnitPrice
FROM 
    Products
WHERE 
    Discontinued = 0
ORDER BY 
    CategoryID;

-- Verify results:
-- Should return 69 rows grouped by CategoryID (1-8)
-- Products with same CategoryID appear together

-- Task 3: Sort by CategoryID then by UnitPrice (descending)
SELECT 
    ProductID, 
    ProductName, 
    CategoryID, 
    Discontinued, 
    UnitPrice
FROM 
    Products
WHERE 
    Discontinued = 0
ORDER BY 
    CategoryID,
    UnitPrice DESC;

-- Verify results:
-- Still 69 rows
-- Grouped by CategoryID (1-8)
-- Within each category, most expensive products appear first