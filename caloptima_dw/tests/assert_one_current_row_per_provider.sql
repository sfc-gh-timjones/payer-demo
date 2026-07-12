-- Singular test: exactly one current row per PRPR_ID in the SCD2 provider table.
-- A merge bug that fails to close old rows would leave two "current" versions.
-- Returns rows if the test FAILS (dbt convention: passes when query returns 0 rows).
SELECT PRPR_ID, COUNT(*) AS current_row_count
FROM {{ ref('provider') }}
WHERE dbt_valid_to IS NULL
GROUP BY PRPR_ID
HAVING COUNT(*) > 1
