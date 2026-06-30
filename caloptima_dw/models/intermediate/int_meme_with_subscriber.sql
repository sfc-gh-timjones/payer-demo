-- Joins deduplicated members to their subscriber record.
SELECT
    m.*,
    s.SBSB_LAST_NAME        AS SUBSCRIBER_LAST_NAME,
    s.SBSB_FIRST_NAME       AS SUBSCRIBER_FIRST_NAME,
    s.SBSB_DOB              AS SUBSCRIBER_DOB,
    s.STATUS_DESC           AS SUBSCRIBER_STATUS,
    s.SBSB_MCTR_TYPE        AS SUBSCRIBER_MCTR_TYPE
FROM {{ ref('int_meme_dedup') }} m
LEFT JOIN {{ ref('stg_sbsb_subsc') }} s ON m.SBSB_ID = s.SBSB_ID
