WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_MECD_MEDICAID') }}
)
SELECT
    MEME_ID,
    MECD_AID_CD,
    MECD_BIC,
    MECD_EFF_DT,
    MECD_TERM_DT,
    CASE
        WHEN MECD_TERM_DT IS NULL OR MECD_TERM_DT >= CURRENT_DATE
        THEN TRUE ELSE FALSE
    END                             AS IS_ACTIVE_MEDICAID,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at,
    _SNOWFLAKE_DELETED              AS IS_DELETED
FROM source
