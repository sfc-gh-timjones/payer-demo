WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_AGAG_AGREEMENT') }}
    WHERE {{ active_records() }}
)
SELECT
    AGAG_ID,
    PRPR_ID,
    NWNW_ID,
    AGAG_EFF_DT,
    AGAG_TERM_DT,
    CASE
        WHEN AGAG_TERM_DT IS NULL OR AGAG_TERM_DT >= CURRENT_DATE
        THEN TRUE ELSE FALSE
    END                             AS IS_ACTIVE_AGREEMENT,
    AGAG_MCTR_TYPE,
    CASE AGAG_MCTR_TYPE
        WHEN 'FFS'      THEN 'Fee for Service'
        WHEN 'CAP'      THEN 'Capitation'
        WHEN 'PER_DIEM' THEN 'Per Diem'
        ELSE AGAG_MCTR_TYPE
    END                             AS CONTRACT_TYPE_DESC,
    AGAG_STS,
    CASE AGAG_STS
        WHEN 'AC' THEN 'Active'
        WHEN 'IN' THEN 'Inactive'
        ELSE AGAG_STS
    END                             AS STATUS_DESC,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at
FROM source
