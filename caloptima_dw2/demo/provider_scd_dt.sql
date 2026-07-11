-- =============================================================================
-- FILE: provider_scd_dt.sql
-- PURPOSE: SCD2 for providers using a Snowflake Dynamic Table.
--          Creates FACETS_DEV.SILVER.PROVIDER_SCD_DT.
--          Sources from SILVER.PROVIDER (legacy custom SCD2 table) which already
--          contains multiple rows per PRPR_ID — required for LEAD() to work.
--          Once dbt snapshot runs, swap source to SILVER.PROVIDER_SNAPSHOT and
--          rename EFFECTIVE_FROM → dbt_valid_from in the query below.
--
-- SOURCE: SILVER.PROVIDER (legacy custom SCD2, full version history per PRPR_ID)
--         NOTE: Cannot source directly from CMC_PRPR_PROV because Openflow keeps ONE
--         row per provider (updated in place). LEAD() requires multiple rows per PRPR_ID.
--
-- MANAGE:
-- ALTER DYNAMIC TABLE FACETS_DEV.SILVER.PROVIDER_SCD_DT SUSPEND;
-- ALTER DYNAMIC TABLE FACETS_DEV.SILVER.PROVIDER_SCD_DT RESUME;
-- ALTER DYNAMIC TABLE FACETS_DEV.SILVER.PROVIDER_SCD_DT REFRESH;
--
-- Check refresh history:
-- SELECT * FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
--     NAME => 'PROVIDER_SCD_DT'
-- )) ORDER BY REFRESH_START_TIME DESC LIMIT 10;
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE FACETS_DEV;
USE SCHEMA SILVER;
USE WAREHOUSE WH_XS;


-- =============================================================================
-- PROVIDER_SCD_DT — Dynamic Table SCD2
--
-- Pattern (from https://cevo.com.au — Dynamic Tables SCD2):
--   SELECT *,
--       LEAD(UPDATE_TIME) OVER (PARTITION BY ID ORDER BY UPDATE_TIME)
--           AS RECORD_END_TIME
--   FROM source_with_full_history
--
-- How LEAD() produces SCD2:
--   Row 1 (first version):   EFFECTIVE_FROM = v1_ts, EFFECTIVE_TO = v2_ts  (LEAD returns next row's ts)
--   Row 2 (current version): EFFECTIVE_FROM = v2_ts, EFFECTIVE_TO = NULL   (LEAD returns NULL = no next row)
--
-- Dynamic Table auto-refreshes when SILVER.PROVIDER is updated.
-- Note: LEAD() window functions may trigger a full refresh rather than incremental
-- (Snowflake cannot always compute row-level deltas for ordered window functions).
-- Full refresh is acceptable for the demo provider dataset.
-- =============================================================================

CREATE OR REPLACE DYNAMIC TABLE FACETS_DEV.SILVER.PROVIDER_SCD_DT
    TARGET_LAG = '1 MINUTE'
    WAREHOUSE  = WH_XS
    COMMENT    = 'SCD2 provider history via Dynamic Table. Reads SILVER.PROVIDER (legacy SCD2), derives EFFECTIVE_TO via LEAD(). Non-dbt column naming (EFFECTIVE_FROM/TO/IS_CURRENT).'
AS
SELECT
    -- Surrogate key (readable alternative to dbt_scd_id)
    PRPR_ID::VARCHAR || '-' ||
        DATE_PART(EPOCH_MILLISECONDS, EFFECTIVE_FROM::TIMESTAMP_NTZ)::VARCHAR   AS PROVIDER_SK,

    -- Business key
    PRPR_ID,

    -- Core provider attributes (identical to snapshot columns)
    PRPR_NPI,
    PRPR_NAME,
    PROVIDER_TYPE,
    PRPR_ENTITY,
    STATUS_DESC,
    PRPR_STS,
    CONTRACT_TYPE,
    PRPR_MCTR_TYPE,
    PRPR_TAXONOMY_CD,
    TERM_DT,
    IS_DELETED,
    updated_at                                                                   AS BRONZE_UPDATED_AT,

    -- SCD2 history columns — EFFECTIVE_FROM already exists in SILVER.PROVIDER
    -- EFFECTIVE_TO derived via LEAD() over the version history
    EFFECTIVE_FROM,

    LEAD(EFFECTIVE_FROM) OVER (
        PARTITION BY PRPR_ID
        ORDER BY EFFECTIVE_FROM ASC
    )                                                                            AS EFFECTIVE_TO,

    CASE
        WHEN LEAD(EFFECTIVE_FROM) OVER (
            PARTITION BY PRPR_ID
            ORDER BY EFFECTIVE_FROM ASC
        ) IS NULL
        THEN TRUE
        ELSE FALSE
    END                                                                          AS IS_CURRENT

FROM FACETS_DEV.SILVER.PROVIDER;


-- =============================================================================
-- Verification — run after initial refresh (allow up to 1 minute for lag)
-- =============================================================================

-- Check row count and current records
SELECT
    COUNT(*)                                            AS total_rows,
    SUM(CASE WHEN IS_CURRENT THEN 1 ELSE 0 END)         AS current_rows,
    COUNT(DISTINCT PRPR_ID)                             AS distinct_providers
FROM FACETS_DEV.SILVER.PROVIDER_SCD_DT;

-- Cross-check all three deployed SCD2 objects
-- Note: PROVIDER_SCD_STREAM_TASK has 14 more rows (seeded from raw Bronze without
-- IS_DUPLICATE filter); PROVIDER and PROVIDER_SCD_DT match at 5,263.
SELECT 'PROVIDER (legacy SCD2)'  AS implementation, COUNT(*) AS current FROM FACETS_DEV.SILVER.PROVIDER              WHERE IS_CURRENT = TRUE
UNION ALL
SELECT 'PROVIDER_SCD_STREAM'     AS implementation, COUNT(*) AS current FROM FACETS_DEV.SILVER.PROVIDER_SCD_STREAM_TASK WHERE IS_CURRENT = TRUE
UNION ALL
SELECT 'PROVIDER_SCD_DT'         AS implementation, COUNT(*) AS current FROM FACETS_DEV.SILVER.PROVIDER_SCD_DT          WHERE IS_CURRENT = TRUE
ORDER BY implementation;

-- Spot-check: compare a specific provider across implementations
-- SELECT 'SNAPSHOT' AS src, PRPR_ID, dbt_valid_from AS eff_from, dbt_valid_to AS eff_to FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT WHERE PRPR_ID = <id>
-- UNION ALL
-- SELECT 'STREAM'   AS src, PRPR_ID, EFFECTIVE_FROM, EFFECTIVE_TO FROM FACETS_DEV.SILVER.PROVIDER_SCD_STREAM_TASK WHERE PRPR_ID = <id>
-- UNION ALL
-- SELECT 'DT'       AS src, PRPR_ID, EFFECTIVE_FROM, EFFECTIVE_TO FROM FACETS_DEV.SILVER.PROVIDER_SCD_DT WHERE PRPR_ID = <id>
-- ORDER BY src, eff_from;
