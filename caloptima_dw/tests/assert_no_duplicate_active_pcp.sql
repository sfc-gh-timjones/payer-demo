-- Singular test: no member should have more than one active PCP in Silver.
-- Returns rows if the test FAILS (dbt convention: test passes when query returns 0 rows).
SELECT MEME_ID, COUNT(*) AS active_pcp_count
FROM {{ ref('silver_member') }}
WHERE ACTIVE_PCP_PRPR_ID IS NOT NULL
GROUP BY MEME_ID
HAVING COUNT(*) > 1
