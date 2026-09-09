{{
    config(
        materialized='incremental',
        unique_key='dbt_scd_id',
        incremental_strategy='merge',
        on_schema_change='sync_all_columns'
    )
}}

/*
  Enriched SCD2 provider history — the primary SILVER.PROVIDER consumer table.

  Architecture:
    SILVER.PROVIDER_SNAPSHOT  — raw SCD2 history (snapshot of stg_prpr_prov only,
                                 fully deterministic — no derived/joined columns)
         ↓ JOIN current enrichment (address, network, org hierarchy)
    SILVER.PROVIDER           — this view: full history + enriched columns

  SCD2 columns (added by dbt snapshot):
    dbt_valid_from   — when this version became current
    dbt_valid_to     — when superseded (NULL = current record)
    dbt_scd_id       — unique row hash

  To query current providers:  WHERE dbt_valid_to IS NULL
  To query point-in-time:      WHERE dbt_valid_from <= '<ts>'
                               AND  (dbt_valid_to IS NULL OR dbt_valid_to > '<ts>')

  Note: enriched columns (address, network, org) reflect CURRENT source state,
  not the state at the time of the historical snapshot row. For fully temporal
  enrichment, those attributes would need their own snapshot tables.

  Incremental strategy: merges on dbt_scd_id (snapshot's unique row hash).
  New snapshot rows (new provider versions) get inserted; updated enrichment
  on existing rows gets merged.
*/

SELECT
    -- SCD2 history columns
    snap.dbt_scd_id,
    snap.dbt_valid_from,
    snap.dbt_valid_to,
    snap.dbt_updated_at,

    -- Core provider fields (from snapshot — historically accurate)
    snap.PRPR_ID,
    snap.PRPR_NPI,
    snap.PRPR_NAME,
    snap.PROVIDER_TYPE,
    snap.PRPR_ENTITY,
    snap.STATUS_DESC,
    snap.PRPR_STS,
    snap.CONTRACT_TYPE,
    snap.PRPR_MCTR_TYPE,
    snap.PRPR_TAXONOMY_CD,
    snap.TERM_DT,
    snap.ROW_HASH_HEX,
    snap.SYS_LAST_UPD_DTM,
    snap.IS_DELETED,
    snap.updated_at             AS BRONZE_UPDATED_AT,

    -- Enriched columns (current state — from live joins)
    enriched.PRACTICE_ADDR1,
    enriched.PRACTICE_ADDR2,
    enriched.PRACTICE_CITY,
    enriched.PRACTICE_STATE,
    enriched.PRACTICE_ZIP,
    enriched.ACTIVE_NETWORK_COUNT,
    enriched.IS_PCP_ELIGIBLE,
    enriched.CONTRACT_TYPES,
    enriched.PARENT_ORG_PRPR_ID,
    enriched.PARENT_ORG_NAME,
    enriched.DUPLICATE_COUNT

FROM {{ ref('provider_snapshot') }} snap
LEFT JOIN {{ ref('int_prpr_org_hierarchy') }} enriched
    ON snap.PRPR_ID = enriched.PRPR_ID
{% if is_incremental() %}
WHERE snap.dbt_updated_at > (
    SELECT COALESCE(MAX(dbt_updated_at), '1900-01-01'::TIMESTAMP_NTZ)
    FROM {{ this }}
)
-- Also include rows that were just closed by the snapshot (dbt_valid_to was set).
-- The closed row's dbt_updated_at is its original source timestamp (old, won't
-- pass the filter above), but dbt_valid_to = new timestamp. Without this, the
-- old row in silver.provider keeps dbt_valid_to=NULL (looks current) even after
-- the snapshot closes it — causing assert_one_current_row_per_provider to fail.
OR (
    snap.dbt_valid_to IS NOT NULL
    AND snap.dbt_valid_to > (
        SELECT COALESCE(MAX(dbt_updated_at), '1900-01-01'::TIMESTAMP_NTZ)
        FROM {{ this }}
    )
)
{% endif %}
