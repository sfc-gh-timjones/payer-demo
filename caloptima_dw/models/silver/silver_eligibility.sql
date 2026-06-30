{{ config(
    materialized='incremental',
    unique_key=['MEME_ID', 'MEPE_PLAN_TYPE', 'SPAN_EFF_DT'],
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
) }}

SELECT
    e.MEME_ID,
    e.MEPE_PLAN_TYPE,
    e.PLAN_TYPE_DESC,
    e.SPAN_EFF_DT,
    e.SPAN_TERM_DT,
    e.SOURCE_SPAN_COUNT,
    e.HAD_OVERLAP,
    CASE
        WHEN e.SPAN_TERM_DT IS NULL OR e.SPAN_TERM_DT >= CURRENT_DATE
        THEN TRUE ELSE FALSE
    END                                     AS IS_ACTIVE,
    CURRENT_TIMESTAMP()                     AS SILVER_LOADED_AT
FROM {{ ref('int_mepe_span_normalize') }} e
{% if is_incremental() %}
WHERE e.MEME_ID IN (
    SELECT DISTINCT MEME_ID
    FROM {{ source('raw', 'CMC_MEPE_PRCS_ELIG') }}
    WHERE _SNOWFLAKE_UPDATED_AT > (
        SELECT COALESCE(MAX(SILVER_LOADED_AT), '1900-01-01'::TIMESTAMP_NTZ)
        FROM {{ this }}
    )
)
{% endif %}
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY e.MEME_ID, e.MEPE_PLAN_TYPE, e.SPAN_EFF_DT
    ORDER BY e.SOURCE_SPAN_COUNT DESC
) = 1
