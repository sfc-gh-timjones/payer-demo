{{
    config(
        materialized = 'view',
        tags         = ['gold', 'phase-1-scaffold']
    )
}}

/*
  Gold scaffold — Phase 1 architecture placeholder.

  Phase 2 implementation:
  gold_member_enrollment will produce one row per active CalOptima member by
  joining SILVER.MEMBER with active SILVER.ELIGIBILITY spans. The model will
  expose: enrollment status, plan type (COMM / D-SNP / Medi-Cal), PCP
  attribution, Medi-Cal BIC, and effective/termination dates. It will serve as
  the primary input for member roster exports, care management workflows, and
  enrollment dashboards.
*/

SELECT
    'Phase 2: gold_member_enrollment will join SILVER.MEMBER + active '         ||
    'SILVER.ELIGIBILITY spans (MEPE_TERM_DT IS NULL or future) to produce '     ||
    'one analytics-ready row per enrolled member with plan type, PCP, '         ||
    'and Medi-Cal eligibility attributes. Powers member roster reporting '       ||
    'and care management workflows.'
    AS model_description
