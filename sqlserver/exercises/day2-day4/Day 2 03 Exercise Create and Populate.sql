CREATE TABLE Readers(
LibraryID INT identity (1,2) Not Null PRIMARY KEY,
PassportNo VARCHAR (14) UNIQUE NOT NULL ,
ForeName VARCHAR (30) NOT NULL,
SurName VARCHAR (30) NOT NULL,
Age INT CHECK (AGE >=18) NOT NULL ,
City VARCHAR (20) DEFAULT 'LONDON' NOT NULL
)




--Drop table Readers



INSERT INTO Readers(PassportNo,ForeName,SurName,Age)
VALUES('1123d32117','Jim', 'Jason', 19),('6EID1246875','Frank','Sidebottom', 18);


INSERT INTO Readers(PassportNo,ForeName,SurName,Age,City)
VALUES('23d32117','Jim', 'Jason', 19,'Exeter'),('EID1246875','Frank','Sidebottom', 18,'Manchester');
SELECT * FROM Readers