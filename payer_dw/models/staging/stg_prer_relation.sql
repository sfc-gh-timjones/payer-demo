WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_PRER_RELATION') }}
)
SELECT
    PRER_ID,
    PRPR_ID,
    PRER_PRPR_ID,
    PRER_EFF_DT,
    PRER_TERM_DT,
    CASE
        WHEN PRER_TERM_DT IS NULL OR PRER_TERM_DT >= CURRENT_DATE
        THEN TRUE ELSE FALSE
    END                             AS IS_ACTIVE_LINK,
    PRER_PRPR_ENTITY,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at,
    _SNOWFLAKE_DELETED              AS IS_DELETED
FROM source
