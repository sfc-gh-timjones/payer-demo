WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_MEPR_PRIM_PROV') }}
)
SELECT
    MEME_ID,
    PRPR_ID,
    MEPR_EFF_DT,
    MEPR_TERM_DT,
    CASE
        WHEN MEPR_TERM_DT IS NULL THEN TRUE
        ELSE FALSE
    END                             AS IS_ACTIVE_PCP,
    MEPR_PCP_TYPE,
    CASE MEPR_PCP_TYPE
        WHEN 'PC' THEN 'Primary Care Physician'
        WHEN 'OB' THEN 'OB/GYN'
        WHEN 'PE' THEN 'Pediatrician'
        ELSE MEPR_PCP_TYPE
    END                             AS PCP_TYPE_DESC,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at,
    _SNOWFLAKE_DELETED              AS IS_DELETED
FROM source
