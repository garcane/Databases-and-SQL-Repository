# Databases and SQL — Cross-Platform Data Warehouse

> **Restructure in progress.** The repository has been reorganised into its target
> layout and the Microsoft SQL Server implementation isolated as the preserved
> reference. The PostgreSQL port, data quality tests and full documentation are
> being added in subsequent phases. This README is a placeholder and will be
> replaced by the executive-level overview.

## Current layout

```
├── sqlserver/     Reference implementation (golden source) — see sqlserver/README.md
├── postgres/      PostgreSQL port — staging, warehouse, presentation   [pending]
├── tests/         Data quality and validation scripts                  [pending]
├── docs/          Architecture, dimensional model, setup, migration    [pending]
├── architecture/  ERDs and pipeline diagrams                           [pending]
└── sample-data/   Curated demo subset                                  [pending]
```

The original repository README is preserved verbatim at
[`sqlserver/README-original.md`](sqlserver/README-original.md), and the
pre-restructure state is tagged `archive/ms-sql-reference`.
