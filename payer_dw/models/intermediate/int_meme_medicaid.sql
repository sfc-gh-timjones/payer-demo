-- Joins active Medi-Cal records to members (most recent EFF_DT if multiple).
WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY MEME_ID
            ORDER BY MECD_EFF_DT DESC NULLS LAST
        ) AS rn
    FROM {{ ref('stg_mecd_medicaid') }}
    WHERE IS_ACTIVE_MEDICAID = TRUE
)
SELECT
    MEME_ID,
    MECD_AID_CD,
    MECD_BIC,
    MECD_EFF_DT,
    MECD_TERM_DT
FROM ranked
WHERE rn = 1
