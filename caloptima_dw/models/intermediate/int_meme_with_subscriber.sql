-- Joins deduplicated members to their subscriber record.
SELECT
    m.*,
    s.SBSB_LAST_NAME        AS SUBSCRIBER_LAST_NAME,
    s.SBSB_FIRST_NAME       AS SUBSCRIBER_FIRST_NAME,
    s.SBSB_DOB              AS SUBSCRIBER_DOB,
    s.STATUS_DESC           AS SUBSCRIBER_STATUS,
    s.SBSB_GRP_ID,
    s.SBSB_EFF_DT           AS SUBSCRIBER_EFF_DT,
    s.SBSB_TERM_DT          AS SUBSCRIBER_TERM_DT
FROM {{ ref('int_meme_dedup') }} m
LEFT JOIN {{ ref('stg_sbsb_subsc') }} s ON m.SBSB_ID = s.SBSB_ID
