SELECT
    ProductID, 
    ProductName, 
    UnitPrice, 
    UnitsInStock, 
    UnitsOnOrder,
    UnitPrice * UnitsInStock AS CurrentStockValue,
    (UnitsInStock + UnitsOnOrder) * UnitPrice AS FutureStockValue
FROM
    Products
ORDER BY
    FutureStockValue DESC;