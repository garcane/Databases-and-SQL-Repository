--Use master
--Go
--DROP DATABASE IF EXISTS SalesDW
--GO
--CREATE DATABASE SalesDW
--Go


--USE SalesDW

-----create a table
--CREATE TABLE Product(
--PRODUCTid int,
--PRODUCTdesc VARCHAR(30) NOT NULL,
--CategoryID int NOT NULL,
--Price DECIMAL(5,2) NOT NULL,
--DateCreated DATE DEFAULT getdate() NOT NULL
--)

--DROP TABLE Product

----Create table with Primary Key

--CREATE TABLE Product(
--PRODUCTid int NOT NULL PRIMARY KEY,
--PRODUCTdesc VARCHAR(30) NOT NULL,
--CategoryID int NOT NULL,
--Price DECIMAL(5,2) NOT NULL,
--DateCreated DATE DEFAULT getdate() NOT NULL
--)

----Create table with Primary Key

--DROP TABLE Product

--CREATE TABLE Product(
--PRODUCTid int IDENTITY (1,1) NOT NULL PRIMARY KEY,
--PRODUCTdesc VARCHAR(30) NOT NULL,
--CategoryID int NOT NULL,
--Price DECIMAL(5,2) NOT NULL,
--DateCreated DATE DEFAULT getdate() NOT NULL
--)

SELECT * FROM Product



--INSERT INTO Product(PRODUCTdesc,CategoryID,Price)
--VALUES('Hamlet', 1, 9.99),('King Lear', 1, 8.99), ('Watership Down', 2, 10.99)


--DELETE FROM Product
--WHERE Price< 9

--UPDATE Product
--SET Price = 12.40

UPDATE Product
SET Price = 12.99
WHERE CategoryID = 5


