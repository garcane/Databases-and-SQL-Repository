# Dimensional Model

Kimball star schema. Diagrams: [`architecture/star-schema.md`](../architecture/star-schema.md).

---

## Bus matrix

| Business process | Grain | Date | Customer | Employee | Product | Shipper |
|---|---|:--:|:--:|:--:|:--:|:--:|
| Sales order line | one row per product per order | ● | ● | ● | ● | ● |
| Order fulfilment | one row per order | ● | ● | ● | — | ● |

Both facts use the same conformed dimensions, so they drill across without
translation.

---

## Grain declarations

Grain is declared, **enforced by a constraint**, and **tested**. A grain that is
only written down in a document is a grain that drifts — and when a fact grain
drifts, every measure silently doubles without raising an error.

| Fact | Grain | Enforced by | Tested by |
|---|---|---|---|
| `fact_sales_order_line` | Exactly one row per product per order | `uq_fact_sales_order_line_grain (order_id, product_id)` | `DUP-001` |
| `fact_order_fulfilment` | Exactly one row per order | `uq_fact_order_fulfilment_grain (order_id)` | `DUP-002` |

### Why two facts at different grains

The source `Orders` table mixes two grains: the order lines, and the order itself
(freight, ship-to address, milestone dates). Modelling both in one fact is the
most common dimensional modelling error there is.

**Measured:** true freight is **£64,942.69**; summed across the line grain it
becomes **£207,306.10** — **3.19×** overstatement. That is *higher* than the 2.60
average lines per order, because larger orders carry more freight and are
weighted more heavily by the duplication. Estimating the error as "about the
average line count" would itself have been wrong.

`fact_order_fulfilment` therefore carries **no revenue measures at all** — not as
an oversight but so that no query can double-count by joining both. The two join
on the degenerate dimension `order_id` when a question needs both.

---

## Dimensions

| Dimension | Grain | SCD | Rows | Rationale |
|---|---|---|---:|---|
| `dim_date` | one calendar day | n/a | 3,288 | The calendar does not change |
| `dim_customer` | customer per version | **Type 2** | 92 | Address, contact and title are exactly what analysts slice history by |
| `dim_product` | product per version | **Type 2** + Type 1 | 78 | Price and description versioned; stock levels overwritten |
| `dim_employee` | employee per version | **Type 2** | 10 | Title and territory changes must not restate past sales |
| `dim_shipper` | shipper | **Type 1** | 4 | Three carriers with a name and a phone number |

Row counts include the Unknown member.

### SCD strategy, justified per dimension

**Type 2 — `dim_customer`, `dim_product`, `dim_employee`.** Restating three
years of sales because a contact changed job title is precisely the failure mode
Type 2 exists to prevent.

**Type 1 — `dim_shipper`.** Nobody will ever ask what a carrier's phone number
was in 1997. The point of documenting SCD strategy per dimension is to be able
to justify Type 1 where Type 1 is correct, rather than applying Type 2 by reflex.

**Type 1 within a Type 2 dimension — product stock levels.** `units_in_stock`,
`units_on_order` and `reorder_level` are overwritten in place. Versioning them
would generate a new row per product per day: a 77-row dimension growing by
~28,000 rows a year, with every historical query needing a date-qualified join to
find "the" product. Inventory level is a **fact measure, not a product
attribute** — it belongs in a periodic snapshot fact if it is ever needed.

### How Type 2 is implemented

| Column | Purpose |
|---|---|
| `valid_from timestamptz NOT NULL` | Start of the period, inclusive |
| `valid_to timestamptz NULL` | End, exclusive. **`NULL` means current** |
| `is_current boolean` | `GENERATED ALWAYS AS (valid_to IS NULL) STORED` |
| `validity tstzrange` | `GENERATED ALWAYS AS (tstzrange(valid_from, valid_to)) STORED` |
| `row_hash text` | `md5` fingerprint of tracked attributes |

`NULL` rather than a `9999-12-31` sentinel, for two concrete reasons:
`tstzrange(valid_from, NULL)` yields a genuinely unbounded range that the
database can reason about, and `IS NULL` is immutable where a comparison against
a cast literal is not — which matters for generated columns.

**Overlapping versions are impossible, not merely unlikely.** Each Type 2
dimension carries:

```sql
CONSTRAINT ex_dim_customer_no_overlap
    EXCLUDE USING gist (customer_id WITH =, validity WITH &&)
```

Two overlapping versions of one entity cannot be committed, whatever the loader
does. SQL Server has no declarative equivalent — it relies on procedural
discipline plus an audit query. A partial unique index `WHERE is_current` closes
the remaining gap (two current rows written with identical `valid_from`).

**Gaps are the mirror image, and no constraint prevents them.** If a version is
closed and its successor starts later, the entity has an uncovered period and
every as-at query over that window silently returns nothing. Check `SCD-004`
tests for it.

