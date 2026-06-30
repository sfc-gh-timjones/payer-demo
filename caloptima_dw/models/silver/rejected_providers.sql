{{ config(
    materialized='incremental',
    unique_key='PRPR_ID',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
) }}

-- Providers rejected from Silver due to invalid or missing NPI.
-- When NPI is corrected in Facets, the next dbt run removes the row from here
-- and the provider flows to SILVER.PROVIDER via int_prpr_dedup.
SELECT
    PRPR_ID,
    PRPR_NPI,
    PRPR_NAME,
    PRPR_ENTITY,
    PRPR_STS,
    CASE
        WHEN PRPR_NPI IS NULL THEN 'NPI_NULL'
        ELSE 'NPI_INVALID'
    END                         AS REJECTION_RULE,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT       AS BRONZE_UPDATED_AT,
    CURRENT_TIMESTAMP()         AS QUARANTINE_DTM
FROM {{ source('raw', 'CMC_PRPR_PROV') }}
WHERE _SNOWFLAKE_DELETED = FALSE
  AND (PRPR_NPI IS NULL OR NOT (PRPR_NPI REGEXP '^[0-9]{10}$'))
{% if is_incremental() %}
  AND _SNOWFLAKE_UPDATED_AT > (
      SELECT COALESCE(MAX(BRONZE_UPDATED_AT), '1900-01-01'::TIMESTAMP_NTZ)
      FROM {{ this }}
  )
{% endif %}
