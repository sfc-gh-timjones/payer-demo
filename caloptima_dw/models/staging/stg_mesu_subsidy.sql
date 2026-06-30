WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_MESU_SUBSIDY') }}
    WHERE {{ active_records() }}
)
SELECT
    MESU_ID,
    MEME_ID,
    MESU_EFF_DT,
    MESU_TERM_DT,
    CASE
        WHEN MESU_TERM_DT IS NULL OR MESU_TERM_DT >= CURRENT_DATE
        THEN TRUE ELSE FALSE
    END                             AS IS_ACTIVE_SUBSIDY,
    MESU_SUBSIDY_AMT,
    MESU_PREMIUM_AMT,
    MESU_SUBSIDY_TYPE,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at
FROM source
