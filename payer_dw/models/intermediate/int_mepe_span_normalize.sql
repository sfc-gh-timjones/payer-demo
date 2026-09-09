-- Collapses overlapping eligibility spans into non-overlapping normalized spans.
-- Uses ROW_NUMBER to distinguish "first row" from "previous row had no term date"
-- so open-ended spans (TERM_DT IS NULL) don't incorrectly trigger a new group.
WITH spans AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY MEME_ID, MEPE_PLAN_TYPE
            ORDER BY MEPE_EFF_DT, MEPE_ID
        )                               AS rn,
        LAG(MEPE_TERM_DT) OVER (
            PARTITION BY MEME_ID, MEPE_PLAN_TYPE
            ORDER BY MEPE_EFF_DT, MEPE_ID
        )                               AS prev_term_dt
    FROM {{ ref('stg_mepe_prcs_elig') }}
    WHERE MEPE_STS = 'AC'
),
grouped AS (
    SELECT *,
        SUM(
            CASE
                WHEN rn = 1                                                    THEN 1
                WHEN prev_term_dt IS NOT NULL AND MEPE_EFF_DT > prev_term_dt  THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY MEME_ID, MEPE_PLAN_TYPE
            ORDER BY MEPE_EFF_DT, MEPE_ID
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS span_group
    FROM spans
)
SELECT
    MEME_ID,
    MEPE_PLAN_TYPE,
    PLAN_TYPE_DESC,
    span_group,
    MIN(MEPE_EFF_DT)                                AS SPAN_EFF_DT,
    MAX(MEPE_TERM_DT)                               AS SPAN_TERM_DT,
    COUNT(*)                                        AS SOURCE_SPAN_COUNT,
    CASE WHEN COUNT(*) > 1 THEN TRUE ELSE FALSE END AS HAD_OVERLAP
FROM grouped
GROUP BY MEME_ID, MEPE_PLAN_TYPE, PLAN_TYPE_DESC, span_group
