WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_PRPR_PROV') }}
)
SELECT
    PRPR_ID,
    PRPR_NPI,
    CASE
        WHEN PRPR_NPI REGEXP '^[0-9]{10}$' THEN TRUE
        ELSE FALSE
    END                                                              AS NPI_VALID,
    PRPR_NAME,
    PRPR_ENTITY,
    CASE PRPR_ENTITY
        WHEN 'I' THEN 'Individual (Type 1)'
        WHEN 'O' THEN 'Organization (Type 2)'
        ELSE 'Unknown'
    END                                                              AS PROVIDER_TYPE,
    PRPR_STS,
    CASE PRPR_STS
        WHEN 'AC' THEN 'Active'
        WHEN 'IN' THEN 'Inactive'
        WHEN 'SU' THEN 'Suspended'
        ELSE PRPR_STS
    END                                                              AS STATUS_DESC,
    PRPR_MCTR_TYPE,
    CASE PRPR_MCTR_TYPE
        WHEN 'FFS'      THEN 'Fee for Service'
        WHEN 'CAP'      THEN 'Capitation'
        WHEN 'PER_DIEM' THEN 'Per Diem'
        ELSE PRPR_MCTR_TYPE
    END                                                              AS CONTRACT_TYPE,
    PRPR_TAXONOMY_CD,
    PRPR_TERM_DT                                                     AS TERM_DT,
    TO_VARCHAR(ROW_HASH_VALUE)                                       AS ROW_HASH_HEX,
    SYS_USUS_ID,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_INSERTED_AT,
    _SNOWFLAKE_UPDATED_AT                                            AS updated_at,
    _SNOWFLAKE_DELETED                                               AS IS_DELETED
FROM source
