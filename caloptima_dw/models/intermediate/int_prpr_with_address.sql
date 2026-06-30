-- Joins the primary (addr_rank=1) practice address to each provider.
SELECT
    p.*,
    a.PRAD_ADDR1        AS PRACTICE_ADDR1,
    a.PRAD_ADDR2        AS PRACTICE_ADDR2,
    a.PRAD_CITY         AS PRACTICE_CITY,
    a.PRAD_STATE        AS PRACTICE_STATE,
    a.PRAD_ZIP          AS PRACTICE_ZIP
FROM {{ ref('int_prpr_dedup') }} p
LEFT JOIN {{ ref('stg_prad_address') }} a
    ON  p.PRPR_ID   = a.PRPR_ID
    AND a.addr_rank = 1
