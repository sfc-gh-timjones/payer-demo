-- =============================================================================
-- FILE: scd2_provider_demo.sql
-- PURPOSE: Demo queries for SCD Type 2 — provider history tracking
--          comparing PROVIDER_SNAPSHOT (dbt) vs PROVIDER_SCD2_VIA_STREAM (stream/task)
--
-- Known providers with real change history (as of 2026-07-13):
--   3390  Dr. Jones, NP     AC → IN  (changed 4:47 PM today)
--   5318  Dr. Anderson, NP  AC → AC  (changed 12:01 PM today)
--   6268  Dr. Smith, MD     AC → SU  (changed 10:55 AM today)
-- =============================================================================


-- =============================================================================
-- QUERY 1A: Spot-check — known changed providers in PROVIDER_SNAPSHOT (dbt)
-- =============================================================================

SELECT
    PRPR_ID,
    PRPR_NAME,
    PRPR_STS,
    PROVIDER_TYPE,
    PRPR_TAXONOMY_CD,
    CONTRACT_TYPE,
    DBT_VALID_FROM,
    DBT_VALID_TO,
    CASE WHEN DBT_VALID_TO IS NULL THEN TRUE ELSE FALSE END AS IS_CURRENT
FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT
WHERE PRPR_ID IN (3390, 5318, 6268)
ORDER BY PRPR_ID, DBT_VALID_TO NULLS FIRST;


-- =============================================================================
-- QUERY 1B: Spot-check — same providers in PROVIDER_SCD2_VIA_STREAM (stream/task)
-- =============================================================================

SELECT
    PRPR_ID,
    PRPR_NAME,
    PRPR_STS,
    PROVIDER_TYPE,
    PRPR_TAXONOMY_CD,
    CONTRACT_TYPE,
    EFFECTIVE_FROM,
    EFFECTIVE_TO,
    IS_CURRENT
FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
WHERE PRPR_ID IN (3390, 5318, 6268)
ORDER BY PRPR_ID, EFFECTIVE_TO NULLS FIRST;


-- =============================================================================
-- QUERY 2: Full DEV provider list — providers with history floated to top
--          (stream table only — shows the full SCD2 picture dynamically)
-- =============================================================================

WITH PROV_WITH_HISTORY AS (
    SELECT PRPR_ID, COUNT(*) AS VERSION_COUNT
    FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
    GROUP BY PRPR_ID
    HAVING COUNT(*) > 1
)

SELECT
    s.PRPR_ID,
    s.PRPR_NAME,
    s.PROVIDER_TYPE,
    s.PRPR_STS,
    s.PRPR_MCTR_TYPE,
    s.PRPR_TAXONOMY_CD,
    s.EFFECTIVE_FROM,
    s.EFFECTIVE_TO,
    s.IS_CURRENT,
    COALESCE(h.VERSION_COUNT, 1) AS VERSION_COUNT
FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM AS s
LEFT JOIN PROV_WITH_HISTORY AS h ON s.PRPR_ID = h.PRPR_ID
ORDER BY
    h.VERSION_COUNT DESC NULLS LAST,
    s.PRPR_ID,
    s.EFFECTIVE_TO NULLS FIRST;


-- =============================================================================
-- QUERY 3A: SELECT * — PROVIDER_SNAPSHOT (dbt)
-- =============================================================================

SELECT *
FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT
ORDER BY PRPR_ID, DBT_VALID_TO NULLS FIRST;


-- =============================================================================
-- QUERY 3B: SELECT * — PROVIDER_SCD2_VIA_STREAM (stream/task)
-- =============================================================================

SELECT *
FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
ORDER BY PRPR_ID, EFFECTIVE_TO NULLS FIRST;
