-- =============================================================================
-- FILE: scd2_provider_demo.sql
-- PURPOSE: Demo queries for Scenario 4 (SCD Type 2) — provider history tracking
--          in FACETS_DEV.SILVER.PROVIDER
-- =============================================================================


-- =============================================================================
-- QUERY 1: Spot-check — providers with known history (multiple versions)
-- =============================================================================

SELECT
    a.PRPR_ID,
    a.PRPR_NAME,
    a.PROVIDER_TYPE,
    a.PRPR_STS,
    a.PRPR_MCTR_TYPE,
    a.PRPR_TAXONOMY_CD,
    a.CONTRACT_TYPES,
    a.IS_CURRENT,
    a.EFFECTIVE_FROM,
    a.EFFECTIVE_TO
FROM FACETS_DEV.SILVER.PROVIDER AS a
WHERE a.PRPR_ID IN (
    1082,
    1091,
    1153,
    1248,
    1304,
    1334,
    1346
)
ORDER BY
    a.PRPR_ID,
    a.EFFECTIVE_TO NULLS FIRST;


-- =============================================================================
-- QUERY 2: Full provider list — providers with history floated to top
-- =============================================================================

WITH PROV_WITH_HISTORY AS (
    SELECT DISTINCT PRPR_ID, 1 AS HISTORY_FLG
    FROM FACETS_DEV.SILVER.PROVIDER
    WHERE EFFECTIVE_TO IS NOT NULL
)

SELECT
    a.PRPR_ID,
    a.PRPR_NAME,
    a.PROVIDER_TYPE,
    a.PRPR_STS,
    a.PRPR_MCTR_TYPE,
    a.PRPR_TAXONOMY_CD,
    CONCAT(a.PRACTICE_ADDR1, ', ', a.PRACTICE_ADDR2, ', ', a.PRACTICE_CITY, ', ', a.PRACTICE_STATE, ', ', a.PRACTICE_ZIP) AS PRACTICE_ADDRESS,
    a.TERM_DT,
    a.CONTRACT_TYPES,
    a.IS_CURRENT,
    a.EFFECTIVE_FROM,
    a.EFFECTIVE_TO,
    b.HISTORY_FLG
FROM
    FACETS_DEV.SILVER.PROVIDER AS a
    LEFT JOIN PROV_WITH_HISTORY AS b ON a.PRPR_ID = b.PRPR_ID
ORDER BY
    b.HISTORY_FLG DESC NULLS LAST,
    a.PRPR_ID,
    a.EFFECTIVE_TO NULLS FIRST;


-- =============================================================================
-- QUERY 3: Investigate a specific provider — all versions
-- =============================================================================

SELECT *
FROM FACETS_DEV.SILVER.PROVIDER
WHERE PRPR_ID = 1315;


-- =============================================================================
-- QUERY 4: Trace back to Bronze journal for a specific provider
-- =============================================================================

SELECT *
FROM FACETS_BRONZE.RAW.CMC_PRPR_PROV_JOURNAL_1782799685_1
WHERE PAYLOAD__PRPR_ID = 1315;
