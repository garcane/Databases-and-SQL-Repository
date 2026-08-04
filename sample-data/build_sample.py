#!/usr/bin/env python3
"""
Build a small, referentially complete demo subset of the Northwind extract.

    python sample-data/build_sample.py

Reads the full CSVs in postgres/seed/data/ and writes a subset to
sample-data/. The subset is chosen so that it is REFERENTIALLY COMPLETE: every
foreign key in the subset resolves inside the subset. A demo extract that
dangles is worse than no demo extract, because it fails in ways the real data
never would.

Selection rule: the 12 customers with the most orders in 1997, then everything
those orders touch, transitively.
"""

from __future__ import annotations

import csv
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FULL = ROOT / "postgres" / "seed" / "data"
OUT = Path(__file__).resolve().parent

CUSTOMER_LIMIT = 12
YEAR = "1997"


def read(name: str) -> list[dict]:
    with (FULL / f"{name}.csv").open(encoding="utf-8", newline="") as fh:
        return list(csv.DictReader(fh))


def write(name: str, rows: list[dict], columns: list[str]) -> None:
    with (OUT / f"{name}.csv").open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=columns)
        w.writeheader()
        w.writerows(rows)
    print(f"  {name:<22} {len(rows):>5} rows")


def main() -> int:
    customers = read("customers")
    orders = read("orders")
    order_details = read("order_details")
    products = read("products")
    categories = read("categories")
    suppliers = read("suppliers")
    employees = read("employees")
    shippers = read("shippers")

    # 1. Busiest customers of 1997.
    orders_1997 = [o for o in orders if (o["order_date"] or "").startswith(YEAR)]
    busiest = [c for c, _ in Counter(o["customer_id"] for o in orders_1997
                                     if o["customer_id"]).most_common(CUSTOMER_LIMIT)]
    keep_customers = set(busiest)

    # 2. Their 1997 orders, and 3. the lines on those orders.
    keep_orders = [o for o in orders_1997 if o["customer_id"] in keep_customers]
    keep_order_ids = {o["order_id"] for o in keep_orders}
    keep_lines = [d for d in order_details if d["order_id"] in keep_order_ids]

    # 4. Close over everything those rows reference, so no FK dangles.
    keep_product_ids = {d["product_id"] for d in keep_lines}
    keep_products = [p for p in products if p["product_id"] in keep_product_ids]

    keep_category_ids = {p["category_id"] for p in keep_products if p["category_id"]}
    keep_supplier_ids = {p["supplier_id"] for p in keep_products if p["supplier_id"]}
    keep_employee_ids = {o["employee_id"] for o in keep_orders if o["employee_id"]}
    keep_shipper_ids = {o["ship_via"] for o in keep_orders if o["ship_via"]}

    # Employees' managers must also be present, or the flattened hierarchy breaks.
    by_id = {e["employee_id"]: e for e in employees}
    pending = set(keep_employee_ids)
    while pending:
        eid = pending.pop()
        mgr = (by_id.get(eid) or {}).get("reports_to")
        if mgr and mgr not in keep_employee_ids:
            keep_employee_ids.add(mgr)
            pending.add(mgr)

    print(f"Curated subset: {len(busiest)} customers, {YEAR} orders only")
    write("customers",    [c for c in customers if c["customer_id"] in keep_customers], list(customers[0]))
    write("orders",       keep_orders,  list(orders[0]))
    write("order_details", keep_lines,  list(order_details[0]))
    write("products",     keep_products, list(products[0]))
    write("categories",   [c for c in categories if c["category_id"] in keep_category_ids], list(categories[0]))
    write("suppliers",    [s for s in suppliers if s["supplier_id"] in keep_supplier_ids], list(suppliers[0]))
    write("employees",    [e for e in employees if e["employee_id"] in keep_employee_ids], list(employees[0]))
    write("shippers",     [s for s in shippers if s["shipper_id"] in keep_shipper_ids], list(shippers[0]))

    # Verify referential completeness rather than assuming it.
    problems = []
    kept_orders = {o["order_id"] for o in keep_orders}
    for d in keep_lines:
        if d["order_id"] not in kept_orders:
            problems.append(f"order_details -> orders: {d['order_id']}")
        if d["product_id"] not in keep_product_ids:
            problems.append(f"order_details -> products: {d['product_id']}")
    for o in keep_orders:
        if o["customer_id"] and o["customer_id"] not in keep_customers:
            problems.append(f"orders -> customers: {o['customer_id']}")
        if o["employee_id"] and o["employee_id"] not in keep_employee_ids:
            problems.append(f"orders -> employees: {o['employee_id']}")

    if problems:
        print("\nFAILED referential completeness:")
        for p in sorted(set(problems))[:10]:
            print("  " + p)
        return 1

    # An empty subset satisfies "no dangling foreign keys" vacuously. Without
    # this guard the script reports success on zero rows - which is exactly what
    # it did on the first run, when the date filter silently matched nothing
    # because the source dates were still in M/D/YYYY form.
    if not keep_orders or not keep_lines or not keep_customers:
        print("\nFAILED: subset is empty - the selection rule matched nothing.")
        return 1

    print("\nReferential completeness: OK (no dangling foreign keys)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
