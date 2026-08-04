# SQL Server — Reference Implementation

How to stand up the original system. This tree is the **golden source** and is
preserved byte for byte; see [`sqlserver/README.md`](../sqlserver/README.md) for
the change policy.

> **Do not modify anything under `sqlserver/`.** Quirks are preserved
> deliberately — the port documents them rather than silently correcting them.
> The pre-restructure state is tagged `archive/ms-sql-reference`.

## Prerequisites

- SQL Server 2016 or later (Developer, Express and Azure SQL Edge all work)
- SQL Server Management Studio, Azure Data Studio, or `sqlcmd`

## The four databases

These are **separate, independent** databases, not one system.

| Database | Script | Creates | Contents |
|---|---|---|---|
| **Northwind** | [`database/northwind/northwind.sql`](../sqlserver/database/northwind/northwind.sql) | Yes — drops and recreates | 13 tables, 16 views, 7 procedures, ~30 indexes, full data |
| **QATSQLPLUS** | [`database/qatsqlplus/qatsqlplus_setup.sql`](../sqlserver/database/qatsqlplus/qatsqlplus_setup.sql) | Yes — drops and recreates | 8 tables, 2 views, 1 procedure, 2 commented-out UDFs |
| **QAStore** | [`database/qastore/create_qastore.sql`](../sqlserver/database/qastore/create_qastore.sql) | Yes — drops and recreates | 5 tables, composite PK and composite FK |
| **REVENUE** | [`database/revenue/create_revenue.sql`](../sqlserver/database/revenue/create_revenue.sql) | **No** — table only | One table, 45 rows, 1998–2012 |

Only **Northwind** has enough transactional depth to model dimensionally, and it
is the source system for the PostgreSQL warehouse. The other three are reference
material for the exercises and for dialect-coverage porting examples.

## Setup

### Northwind

```bash
sqlcmd -S localhost -E -i "sqlserver/database/northwind/northwind.sql"
```

The script `USE master`, drops any existing `Northwind` database, and recreates
it — deriving the data file path from `master.mdf`'s location, so no path
configuration is needed.

### QATSQLPLUS

```bash
sqlcmd -S localhost -E -i "sqlserver/database/qatsqlplus/qatsqlplus_setup.sql"
```

### QAStore — note the encoding

This file was exported by SSMS as **UTF-16LE**, not UTF-8. `sqlcmd` needs to be
told, or it will read mojibake:

```bash
sqlcmd -S localhost -E -f 1200 -i "sqlserver/database/qastore/create_qastore.sql"
```

SSMS and Azure Data Studio detect the BOM and need no flag. The file is marked
`binary` in `.gitattributes` so Git cannot mangle its BOM or line endings.

### REVENUE

This script creates a **table only** — no database. Run it inside whichever
database you want it in:

```sql
USE Northwind;   -- or any database of your choosing
GO
:r sqlserver/database/revenue/create_revenue.sql
```

## Running the exercises

Run against **Northwind** unless a script says otherwise.

| Directory | Contents |
|---|---|
| [`exercises/day1-setup/`](../sqlserver/exercises/day1-setup/) | Day 1 starter scripts |
| [`exercises/day2-day4/`](../sqlserver/exercises/day2-day4/) | Day 2–4 exercises, in filename order |
| [`exercises/demos/`](../sqlserver/exercises/demos/) | Instructor demonstrations |
| [`exercises/data/`](../sqlserver/exercises/data/) | CSVs for the join exercises |
| [`exercises/normalisation/`](../sqlserver/exercises/normalisation/) | Day 1 normalisation workbooks (Excel) |
| [`queries/`](../sqlserver/queries/) | Author-written analysis queries |
| [`views/`](../sqlserver/views/) | Author-written view definitions |

Original filenames are unchanged throughout, so the learning progression stays
legible and `git log --follow` works on every file.

### The ClientOrders demo

[`queries/SQLQuery Joins.sql`](../sqlserver/queries/SQLQuery%20Joins.sql) begins
`CREATE DATABASE ClientOrders` but does **not** create or populate its tables —
they are loaded by hand from
[`exercises/data/Clients.csv`](../sqlserver/exercises/data/Clients.csv) and
`Orders.csv` (via the SSMS Import Wizard). Expect the `SELECT`s to fail until you
do that. Preserved as-is.

Note `Orders.csv` has a header column literally named `client_id*` — the asterisk
is in the source file.

## Things that will surprise you

These are all in the original and are **preserved deliberately**. The full
catalogue is in [`migration-guide.md`](migration-guide.md#6-findings-in-the-source-implementation).

| Where | What |
|---|---|
| `northwind.sql` | Encoded **cp1252**, not UTF-8 — 657 non-ASCII bytes in customer and supplier addresses |
| `create_qastore.sql` | Encoded **UTF-16LE** |
| Northwind indexes | **Eight pairs of duplicates** (`CustomerID` and `CustomersOrders` both on `Orders(CustomerID)`, etc.) |
| `Day 4 03 ... Revision.sql` Step 10 | Uses `TOP 2` where the question asks for the single highest |
| `Day 4 03 ... Revision.sql` Step 11 | Asks for customers with *no* dealings with two employees, but implements `NOT IN` inside a join — which returns customers who dealt with *someone else too* |
| `Managers` view | Self-join aliases read backwards: `m` holds the subordinate |
| `Current Product List` | Compares a `bit` column to the string `'N'` |
| `Order Subtotals` | `/100 ... *100` to force `money` through a rounding step |

## What is not here

**No SSIS packages.** No `.dtsx`, `.dtproj` or `.ispac` file exists in this
repository or anywhere in its Git history. Loading was done by executing T-SQL
directly. No empty `ssis/` folder was created to imply otherwise.

**No author-written stored procedures.** The only procedures present are
Microsoft's, inside `northwind.sql`, and `ResetBookStock` in the QATSQLPLUS
setup script.

## Verifying the source

Confirm the golden source is unmodified:

```bash
git diff archive/ms-sql-reference HEAD --stat -- sqlserver/
```

Files moved during the restructure, so paths differ — but every original blob is
byte-identical. 59 of 60 original blobs are preserved; the single exception is
`.gitattributes`, which was extended deliberately.

## Next

- [`postgres.md`](postgres.md) — build and run the ported warehouse
- [`migration-guide.md`](migration-guide.md) — what changed, and why
