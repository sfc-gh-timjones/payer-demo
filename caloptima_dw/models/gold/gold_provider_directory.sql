{{
    config(
        materialized = 'view',
        tags         = ['gold', 'phase-1-scaffold']
    )
}}

/*
  Gold scaffold — Phase 1 architecture placeholder.

  Phase 2 implementation:
  gold_provider_directory will filter SILVER.PROVIDER2 to IS_DELETED = FALSE
  and join network participation, specialty, and address data. The model will
  expose: NPI, provider name, specialty, network status, address, and effective
  dates in a format suitable for member-facing provider directory lookups,
  network adequacy reporting, and prior authorization routing.

  Soft-delete filter required: WHERE NOT p.IS_DELETED
  For full history: query SILVER.PROVIDER (dbt snapshot) and filter dbt_valid_to IS NULL
*/

SELECT
    'Phase 2: gold_provider_directory will SELECT IS_CURRENT = TRUE rows from ' ||
    'SILVER.PROVIDER and join network participation and address data to produce ' ||
    'a clean, deduplicated in-network provider directory. Will power '           ||
    'member-facing provider search, network adequacy analysis, and '             ||
    'credentialing workflows.'
    AS model_description
