WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_NWPR_RELATION') }}
    WHERE {{ active_records() }}
)
SELECT
    PRPR_ID,
    NWNW_ID,
    NWPR_EFF_DT,
    NWPR_TERM_DT,
    CASE
        WHEN NWPR_TERM_DT IS NULL OR NWPR_TERM_DT >= CURRENT_DATE
        THEN TRUE ELSE FALSE
    END                             AS IS_ACTIVE_PARTICIPATION,
    NWPR_STS,
    CASE NWPR_STS
        WHEN 'AC' THEN 'Active'
        WHEN 'IN' THEN 'Inactive'
        ELSE NWPR_STS
    END                             AS STATUS_DESC,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at
FROM source
