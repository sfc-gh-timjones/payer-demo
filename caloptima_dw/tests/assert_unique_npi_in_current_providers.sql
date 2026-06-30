-- Singular test: exactly one IS_CURRENT=TRUE row per NPI in Silver.
-- int_prpr_dedup takes one row per NPI, so this should never fire.
-- Returns rows if the test FAILS (dbt convention: passes when query returns 0 rows).
SELECT PRPR_NPI, COUNT(*) AS current_npi_count
FROM {{ ref('provider') }}
WHERE IS_CURRENT = TRUE
GROUP BY PRPR_NPI
HAVING COUNT(*) > 1
