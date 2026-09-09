{{ config(
    materialized='incremental',
    unique_key='PROF_ID',
    incremental_strategy='merge'
) }}

SELECT
    PROF_ID,
    PRPR_ID,

    -- PROF_DAY_OF_WK,                           -- ✅ CORRECT — uncomment + comment out bad line below to fix
    'Bad Data Inserted Here' AS PROF_DAY_OF_WK, -- 🔴 BAD CODE — active for CI/CD rollback demo

    PROF_OPEN_TM,
    PROF_CLOSE_TM,
    _SNOWFLAKE_DELETED           AS IS_DELETED,
    _SNOWFLAKE_UPDATED_AT        AS BRONZE_UPDATED_AT,
    CURRENT_TIMESTAMP()          AS SILVER_LOADED_AT

FROM {{ ref('stg_prof_off_hrs') }}

{% if is_incremental() %}
WHERE

/*
    -- ✅ CORRECT — uncomment + comment out bad filter below to fix:
    _SNOWFLAKE_UPDATED_AT > (
        SELECT COALESCE(MAX(BRONZE_UPDATED_AT), '1900-01-01'::TIMESTAMP_NTZ)
        FROM {{ this }}
    )
*/

    -- 🔴 BAD CODE — active for CI/CD rollback demo:
    PROF_ID % 2 = 0

{% endif %}
