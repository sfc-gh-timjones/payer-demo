WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY DEMO_KEY
            ORDER BY SYS_LAST_UPD_DTM DESC NULLS LAST, MEME_ID DESC
        )                                       AS rn,
        COUNT(*) OVER (PARTITION BY DEMO_KEY)   AS demo_key_count
    FROM {{ ref('stg_meme_member') }}
)
SELECT *,
    CASE WHEN rn = 1 THEN FALSE ELSE TRUE END   AS IS_DUPLICATE,
    demo_key_count - 1                          AS DUPLICATE_COUNT
FROM ranked
