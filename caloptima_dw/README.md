# caloptima_dw

dbt Core project for the CalOptima Health Facets CDC pipeline (RFP 26-038 demo).

## Architecture

```
FACETS_BRONZE.RAW (Openflow UPSERT)
  └── caloptima_dw (this project)
        ├── staging/     → FACETS_DEV.STAGING   (views)
        ├── intermediate/                        (ephemeral)
        ├── silver/      → FACETS_DEV.SILVER     (incremental merge)
        └── marts/       → FACETS_DEV.SILVER     (tables)
```

## Setup

```bash
pip install dbt-snowflake
dbt deps
dbt compile          # syntax + Jinja check, no warehouse needed
dbt test --select test_type:unit
```

## Running models

```bash
# Full Silver refresh (dev)
dbt run --select silver_provider silver_member silver_eligibility

# DQ marts
dbt run --select dup_metrics dq_row_counts

# All
dbt run
```

## Environment targets

| Target | Database | Schema |
|--------|----------|--------|
| dev    | FACETS_DEV | SILVER |
| qa     | FACETS_QA  | SILVER |
| prod   | FACETS_PROD | SILVER |

```bash
dbt run --target prod --vars '{"target_database": "FACETS_PROD"}'
```

## Key design decisions

- **Active rows**: Openflow uses `_SNOWFLAKE_DELETED = FALSE` for soft deletes — all staging models apply `{{ active_records() }}` macro
- **Provider dedup**: NPI-based with `ROW_NUMBER()` on `SYS_LAST_UPD_DTM DESC` — 1 row per NPI in Silver
- **Member dedup**: Demographic key (`SBSB_ID + DOB + SEX + NAME`) MD5 hash — resolves near-duplicates across subscriber groups
- **Eligibility**: `LAG()`-based span normalization collapses overlapping `MEPE_PRCS_ELIG` rows into non-overlapping spans
- **Incremental filter**: `_SNOWFLAKE_UPDATED_AT > MAX(BRONZE_UPDATED_AT)` — picks up all Openflow upserts since last run
