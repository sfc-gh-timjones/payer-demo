{{ config(
    materialized='incremental',
    unique_key='PRPR_ID',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
) }}

SELECT
    p.PRPR_ID,
    p.PRPR_NPI,
    p.PRPR_NAME,
    p.PROVIDER_TYPE,
    p.PRPR_ENTITY,
    p.STATUS_DESC,
    p.PRPR_STS,
    p.CONTRACT_TYPE,
    p.PRPR_MCTR_TYPE,
    p.PRPR_TAXONOMY_CD,
    p.PRACTICE_ADDR1,
    p.PRACTICE_ADDR2,
    p.PRACTICE_CITY,
    p.PRACTICE_STATE,
    p.PRACTICE_ZIP,
    p.PRACTICE_COUNTY,
    p.PRACTICE_PHONE,
    p.ACTIVE_NETWORK_COUNT,
    p.IS_PCP_ELIGIBLE::BOOLEAN              AS IS_PCP_ELIGIBLE,
    p.CONTRACT_TYPES,
    p.PARENT_ORG_PRPR_ID,
    p.PARENT_ORG_NAME,
    p.TERM_DT,
    p.DUPLICATE_COUNT,
    p.ROW_HASH_HEX,
    p.SYS_LAST_UPD_DTM,
    p.updated_at                            AS BRONZE_UPDATED_AT,
    CURRENT_TIMESTAMP()                     AS SILVER_LOADED_AT
FROM {{ ref('int_prpr_org_hierarchy') }} p
WHERE p.IS_DUPLICATE = FALSE
{% if is_incremental() %}
    AND p.updated_at > (
        SELECT COALESCE(MAX(BRONZE_UPDATED_AT), '1900-01-01'::TIMESTAMP_NTZ)
        FROM {{ this }}
    )
{% endif %}
