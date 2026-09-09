{{ config(severity='warn') }}
-- Singular test: exactly one current row per NPI in Silver.
-- NOTE: severity=warn because the snapshot sources from stg_prpr_prov (all
-- PRPR_IDs, no NPI dedup). Two PRPR_IDs can share the same randomly-generated
-- NPI — a data quality observation, not a pipeline blocker. The legacy model
-- sourced from int_prpr_org_hierarchy (IS_DUPLICATE=FALSE) which guaranteed
-- uniqueness; the snapshot approach does not.
-- Returns rows if the test FAILS (dbt convention: passes when query returns 0 rows).
SELECT PRPR_NPI, COUNT(*) AS current_npi_count
FROM {{ ref('provider') }}
WHERE dbt_valid_to IS NULL
GROUP BY PRPR_NPI
HAVING COUNT(*) > 1
