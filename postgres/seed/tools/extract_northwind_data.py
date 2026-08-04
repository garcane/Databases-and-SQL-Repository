#!/usr/bin/env python3
"""
Extract Northwind data from the SQL Server reference script into CSV files.

The reference implementation at
sqlserver/database/northwind/northwind.sql is the golden source: it is READ
here and never written. This script converts its INSERT statements into CSVs
that PostgreSQL's COPY can load, which is dramatically faster than replaying
3,000 single-row INSERTs and keeps the port free of hand-transcribed data.

    python postgres/seed/tools/extract_northwind_data.py

Writes CSVs to postgres/seed/data/ and prints a row count per table.

Three statement forms appear in the source and all are handled:

    INSERT "Categories"("CategoryID",...) VALUES(1,'Beverages',...)
    INSERT [dbo].[Region] ([RegionID],...) VALUES (1, N'Eastern')
    Insert Into Region Values (1,'Eastern')

Columns holding embedded bitmaps (Categories.Picture, Employees.Photo) are
dropped. They are OLE-wrapped Windows bitmaps averaging ~40 KB per row, they
have no analytical value, and carrying them would inflate the repository by
several megabytes to no purpose. Every other column is preserved exactly.
"""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SOURCE = REPO_ROOT / "sqlserver" / "database" / "northwind" / "northwind.sql"
OUT_DIR = REPO_ROOT / "postgres" / "seed" / "data"

# Target table -> ordered staging columns, matching postgres/database/10_staging.sql.
# Keys are the lowercased, space-stripped source table name.
TABLES: dict[str, tuple[str, list[str]]] = {
    "categories": ("categories", ["category_id", "category_name", "description"]),
    "customers": ("customers", [
        "customer_id", "company_name", "contact_name", "contact_title", "address",
        "city", "region", "postal_code", "country", "phone", "fax"]),
    "employees": ("employees", [
        "employee_id", "last_name", "first_name", "title", "title_of_courtesy",
        "birth_date", "hire_date", "address", "city", "region", "postal_code",
        "country", "home_phone", "extension", "notes", "reports_to", "photo_path"]),
    "shippers": ("shippers", ["shipper_id", "company_name", "phone"]),
    "suppliers": ("suppliers", [
        "supplier_id", "company_name", "contact_name", "contact_title", "address",
        "city", "region", "postal_code", "country", "phone", "fax", "home_page"]),
    "products": ("products", [
        "product_id", "product_name", "supplier_id", "category_id",
        "quantity_per_unit", "unit_price", "units_in_stock", "units_on_order",
        "reorder_level", "discontinued"]),
    "orders": ("orders", [
        "order_id", "customer_id", "employee_id", "order_date", "required_date",
        "shipped_date", "ship_via", "freight", "ship_name", "ship_address",
        "ship_city", "ship_region", "ship_postal_code", "ship_country"]),
    "orderdetails": ("order_details", [
        "order_id", "product_id", "unit_price", "quantity", "discount"]),
    "region": ("region", ["region_id", "region_description"]),
    "territories": ("territories", [
        "territory_id", "territory_description", "region_id"]),
    "employeeterritories": ("employee_territories", ["employee_id", "territory_id"]),
}

# Source columns dropped on extraction (embedded bitmaps).
DROPPED_COLUMNS = {"picture", "photo"}

# Column lists for the statements that omit them, e.g.
#   INSERT "Customers" VALUES('ALFKI', ...)
# Order is the source CREATE TABLE order and must not be rearranged.
POSITIONAL_COLUMNS: dict[str, list[str]] = {
    "customers": [
        "customerid", "companyname", "contactname", "contacttitle", "address",
        "city", "region", "postalcode", "country", "phone", "fax"],
    "orders": [
        "orderid", "customerid", "employeeid", "orderdate", "requireddate",
        "shippeddate", "shipvia", "freight", "shipname", "shipaddress",
        "shipcity", "shipregion", "shippostalcode", "shipcountry"],
    "orderdetails": ["orderid", "productid", "unitprice", "quantity", "discount"],
    "region": ["regionid", "regiondescription"],
    "territories": ["territoryid", "territorydescription", "regionid"],
    "employeeterritories": ["employeeid", "territoryid"],
}

# The source is a Windows SSMS export: single-byte cp1252, not UTF-8. Decoding
# it as UTF-8 fails outright on 0xF3 ("Constitución"), and decoding with
# errors="replace" would silently corrupt 657 bytes across the customer and
# supplier addresses - names like "México D.F." and "Mataderos 2312".
SOURCE_ENCODING = "cp1252"

INSERT_RE = re.compile(
    r"""^\s*INSERT \s+ (?:INTO\s+)?          # INSERT [INTO]
        (?P<table> "[^"]+" | \[[^\]]+\] (?:\.\[[^\]]+\])? | \w+ )
        \s*
        (?P<cols> \( [^)]*? \) )? \s*        # optional column list
        VALUES \s* \(                        # VALUES (
    """,
    re.IGNORECASE | re.VERBOSE | re.MULTILINE,
)


