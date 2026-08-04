CREATE TABLE Readers(
LibraryID INT identity (1,2) Not Null PRIMARY KEY,
PassportNo VARCHAR (14) UNIQUE NOT NULL ,
ForeName VARCHAR (30) NOT NULL,
SurName VARCHAR (30) NOT NULL,
Age INT CHECK (AGE >=18) NOT NULL ,
City VARCHAR (20) DEFAULT 'LONDON' NOT NULL
)

INSERT INTO Readers(PassportNo,ForeName,SurName,Age)
VALUES('1123e32117','Jim', 'Jason', 18),('6EID1346875','Frank','Sidebottom', 21);


SELECT * FROM Readers

Update Readers
SET Age = 35
Where Age<19

DELETE 
FROM Readers
WHERE LibraryID=9
