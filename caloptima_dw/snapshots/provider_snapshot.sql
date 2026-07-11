{% snapshot provider_snapshot %}

{{
    config(
        target_schema='SILVER',
        strategy='timestamp',
        unique_key='PRPR_ID',
        updated_at='updated_at',
        invalidate_hard_deletes=True
    )
}}

/*
  dbt native SCD2 snapshot for the provider master.

  dbt adds these columns automatically:
    dbt_scd_id      — unique row hash (MD5 of key + updated_at)
    dbt_updated_at  — when this snapshot row was last processed
    dbt_valid_from  — when this version became current
    dbt_valid_to    — when this version was superseded (NULL = current record)

  To query current providers: WHERE dbt_valid_to IS NULL
  To query a point-in-time:   WHERE dbt_valid_from <= '<ts>' AND (dbt_valid_to IS NULL OR dbt_valid_to > '<ts>')

  Compare vs silver/provider_scd2_legacy.sql (custom MERGE approach):
    - Custom: EFFECTIVE_FROM / EFFECTIVE_TO / IS_CURRENT, requires 192 lines of MERGE logic
    - Snapshot: dbt_valid_from / dbt_valid_to, ~15 lines of config
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
    updated_at
FROM {{ ref('int_prpr_org_hierarchy') }}
WHERE IS_DUPLICATE = FALSE

{% endsnapshot %}
