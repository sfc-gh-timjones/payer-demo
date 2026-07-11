{{ config(severity='warn') }}
-- Singular test: no member should have more than one active PCP assignment
-- BEFORE resolution by int_meme_pcp_current.
-- silver.member already has one row per MEME_ID so testing there is a no-op.
-- Returns rows if the test FAILS (dbt convention: passes when query returns 0 rows).
SELECT MEME_ID, COUNT(*) AS active_pcp_count
FROM {{ ref('stg_mepr_prim_prov') }}
WHERE IS_ACTIVE_PCP = TRUE
GROUP BY MEME_ID
HAVING COUNT(*) > 1
