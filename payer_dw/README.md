# payer_dw

dbt Core project for the Payer Facets CDC pipeline.

## Architecture

```
FACETS_BRONZE.RAW (Openflow CDC UPSERT)
  └── payer_dw (this project)
        ├── staging/        → FACETS_DEV.STAGING   (views, 12 models)
        ├── intermediate/                           (ephemeral, compiled inline)
        ├── silver/         → FACETS_DEV.SILVER     (incremental merge, 4 models)
        ├── gold/           → FACETS_DEV.GOLD       (views, 3 models — Phase 1 scaffolds)
        └── ops/            → FACETS_DEV.DQ         (tables, 2 models — pipeline observability)
```

**Layer responsibilities:**
- **STAGING** — light source renaming/decoding, one view per Bronze table, active-records filter
- **SILVER** — conformed entities with business logic (SCD2, dedup, span normalization, quarantine)
- **GOLD** — analytics-ready consumer layer (Phase 1 scaffold; full logic in Phase 2)
- **DQ** — pipeline observability (Bronze vs Silver row counts, duplicate rate metrics)

## Setup

```bash
pip install dbt-snowflake
dbt deps
dbt compile          # syntax + Jinja check, no warehouse needed
dbt test --select test_type:unit
```

## Running models

```bash
# First-time full build (required after schema changes or SCD2 column additions)
dbt run --full-refresh

# Silver refresh (incremental — picks up Bronze changes since last run)
dbt run --select provider member eligibility rejected_providers

# Gold scaffolds (views — rebuild on query, but explicit run registers them)
dbt run --select tag:gold

# DQ ops (pipeline observability)
dbt run --select dup_metrics dq_row_counts

# All models
dbt run
```

## Environment targets

| Target | Database    | Schema  |
|--------|-------------|---------|
| dev    | FACETS_DEV  | SILVER  |
| qa     | FACETS_QA   | SILVER  |
| prod   | FACETS_PROD | SILVER  |

```bash
# Switch target via --target flag
dbt run --target qa
dbt run --target prod
```

## Key design decisions

- **Active rows**: Openflow uses `_SNOWFLAKE_DELETED = FALSE` for soft deletes — all staging models apply `{{ active_records() }}` macro
- **Provider SCD2**: `SILVER.PROVIDER` is a Type 2 SCD table. Each status/attribute change creates a new row (`IS_CURRENT=TRUE`) and closes the old one (`EFFECTIVE_TO` set). Query with `WHERE IS_CURRENT = TRUE` for current state.
- **Provider dedup**: NPI-based `ROW_NUMBER()` on `SYS_LAST_UPD_DTM DESC` — 1 active provider per NPI in Silver
- **Rejected providers**: Providers with invalid/null NPI land in `SILVER.REJECTED_PROVIDERS`. Fix the NPI in source → next dbt run promotes to `SILVER.PROVIDER`
- **Member dedup**: Demographic key (SBSB_ID + DOB + SEX + NAME) MD5 hash — resolves near-duplicates across subscriber groups
- **Eligibility spans**: `LAG()`-based span normalization collapses overlapping `MEPE_PRCS_ELIG` rows into non-overlapping spans
- **Incremental filter**: `_SNOWFLAKE_UPDATED_AT > MAX(BRONZE_UPDATED_AT)` — picks up all Openflow upserts since last run
- **Gold (Phase 1)**: Views with description strings only. Phase 2 will add full analytic logic referencing Silver models.

## Demo: Scenario 4 — Provider Status Change (SCD2)

```sql
-- 1. Check current state of a provider
SELECT PRPR_ID, PRPR_STS, STATUS_DESC, IS_CURRENT, EFFECTIVE_FROM, EFFECTIVE_TO
FROM FACETS_DEV.SILVER.PROVIDER
WHERE PRPR_ID = <id>;
-- → 1 row, IS_CURRENT=TRUE, EFFECTIVE_TO=NULL

-- 2. Change provider status in Azure SQL (AC → IN)
-- 3. Run: dbt run --select provider

-- 4. Show the audit trail
SELECT PRPR_ID, PRPR_STS, IS_CURRENT, EFFECTIVE_FROM, EFFECTIVE_TO
FROM FACETS_DEV.SILVER.PROVIDER
WHERE PRPR_ID = <id>
ORDER BY EFFECTIVE_FROM;
-- → 2 rows: closed version (IS_CURRENT=FALSE, EFFECTIVE_TO set) + new version (IS_CURRENT=TRUE)
```

## Demo: NPI Quarantine

```sql
-- Providers with invalid NPI (before fix)
SELECT * FROM FACETS_DEV.SILVER.REJECTED_PROVIDERS;

-- After fixing NPI in Facets → dbt run → row moves to SILVER.PROVIDER
-- Confirmed with:
SELECT COUNT(*) FROM FACETS_DEV.SILVER.REJECTED_PROVIDERS;  -- decrements
SELECT * FROM FACETS_DEV.SILVER.PROVIDER WHERE IS_CURRENT = TRUE AND PRPR_ID = <id>;  -- appears
```

## Demo: Gold Architecture (Phase 1 Scaffold)

```sql
-- Show the Gold layer exists and is queryable
SELECT model_description FROM FACETS_DEV.GOLD.GOLD_MEMBER_ENROLLMENT;
SELECT model_description FROM FACETS_DEV.GOLD.GOLD_PROVIDER_DIRECTORY;
SELECT model_description FROM FACETS_DEV.GOLD.GOLD_ELIGIBILITY_SNAPSHOT;
-- Each returns one row describing the Phase 2 analytic logic to be built.
```
