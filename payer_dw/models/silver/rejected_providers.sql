{{ config(materialized='table') }}

-- Rebuilt from scratch on every run so that rows disappear automatically
-- when a provider's NPI is corrected in the source system.
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
