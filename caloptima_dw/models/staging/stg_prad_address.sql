WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_PRAD_ADDRESS') }}
    WHERE {{ active_records() }}
),
primary_address AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PRPR_ID
            ORDER BY
                CASE WHEN PRAD_TYPE = 'PR' THEN 0 ELSE 1 END,
                PRAD_SEQ_NO
        ) AS addr_rank
    FROM source
)
SELECT
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
    PRAD_STATE,
    PRAD_ZIP,
    PRAD_COUNTY,
    PRAD_PHONE,
    PRAD_FAX,
    PRAD_STS,
    CASE PRAD_STS
        WHEN 'AC' THEN 'Active'
        WHEN 'IN' THEN 'Inactive'
        ELSE PRAD_STS
    END                             AS STATUS_DESC,
    addr_rank,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at
FROM primary_address
