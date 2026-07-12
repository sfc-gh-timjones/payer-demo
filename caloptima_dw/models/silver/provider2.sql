{{ config(
    materialized='incremental',
    unique_key='PRPR_ID',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
) }}

/*
  Current-state provider model — simple merge on PRPR_ID, no SCD2 history.
  Optimized for queries that only need today's data (Agent, Gold views, reporting).
  Use this when you don't need history and want to avoid filtering dbt_valid_to IS NULL.

  For full SCD2 history with enriched columns: query SILVER.PROVIDER (view).
  For raw SCD2 history only:                   query SILVER.PROVIDER_SNAPSHOT.
*/

SELECT
    PRPR_ID,
    PRPR_NPI,
    PRPR_NAME,
    PROVIDER_TYPE,
    PRPR_ENTITY,
    STATUS_DESC,
    PRPR_STS,
    CONTRACT_TYPE,
    PRPR_MCTR_TYPE,
    PRPR_TAXONOMY_CD,
    PRACTICE_ADDR1,
    PRACTICE_ADDR2,
    PRACTICE_CITY,
    PRACTICE_STATE,
    PRACTICE_ZIP,
    ACTIVE_NETWORK_COUNT,
    IS_PCP_ELIGIBLE,
    CONTRACT_TYPES,
    PARENT_ORG_PRPR_ID,
    PARENT_ORG_NAME,
    TERM_DT,
    DUPLICATE_COUNT,
    IS_DELETED,
    updated_at                  AS BRONZE_UPDATED_AT,
    CURRENT_TIMESTAMP()         AS SILVER_LOADED_AT
FROM {{ ref('int_prpr_org_hierarchy') }}
WHERE IS_DUPLICATE = FALSE
{% if is_incremental() %}
    AND updated_at > (
        SELECT COALESCE(MAX(BRONZE_UPDATED_AT), '1900-01-01'::TIMESTAMP_NTZ)
        FROM {{ this }}
    )
{% endif %}
