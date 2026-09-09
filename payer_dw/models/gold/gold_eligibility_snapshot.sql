{{
    config(
        materialized = 'view',
        tags         = ['gold', 'phase-1-scaffold']
    )
}}

/*
  Gold scaffold — Phase 1 architecture placeholder.

  Phase 2 implementation:
  gold_eligibility_snapshot will filter SILVER.ELIGIBILITY to currently active
  spans (SPAN_TERM_DT IS NULL or > CURRENT_DATE) and join member demographics
  and plan attributes. The model will expose: member ID, plan type, effective
  date, benefit package, and Medi-Cal aid category. It will serve as the
  authoritative "who is covered today" table for claims adjudication, encounter
  reporting, and regulatory eligibility attestation.
*/

SELECT
    'Phase 2: gold_eligibility_snapshot will filter SILVER.ELIGIBILITY to '     ||
    'active spans and join SILVER.MEMBER for a complete, point-in-time '        ||
    'coverage view. Will power claims adjudication, encounter reporting, '      ||
    'and regulatory eligibility attestation to DHCS and CMS.'
    AS model_description
