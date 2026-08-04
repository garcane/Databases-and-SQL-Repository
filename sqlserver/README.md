# SQL Server — Reference Implementation (Golden Source)

This directory is the **preserved reference implementation**: the original Microsoft
SQL Server system and the learning exercises built against it. It is the source of
truth that the PostgreSQL port in [`/postgres`](../postgres) is validated against.

> **Change policy:** files in this tree are **not modified**. No reformatting, no
> renaming of objects, no "improvements" to the T-SQL. Where a script contains a
> quirk (UTF-16LE encoding, an unqualified `SELECT *`, a `TOP 2` where `TOP 1` was
> intended), that quirk is preserved deliberately — the port documents it rather
> than silently correcting it. The pre-restructure state is tagged
> `archive/ms-sql-reference`.

Only file **locations** changed during the restructure, via `git mv`, so per-file
history is intact. Original filenames are unchanged throughout `exercises/`,
`queries/` and `views/`.

## Layout

| Path | Contents |
|---|---|
| `database/northwind/` | Northwind OLTP build script — 13 tables, 16 views, 7 procedures, indexes and full data |
| `database/qatsqlplus/` | QATSQLPLUS training schema — 8 tables, 2 views, 1 procedure, seed data |
| `database/qastore/` | QAStore schema — 5 tables including a composite foreign key (UTF-16LE, treated as binary) |
| `database/revenue/` | Standalone `REVENUE` table used for `ROLLUP` / `CUBE` demonstrations |
| `exercises/day1-setup/` | Day 1 starter scripts |
| `exercises/day2-day4/` | Day 2–4 exercise scripts, original filenames |
| `exercises/demos/` | Instructor demonstration scripts |
| `exercises/data/` | CSV inputs for the join exercises (`Clients`, `Orders`, `DeptEmployees`) |
| `exercises/normalisation/` | Day 1 normalisation workbooks (Excel) |
| `queries/` | Author-written analysis queries against Northwind |
| `views/` | Author-written view definitions |
| `README-original.md` | The repository's original README, retained verbatim |

## Source databases

Four separate databases are defined here. Northwind is the only one with enough
transactional depth to model dimensionally, and is therefore the source system for
the warehouse built in `/postgres`.

| Database | Build script | Role in this project |
|---|---|---|
| Northwind | `database/northwind/northwind.sql` | **Source system** for the dimensional warehouse |
| QATSQLPLUS | `database/qatsqlplus/qatsqlplus_setup.sql` | Reference only — procedure/function porting examples |
| QAStore | `database/qastore/create_qastore.sql` | Reference only — composite-key porting example |
| REVENUE | `database/revenue/create_revenue.sql` | Reference only — aggregate/`ROLLUP` porting example |

## Not present

There are **no SSIS packages** in this repository or in its Git history — no
`.dtsx`, `.dtproj` or `.ispac` files exist. Loading was performed by executing
T-SQL scripts directly. Orchestration for the PostgreSQL target is covered in
[`docs/migration-guide.md`](../docs/migration-guide.md) rather than by porting an
SSIS package that never existed.

Likewise there are no author-written stored procedures; the only procedures in the
tree are those shipped inside the vendor Northwind script and `ResetBookStock` in
the QATSQLPLUS setup script.

## Running these scripts

See [`docs/sql-server.md`](../docs/sql-server.md).