### Collapsed hierarchies

Category and supplier attributes are denormalised **into** `dim_product` rather
than kept as separate dimension tables.

Both relationships are many-to-one, so a separate table buys nothing but an extra
join on every query, while costing the ability to browse category and supplier
attributes in one pass. Storage saved by normalising a 29-row supplier table is
not a real number. "Sales by supplier country" still works — the attribute simply
lives on `dim_product`.

The employee reporting hierarchy is flattened the same way, to
`manager_employee_id` / `manager_name`: facts join to an employee, not to a
recursive CTE, and "sales by manager" costs no extra join.

### Role-playing dimensions

`dim_date` is joined three times by the sales fact — order, required, shipped.
Views in the presentation layer give each role its own name and column prefix
(`order_year`, `shipped_month`), which is effectively free: PostgreSQL inlines a
simple view into the calling query.

### Unknown members

Every dimension has a row at key `-1`, and every fact foreign key is
`NOT NULL DEFAULT -1`.

An unresolvable lookup therefore **retains** the fact row rather than dropping it
or writing `NULL`. Revenue that cannot be attributed is still revenue, and a fact
silently missing from the warehouse is far worse than one attributed to
`Unknown` where it is visible and countable.

This has a second effect that pays for itself: because no fact key is ever
`NULL`, every star join is a plain inner join that cannot drop a row — which is
what allows the tests to treat *any* orphan as a hard failure.

### Degenerate dimensions

`order_id` and `product_id` sit on the facts. They are identifiers with no
attributes of their own, so a one-column dimension table would add a join and
nothing else. `order_id` doubles as the join key between the two facts.

---

## Measures and additivity

### `fact_sales_order_line`

| Measure | Additivity | Note |
|---|---|---|
| `quantity` | Fully additive | |
| `gross_amount` | Fully additive | Generated: `quantity * unit_price` |
| `discount_amount` | Fully additive | Generated |
| `net_amount` | Fully additive | Generated: `quantity * unit_price * (1 - discount_pct)` |
| `unit_price` | **Non-additive** | A rate. Average it, never sum it |
| `discount_pct` | **Non-additive** | A ratio — see below |

> **`discount_pct` must never be summed or naively averaged.** Derive it at the
> reporting grain: `SUM(discount_amount) / SUM(gross_amount)`. The presentation
> views do exactly this, and the column carries a `COMMENT` saying so.

### `fact_order_fulfilment`

| Measure | Additivity | Note |
|---|---|---|
| `freight_amount` | Fully additive | Only at order grain |
| `order_line_count` | Fully additive | Must reconcile to the line fact — check `REC-006` |
| `days_to_ship` | **Semi-additive** | Average, never sum. `NULL` until shipped |
| `days_late` | **Semi-additive** | Average, never sum |

`NULL` for unreached milestones is deliberate: an unshipped order has no shipping
duration, and `NULL` keeps it out of `AVG()` rather than dragging the average
toward zero.

### Why derived measures are generated columns

The arithmetic is defined **once**, in the schema. It cannot drift between one
analyst's report and another's, and it cannot be left stale by a partial reload.
Attempting to write one raises `428C9`.

---

## Keys

| Concern | Decision |
|---|---|
| Dimension PK | Meaningless surrogate, `GENERATED ALWAYS AS IDENTITY` |
| `dim_date` PK | Smart key `yyyymmdd` — readable in raw facts, sorts correctly, range-scannable without a join |
| Natural keys | Retained as attributes for audit and lookup |
| Fact PK | Surrogate identity; the **grain** is a separate `UNIQUE` constraint |

`dim_date` is the deliberate exception to the meaningless-surrogate rule, and
carries a `CHECK` that `date_key` always agrees with `full_date` — a silent
mismatch there would misdirect every fact loaded for that day.

---

## Key resolution and the historical caveat

Facts resolve to the dimension version **current at load time**, not the version
in force on the order date. This is correct here, and worth being explicit about
because "SCD Type 2" is often assumed to mean the opposite:

- The source is a **static extract**. Every dimension row was created by the
  initial load, so its validity begins at the load timestamp — long after
  1996–1998, when the orders were placed. Matching order dates against those
  ranges would resolve *every* fact to the Unknown member.
- Type 2 pays off **from the load forward**: once an attribute changes, orders
  loaded before the change stay pointed at the old version.
- Reconstructing pre-warehouse history is not possible from this source — the
  OLTP system keeps no attribute history to reconstruct it from. Inventing
  effective dates would fabricate data.

---

## Verification

| Property | Result |
|---|---|
| Revenue, all three layers | **£1,265,793.04** identical |
| Gross revenue | £1,354,458.59 reconciled |
| Freight, order grain | £64,942.69 reconciled |
| Facts on Unknown members | 0 |
| Grain violations | 0 |
| SCD2 overlaps / gaps | 0 / 0 |
| Total checks | 71/71 pass |