def normalise_name(raw: str) -> str:
    """`[dbo].[Order Details]` / `"Order Details"` -> `orderdetails`."""
    name = raw.strip()
    if "." in name and name.startswith("["):
        name = name.split(".")[-1]
    return name.strip('"[]').replace(" ", "").replace("_", "").lower()


def split_values(text: str, start: int) -> tuple[list[tuple[str, bool]], int]:
    """
    Split one VALUES tuple into (literal, was_quoted) pairs, honouring T-SQL
    quoting. `start` indexes the character after the opening parenthesis.

    A naive str.split(',') corrupts any row containing a comma inside a string -
    which in this data means most addresses and every product name like
    'Sir Rodney''s Marmalade'. Doubled single quotes are the T-SQL escape and
    are collapsed to one here.

    was_quoted is tracked in the same pass rather than by re-scanning, so that
    the four-character string 'NULL' can never be mistaken for SQL NULL.
    """
    values: list[tuple[str, bool]] = []
    buf: list[str] = []
    quoted = False
    i, n = start, len(text)
    in_string = False

    while i < n:
        ch = text[i]
        if in_string:
            if ch == "'":
                if i + 1 < n and text[i + 1] == "'":   # '' -> escaped quote
                    buf.append("'")
                    i += 2
                    continue
                in_string = False
                i += 1
                continue
            buf.append(ch)
        else:
            if ch == "'":
                # T-SQL national-character literals are written N'...'. The N is
                # a type prefix, not data: without this, N'VINET' extracts as
                # the six-character string "NVINET" and overflows char(5) on
                # load. Only a bare N immediately before the quote qualifies -
                # a genuine value cannot reach here as unquoted text.
                if "".join(buf).strip().upper() == "N":
                    buf = []
                in_string = True
                quoted = True
                i += 1
                continue
            if ch == ",":
                values.append(("".join(buf).strip(), quoted))
                buf, quoted = [], False
                i += 1
                continue
            if ch == ")":
                values.append(("".join(buf).strip(), quoted))
                return values, i + 1
            buf.append(ch)
        i += 1

    raise ValueError("unterminated VALUES tuple")


def clean(value: str, was_quoted: bool) -> str | None:
    """Convert one raw literal to its CSV representation. None means SQL NULL."""
    v = value.strip()
    if not was_quoted and v.upper() == "NULL":
        return None
    if not was_quoted and v.lower().startswith("0x"):   # binary blob
        return None
    return v


def parse(text: str) -> dict[str, list[list[str | None]]]:
    rows: dict[str, list[list[str | None]]] = {key: [] for key in TABLES}
    skipped: dict[str, int] = {}

    for match in INSERT_RE.finditer(text):
        table = normalise_name(match.group("table"))
        if table not in TABLES:
            skipped[table] = skipped.get(table, 0) + 1
            continue

        raw_cols = match.group("cols")
        if raw_cols:
            source_cols = [
                c.strip().strip('"[] ').lower()
                for c in raw_cols.strip("()").split(",")
            ]
        else:
            source_cols = POSITIONAL_COLUMNS.get(table)
            if source_cols is None:
                raise ValueError(f"{table}: VALUES without a column list")

        literals, _ = split_values(text, match.end())

        if len(literals) != len(source_cols):
            raise ValueError(
                f"{table}: {len(literals)} values for {len(source_cols)} columns"
            )

        record = {
            col: clean(lit, was_quoted)
            for col, (lit, was_quoted) in zip(source_cols, literals)
            if col not in DROPPED_COLUMNS
        }

        _, target_cols = TABLES[table]
        # Map staging snake_case back onto the source's squashed column names.
        rows[table].append([
            record.get(tc.replace("_", ""), record.get(tc))
            for tc in target_cols
        ])

    if skipped:
        other = ", ".join(f"{k}({v})" for k, v in sorted(skipped.items()))
        print(f"  ignored INSERTs into non-staging tables: {other}", file=sys.stderr)

    return rows


def main() -> int:
    if not SOURCE.exists():
        print(f"ERROR: source not found: {SOURCE}", file=sys.stderr)
        return 1

    text = SOURCE.read_text(encoding=SOURCE_ENCODING)
    print(f"Reading {SOURCE.relative_to(REPO_ROOT)} ({len(text):,} bytes)")

    rows = parse(text)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    total = 0
    for key, (target, columns) in TABLES.items():
        data = rows[key]
        path = OUT_DIR / f"{target}.csv"
        with path.open("w", newline="", encoding="utf-8") as fh:
            writer = csv.writer(fh, quoting=csv.QUOTE_MINIMAL)
            writer.writerow(columns)
            for row in data:
                writer.writerow(["" if v is None else v for v in row])
        total += len(data)
        print(f"  {target:<22} {len(data):>5} rows -> {path.name}")

    print(f"\n{total:,} rows extracted to {OUT_DIR.relative_to(REPO_ROOT)}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
