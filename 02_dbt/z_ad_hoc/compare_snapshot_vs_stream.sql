-- =============================================================================
-- COMPARE: PROVIDER_SNAPSHOT (dbt) vs PROVIDER_SCD2_VIA_STREAM (stream/task)
--
-- Both tables implement SCD2 for CMC_PRPR_PROV but use different approaches:
--   PROVIDER_SNAPSHOT      → dbt snapshot, columns: dbt_valid_from / dbt_valid_to
--   PROVIDER_SCD2_VIA_STREAM → stream+task+MERGE, columns: EFFECTIVE_FROM / EFFECTIVE_TO / IS_CURRENT
--
-- Run each section independently to drill in on a specific comparison dimension.
-- =============================================================================

USE DATABASE FACETS_DEV;
USE SCHEMA SILVER;


-- =============================================================================
-- 1. SUMMARY: Row counts and current provider counts
-- =============================================================================

SELECT
    'dbt snapshot'    AS approach,
    COUNT(*)          AS total_rows,
    COUNT(DISTINCT PRPR_ID) AS distinct_providers,
    SUM(CASE WHEN dbt_valid_to IS NULL THEN 1 ELSE 0 END) AS current_rows,
    SUM(CASE WHEN dbt_valid_to IS NOT NULL THEN 1 ELSE 0 END) AS historical_rows
FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT

UNION ALL

SELECT
    'stream/task'     AS approach,
    COUNT(*)          AS total_rows,
    COUNT(DISTINCT PRPR_ID) AS distinct_providers,
    SUM(CASE WHEN IS_CURRENT THEN 1 ELSE 0 END) AS current_rows,
    SUM(CASE WHEN NOT IS_CURRENT THEN 1 ELSE 0 END) AS historical_rows
FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM

ORDER BY approach;


-- =============================================================================
-- 2. VERSION HISTORY: Number of SCD2 versions per provider in each table
--    Expect these to be equal for providers that have been through both pipelines.
-- =============================================================================

WITH snap_versions AS (
    SELECT PRPR_ID, COUNT(*) AS snap_versions
    FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT
    GROUP BY PRPR_ID
),
stream_versions AS (
    SELECT PRPR_ID, COUNT(*) AS stream_versions
    FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
    GROUP BY PRPR_ID
)
SELECT
    COALESCE(s.PRPR_ID, t.PRPR_ID)  AS PRPR_ID,
    s.snap_versions,
    t.stream_versions,
    (s.snap_versions - t.stream_versions) AS version_diff
FROM snap_versions  s
FULL OUTER JOIN stream_versions t ON s.PRPR_ID = t.PRPR_ID
WHERE s.snap_versions != t.stream_versions   -- only show mismatches
   OR s.PRPR_ID IS NULL
   OR t.PRPR_ID IS NULL
ORDER BY ABS(COALESCE(s.snap_versions, 0) - COALESCE(t.stream_versions, 0)) DESC
LIMIT 100;


-- =============================================================================
-- 3. CURRENT STATE DIFF: Providers where current attribute values differ
--    Joins on PRPR_ID (current row only) and compares shared columns.
--    Any row returned means the two approaches disagree on current state.
-- =============================================================================

