-- Resolves each member's single current PCP (latest EFF_DT where TERM_DT IS NULL).
WITH ranked AS (
    SELECT
        pcp.*,
        p.PRPR_NAME     AS PCP_NAME,
        p.PRPR_NPI      AS PCP_NPI,
        ROW_NUMBER() OVER (
            PARTITION BY pcp.MEME_ID
            ORDER BY pcp.MEPR_EFF_DT DESC NULLS LAST
        )               AS rn
    FROM {{ ref('stg_mepr_prim_prov') }} pcp
    LEFT JOIN {{ ref('stg_prpr_prov') }} p ON pcp.PRPR_ID = p.PRPR_ID
    WHERE pcp.IS_ACTIVE_PCP = TRUE
)
SELECT
    MEME_ID,
    PRPR_ID             AS ACTIVE_PCP_PRPR_ID,
    PCP_NAME            AS ACTIVE_PCP_NAME,
    PCP_NPI             AS ACTIVE_PCP_NPI,
    MEPR_EFF_DT         AS PCP_EFF_DT,
    PCP_TYPE_DESC       AS ACTIVE_PCP_TYPE
FROM ranked
WHERE rn = 1
