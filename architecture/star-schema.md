# Star Schema — Dimensional Model

Rendered by GitHub natively. Source of truth for these objects is
[`postgres/database/20_dimensions.sql`](../postgres/database/20_dimensions.sql)
and [`postgres/database/30_facts.sql`](../postgres/database/30_facts.sql).

## Sales star — transaction grain

**Grain: one row per product per order.** Owns every revenue measure.

```mermaid
erDiagram
    dim_date ||--o{ fact_sales_order_line : "order_date_key"
    dim_date ||--o{ fact_sales_order_line : "required_date_key"
    dim_date ||--o{ fact_sales_order_line : "shipped_date_key"
    dim_customer ||--o{ fact_sales_order_line : "customer_key"
    dim_employee ||--o{ fact_sales_order_line : "employee_key"
    dim_product ||--o{ fact_sales_order_line : "product_key"
    dim_shipper ||--o{ fact_sales_order_line : "shipper_key"

    fact_sales_order_line {
        bigint sales_order_line_key PK
        integer order_id "degenerate dim"
        integer product_id "natural key, grain"
        integer customer_key FK
        integer employee_key FK
        integer product_key FK
        integer shipper_key FK
        integer order_date_key FK
        integer required_date_key FK
        integer shipped_date_key FK
        smallint quantity "additive"
        numeric unit_price "non-additive"
        numeric discount_pct "NON-ADDITIVE ratio"
        numeric gross_amount "additive, generated"
        numeric discount_amount "additive, generated"
        numeric net_amount "additive, generated"
    }

    dim_customer {
        integer customer_key PK
        char customer_id "natural key"
        varchar company_name
        varchar contact_name
        varchar city
        varchar country
        timestamptz valid_from "SCD2"
        timestamptz valid_to "SCD2, NULL = current"
        boolean is_current "generated"
        tstzrange validity "generated, EXCLUDE"
    }

    dim_product {
        integer product_key PK
        integer product_id "natural key"
        varchar product_name
        numeric unit_price
        boolean discontinued
        varchar category_name "collapsed hierarchy"
        varchar supplier_name "collapsed hierarchy"
        varchar supplier_country "collapsed hierarchy"
        smallint units_in_stock "TYPE 1"
        timestamptz valid_from "SCD2"
        timestamptz valid_to "SCD2"
    }

    dim_employee {
        integer employee_key PK
        integer employee_id "natural key"
        varchar full_name
        varchar title
        integer manager_employee_id "flattened hierarchy"
        varchar manager_name "flattened hierarchy"
        boolean is_manager
        timestamptz valid_from "SCD2"
        timestamptz valid_to "SCD2"
    }

    dim_shipper {
        integer shipper_key PK
        integer shipper_id "natural key"
        varchar company_name "TYPE 1"
    }

    dim_date {
        integer date_key PK "smart key yyyymmdd"
        date full_date
        smallint year_number
        char quarter_name
        varchar month_name
        smallint fiscal_year "UK, Apr start"
        boolean is_weekend
    }
```

## Fulfilment star — accumulating snapshot

**Grain: one row per order.** Owns freight and delivery-cycle measures, and
deliberately **no revenue measures** — so no query can double-count by joining
both facts.

```mermaid
erDiagram
    dim_date ||--o{ fact_order_fulfilment : "order_date_key"
    dim_customer ||--o{ fact_order_fulfilment : "customer_key"
    dim_employee ||--o{ fact_order_fulfilment : "employee_key"
    dim_shipper ||--o{ fact_order_fulfilment : "shipper_key"

    fact_order_fulfilment {
        bigint order_fulfilment_key PK
        integer order_id "degenerate dim, grain"
        integer customer_key FK
        integer employee_key FK
        integer shipper_key FK
        integer order_date_key FK
        integer required_date_key FK
        integer shipped_date_key FK
        date order_date "milestone"
        date required_date "milestone"
        date shipped_date "milestone"
        numeric freight_amount "additive"
        smallint order_line_count "additive"
        integer days_to_ship "generated, semi-additive"
        integer days_late "generated, semi-additive"
        boolean is_shipped "generated"
        boolean is_late "generated"
    }
```

### Why two facts

The source `Orders` table mixes two grains: order lines, and the order itself
(freight, ship-to address, milestone dates). Modelling both in one fact is the
most common dimensional modelling error there is.

**Measured on this data:** true freight is **£64,942.69**. Summed across the
line grain it becomes **£207,306.10** — an overstatement of **3.19×**. Note that
is *higher* than the 2.60 average lines per order, because larger orders carry
more freight and are weighted more heavily by the duplication.

The two facts join on the degenerate dimension `order_id` when a question needs
both — the correct way to combine facts of differing grain.

## Bus matrix

| Business process | Grain | Date | Customer | Employee | Product | Shipper |
|---|---|:--:|:--:|:--:|:--:|:--:|
| Sales order line | product per order | ● | ● | ● | ● | ● |
| Order fulfilment | order | ● | ● | ● | — | ● |

Both facts share the same conformed dimensions, so they can be compared and
drilled across without translation.

## Source system — Northwind OLTP (3NF)

What the warehouse is built *from*. Preserved unmodified in
[`sqlserver/database/northwind/`](../sqlserver/database/northwind/).

```mermaid
erDiagram
    Categories ||--o{ Products : "CategoryID"
    Suppliers ||--o{ Products : "SupplierID"
    Products ||--o{ OrderDetails : "ProductID"
    Orders ||--o{ OrderDetails : "OrderID"
    Customers ||--o{ Orders : "CustomerID"
    Employees ||--o{ Orders : "EmployeeID"
    Shippers ||--o{ Orders : "ShipVia"
    Employees ||--o{ Employees : "ReportsTo"
    Region ||--o{ Territories : "RegionID"
    Employees ||--o{ EmployeeTerritories : "EmployeeID"
    Territories ||--o{ EmployeeTerritories : "TerritoryID"
```

| Table | Rows |
|---|---:|
| Categories | 8 |
| Customers | 91 |
| Employees | 9 |
| Order Details | 2,155 |
| Orders | 830 |
| Products | 77 |
| Region | 4 |
| Shippers | 3 |
| Suppliers | 29 |
| Territories | 53 |
| EmployeeTerritories | 49 |

## Key design

| Concern | Decision |
|---|---|
| Dimension keys | Meaningless surrogates, `GENERATED ALWAYS AS IDENTITY` — nothing outside ETL may supply one |
| Date key | Smart key `yyyymmdd` — readable in raw fact data, sorts correctly, range-scannable without a join |
| Natural keys | Retained as dimension attributes for audit and lookup |
| Unresolved lookups | Every dimension has an Unknown member at `-1`; fact FKs are `NOT NULL DEFAULT -1` |
| Degenerate dimensions | `order_id`, `product_id` — identifiers with no attributes of their own live on the fact |
| Hierarchies | Collapsed into the dimension, never snowflaked |

Because unresolved lookups land on `-1` rather than `NULL`, every fact-to-dimension
join is a plain inner join that cannot drop a row — which is what allows the
tests to treat *any* orphan as a hard failure rather than an expected condition.