WITH snap_current AS (
    SELECT
        PRPR_ID,
        PRPR_NPI,
        PRPR_NAME,
        PRPR_ENTITY,
        PRPR_STS,
        STATUS_DESC,
        CONTRACT_TYPE,
        PRPR_MCTR_TYPE,
        PRPR_TAXONOMY_CD,
        TERM_DT,
        IS_DELETED,
        dbt_valid_from  AS effective_from_snap
    FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT
    WHERE dbt_valid_to IS NULL
),
stream_current AS (
    SELECT
        PRPR_ID,
        PRPR_NPI,
        PRPR_NAME,
        PRPR_ENTITY,
        PRPR_STS,
        STATUS_DESC,
        CONTRACT_TYPE,
        PRPR_MCTR_TYPE,
        PRPR_TAXONOMY_CD,
        TERM_DT,
        IS_DELETED,
        EFFECTIVE_FROM  AS effective_from_stream
    FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
    WHERE IS_CURRENT = TRUE
)
SELECT
    s.PRPR_ID,

    -- Flag which columns differ
    CASE WHEN s.PRPR_NPI         != t.PRPR_NPI         THEN '❌' ELSE '✓' END AS npi_match,
    CASE WHEN s.PRPR_NAME        != t.PRPR_NAME        THEN '❌' ELSE '✓' END AS name_match,
    CASE WHEN s.PRPR_ENTITY      != t.PRPR_ENTITY      THEN '❌' ELSE '✓' END AS entity_match,
    CASE WHEN s.PRPR_STS         != t.PRPR_STS         THEN '❌' ELSE '✓' END AS status_match,
    CASE WHEN s.STATUS_DESC      != t.STATUS_DESC      THEN '❌' ELSE '✓' END AS status_desc_match,
    CASE WHEN s.CONTRACT_TYPE    != t.CONTRACT_TYPE    THEN '❌' ELSE '✓' END AS contract_match,
    CASE WHEN s.PRPR_MCTR_TYPE   != t.PRPR_MCTR_TYPE   THEN '❌' ELSE '✓' END AS mctr_type_match,
    CASE WHEN s.PRPR_TAXONOMY_CD != t.PRPR_TAXONOMY_CD THEN '❌' ELSE '✓' END AS taxonomy_match,
    CASE WHEN s.IS_DELETED       != t.IS_DELETED       THEN '❌' ELSE '✓' END AS deleted_match,

    -- Effective dates from each approach (should be equal or close)
    s.effective_from_snap,
    t.effective_from_stream,
    DATEDIFF('minute', s.effective_from_snap, t.effective_from_stream) AS effective_from_diff_mins,

    -- Snapshot values
    s.PRPR_NPI         AS snap_npi,
    s.PRPR_STS         AS snap_sts,
    s.STATUS_DESC      AS snap_status_desc,
    s.CONTRACT_TYPE    AS snap_contract,

    -- Stream values
    t.PRPR_NPI         AS stream_npi,
    t.PRPR_STS         AS stream_sts,
    t.STATUS_DESC      AS stream_status_desc,
    t.CONTRACT_TYPE    AS stream_contract

FROM snap_current s
INNER JOIN stream_current t ON s.PRPR_ID = t.PRPR_ID
WHERE
    -- Any attribute mismatch
    s.PRPR_NPI         IS DISTINCT FROM t.PRPR_NPI
    OR s.PRPR_NAME     IS DISTINCT FROM t.PRPR_NAME
    OR s.PRPR_ENTITY   IS DISTINCT FROM t.PRPR_ENTITY
    OR s.PRPR_STS      IS DISTINCT FROM t.PRPR_STS
    OR s.CONTRACT_TYPE IS DISTINCT FROM t.CONTRACT_TYPE
    OR s.PRPR_MCTR_TYPE IS DISTINCT FROM t.PRPR_MCTR_TYPE
    OR s.PRPR_TAXONOMY_CD IS DISTINCT FROM t.PRPR_TAXONOMY_CD
    OR s.IS_DELETED    IS DISTINCT FROM t.IS_DELETED
ORDER BY s.PRPR_ID;


-- =============================================================================
-- 4. MISSING PROVIDERS: In one table but not the other (current rows only)
-- =============================================================================

-- In snapshot but NOT in stream/task
SELECT 'in snapshot only' AS side, PRPR_ID, PRPR_NPI, PRPR_NAME, PRPR_STS
FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT
WHERE dbt_valid_to IS NULL
  AND PRPR_ID NOT IN (
      SELECT PRPR_ID FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM WHERE IS_CURRENT = TRUE
  )

UNION ALL

-- In stream/task but NOT in snapshot
SELECT 'in stream only' AS side, PRPR_ID, PRPR_NPI, PRPR_NAME, PRPR_STS
FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
WHERE IS_CURRENT = TRUE
  AND PRPR_ID NOT IN (
      SELECT PRPR_ID FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT WHERE dbt_valid_to IS NULL
  )

ORDER BY side, PRPR_ID;


-- =============================================================================
-- 5. TIMELINE COMPARISON: Full SCD2 history side-by-side for a single provider
--    Replace :prpr_id with the provider ID you want to inspect.
-- =============================================================================

SET prpr_id = 12345;  -- replace with a PRPR_ID of interest

SELECT
    'snapshot'          AS source,
    PRPR_ID,
    PRPR_NPI,
    PRPR_STS,
    STATUS_DESC,
    dbt_valid_from      AS effective_from,
    dbt_valid_to        AS effective_to,
    (dbt_valid_to IS NULL) AS is_current
FROM FACETS_DEV.SILVER.PROVIDER_SNAPSHOT
WHERE PRPR_ID = $prpr_id

UNION ALL

SELECT
    'stream/task'       AS source,
    PRPR_ID,
    PRPR_NPI,
    PRPR_STS,
    STATUS_DESC,
    EFFECTIVE_FROM      AS effective_from,
    EFFECTIVE_TO        AS effective_to,
    IS_CURRENT
FROM FACETS_DEV.SILVER.PROVIDER_SCD2_VIA_STREAM
WHERE PRPR_ID = $prpr_id

ORDER BY source, effective_from;
