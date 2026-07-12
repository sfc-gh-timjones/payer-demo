WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_PRNP_NPI') }}
)
SELECT
    PRNP_ID,
    PRPR_ID,
    PRNP_NPI,
    CASE
        WHEN PRNP_NPI REGEXP '^[0-9]{10}$' THEN TRUE
        ELSE FALSE
    END                             AS NPI_VALID,
    PRNP_NPI_TYPE,
    CASE PRNP_NPI_TYPE
        WHEN '1' THEN 'Individual'
        WHEN '2' THEN 'Organization'
        ELSE PRNP_NPI_TYPE
    END                             AS NPI_TYPE_DESC,
    PRNP_EFF_DT,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at,
    _SNOWFLAKE_DELETED              AS IS_DELETED
FROM source
