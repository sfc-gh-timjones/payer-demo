{% snapshot provider_snapshot %}

{{
    config(
        target_schema='SILVER',
        alias='PROVIDER_SNAPSHOT',
        strategy='timestamp',
        unique_key='PRPR_ID',
        updated_at='updated_at',
        invalidate_hard_deletes=True
    )
}}

/*
  dbt native SCD2 snapshot for the provider master.
  Sources directly from stg_prpr_prov (raw Bronze columns only) for deterministic behavior.

  Why not int_prpr_org_hierarchy:
    - PARENT_ORG_NAME is fetched via JOIN to stg_prpr_prov — if the org renames,
      PARENT_ORG_NAME changes without the individual provider's updated_at bumping,
      causing missed history rows.
    - ACTIVE_NETWORK_COUNT / IS_PCP_ELIGIBLE / CONTRACT_TYPES are derived from
      date-filtered joins (IS_ACTIVE_PARTICIPATION = TRUE uses CURRENT_DATE),
      so they can drift over time without source changes.
    - Enriched columns belong in silver/provider2.sql (current-state model).

  dbt adds these columns automatically:
    dbt_scd_id      — unique row hash (MD5 of key + updated_at)
    dbt_updated_at  — when this snapshot row was last processed
    dbt_valid_from  — when this version became current
    dbt_valid_to    — when this version was superseded (NULL = current record)

  To query current providers: WHERE dbt_valid_to IS NULL
  To query point-in-time:     WHERE dbt_valid_from <= '<ts>'
                                AND (dbt_valid_to IS NULL OR dbt_valid_to > '<ts>')

  Compare vs silver/provider_scd2_legacy.sql (custom MERGE approach):
    - Custom: EFFECTIVE_FROM / EFFECTIVE_TO / IS_CURRENT, 192 lines of MERGE logic
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
    TERM_DT,
    ROW_HASH_HEX,
    SYS_LAST_UPD_DTM,
    IS_DELETED,
    updated_at
FROM {{ ref('stg_prpr_prov') }}
WHERE NPI_VALID = TRUE    -- mirrors int_prpr_dedup: only track providers with valid NPIs

{% endsnapshot %}
