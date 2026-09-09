WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_PRAD_ADDRESS') }}
),
ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PRPR_ID
            ORDER BY
                CASE WHEN PRAD_TYPE = 'PR' THEN 0 ELSE 1 END,
                PRAD_ID
        ) AS addr_rank
    FROM source
)
SELECT
    PRAD_ID,
    PRPR_ID,
    PRAD_TYPE,
    CASE PRAD_TYPE
        WHEN 'PR' THEN 'Primary Practice'
        WHEN 'RM' THEN 'Remit'
        WHEN 'ML' THEN 'Mailing'
        ELSE PRAD_TYPE
    END                             AS ADDRESS_TYPE_DESC,
    PRAD_ADDR1,
    PRAD_ADDR2,
    PRAD_CITY,
    PRAD_ST                         AS PRAD_STATE,
    PRAD_ZIP,
    addr_rank,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at,
    _SNOWFLAKE_DELETED              AS IS_DELETED
FROM ranked
