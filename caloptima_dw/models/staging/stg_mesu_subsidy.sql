WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_MESU_SUBSIDY') }}
    WHERE {{ active_records() }}
)
SELECT
    MEME_ID,
    SBSB_ID,
    MESU_EFF_DT,
    MESU_TERM_DT,
    CASE
        WHEN MESU_TERM_DT IS NULL OR MESU_TERM_DT >= CURRENT_DATE
        THEN TRUE ELSE FALSE
    END                             AS IS_ACTIVE_SUBSIDY,
    MESU_APTC_AMT,
    MESU_PREM_AMT,
    MESU_NET_PREM_AMT,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at
FROM source
