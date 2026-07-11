WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_MEPE_PRCS_ELIG') }}
)
SELECT
    MEPE_ID,
    MEME_ID,
    SBSB_ID,
    CSPI_ID,
    MEPE_EFF_DT,
    MEPE_TERM_DT,
    CASE
        WHEN MEPE_TERM_DT IS NULL OR MEPE_TERM_DT >= CURRENT_DATE
        THEN TRUE ELSE FALSE
    END                             AS IS_ACTIVE_SPAN,
    MEPE_STS,
    CASE MEPE_STS
        WHEN 'AC' THEN 'Active'
        WHEN 'IN' THEN 'Inactive'
        ELSE MEPE_STS
    END                             AS STATUS_DESC,
    MEPE_PLAN_TYPE,
    CASE MEPE_PLAN_TYPE
        WHEN 'HMO'      THEN 'Health Maintenance Organization'
        WHEN 'PPO'      THEN 'Preferred Provider Organization'
        WHEN 'MEDICAID' THEN 'Medicaid'
        WHEN 'DSNP'     THEN 'Dual Special Needs Plan'
        ELSE MEPE_PLAN_TYPE
    END                             AS PLAN_TYPE_DESC,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at,
    _SNOWFLAKE_DELETED              AS IS_DELETED
FROM source
