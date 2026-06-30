{{ config(
    materialized='incremental',
    unique_key='PROVIDER_SK',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
) }}

{% if is_incremental() %}

WITH source AS (
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
        p.ACTIVE_NETWORK_COUNT,
        p.IS_PCP_ELIGIBLE::BOOLEAN  AS IS_PCP_ELIGIBLE,
        p.CONTRACT_TYPES,
        p.PARENT_ORG_PRPR_ID,
        p.PARENT_ORG_NAME,
        p.TERM_DT,
        p.DUPLICATE_COUNT,
        p.ROW_HASH_HEX,
        p.SYS_LAST_UPD_DTM,
        p.updated_at
    FROM {{ ref('int_prpr_org_hierarchy') }} p
    WHERE p.IS_DUPLICATE = FALSE
),

-- Providers that are new or updated in Bronze since last run
changed AS (
    SELECT s.*
    FROM source s
    LEFT JOIN {{ this }} t
        ON  s.PRPR_ID = t.PRPR_ID
        AND t.IS_CURRENT = TRUE
    WHERE t.PRPR_ID IS NULL
       OR s.updated_at > t.BRONZE_UPDATED_AT
),

-- Close the existing open row (same PROVIDER_SK → MERGE updates it)
rows_to_close AS (
    SELECT
        t.PROVIDER_SK,
        t.PRPR_ID,
        t.PRPR_NPI,
        t.PRPR_NAME,
        t.PROVIDER_TYPE,
        t.PRPR_ENTITY,
        t.STATUS_DESC,
        t.PRPR_STS,
        t.CONTRACT_TYPE,
        t.PRPR_MCTR_TYPE,
        t.PRPR_TAXONOMY_CD,
        t.PRACTICE_ADDR1,
        t.PRACTICE_ADDR2,
        t.PRACTICE_CITY,
        t.PRACTICE_STATE,
        t.PRACTICE_ZIP,
        t.ACTIVE_NETWORK_COUNT,
        t.IS_PCP_ELIGIBLE,
        t.CONTRACT_TYPES,
        t.PARENT_ORG_PRPR_ID,
        t.PARENT_ORG_NAME,
        t.TERM_DT,
        t.DUPLICATE_COUNT,
        t.ROW_HASH_HEX,
        t.SYS_LAST_UPD_DTM,
        t.EFFECTIVE_FROM,
        c.updated_at        AS EFFECTIVE_TO,
        FALSE               AS IS_CURRENT,
        t.BRONZE_UPDATED_AT,
        CURRENT_TIMESTAMP() AS SILVER_LOADED_AT
    FROM {{ this }} t
    JOIN changed c
        ON  t.PRPR_ID = c.PRPR_ID
        AND t.IS_CURRENT = TRUE
        AND t.BRONZE_UPDATED_AT < c.updated_at
),

-- Insert new open row for each changed provider (new PROVIDER_SK → MERGE inserts)
new_rows AS (
    SELECT
        MD5(PRPR_ID::VARCHAR || '|' || updated_at::VARCHAR) AS PROVIDER_SK,
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
        ROW_HASH_HEX,
        SYS_LAST_UPD_DTM,
        updated_at          AS EFFECTIVE_FROM,
        NULL::TIMESTAMP_NTZ AS EFFECTIVE_TO,
        TRUE                AS IS_CURRENT,
        updated_at          AS BRONZE_UPDATED_AT,
        CURRENT_TIMESTAMP() AS SILVER_LOADED_AT
    FROM changed
)

SELECT * FROM rows_to_close
UNION ALL
SELECT * FROM new_rows

{% else %}

-- Full refresh: all providers as a single IS_CURRENT=TRUE version
SELECT
    MD5(p.PRPR_ID::VARCHAR || '|' || p.updated_at::VARCHAR) AS PROVIDER_SK,
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
    p.ACTIVE_NETWORK_COUNT,
    p.IS_PCP_ELIGIBLE::BOOLEAN  AS IS_PCP_ELIGIBLE,
    p.CONTRACT_TYPES,
    p.PARENT_ORG_PRPR_ID,
    p.PARENT_ORG_NAME,
    p.TERM_DT,
    p.DUPLICATE_COUNT,
    p.ROW_HASH_HEX,
    p.SYS_LAST_UPD_DTM,
    p.updated_at            AS EFFECTIVE_FROM,
    NULL::TIMESTAMP_NTZ     AS EFFECTIVE_TO,
    TRUE                    AS IS_CURRENT,
    p.updated_at            AS BRONZE_UPDATED_AT,
    CURRENT_TIMESTAMP()     AS SILVER_LOADED_AT
FROM {{ ref('int_prpr_org_hierarchy') }} p
WHERE p.IS_DUPLICATE = FALSE

{% endif %}
