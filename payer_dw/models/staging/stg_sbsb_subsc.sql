WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_SBSB_SUBSC') }}
    WHERE {{ active_records() }}
)
SELECT
    SBSB_ID,
    SBSB_LAST_NAME,
    SBSB_FIRST_NAME,
    SBSB_DOB,
    SBSB_SEX,
    CASE SBSB_SEX
        WHEN 'M' THEN 'Male'
        WHEN 'F' THEN 'Female'
        WHEN 'U' THEN 'Unknown'
        ELSE SBSB_SEX
    END                             AS SEX_DESC,
    SBSB_STS,
    CASE SBSB_STS
        WHEN 'AC' THEN 'Active'
        WHEN 'IN' THEN 'Inactive'
        WHEN 'SU' THEN 'Suspended'
        ELSE SBSB_STS
    END                             AS STATUS_DESC,
    SBSB_MCTR_TYPE,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at
FROM source
