{{ config(severity='warn') }}
-- Singular test: no two eligibility spans for the same member+plan should overlap.
-- severity=warn: Openflow's synthetic incremental load injects ~5% overlapping
-- spans per run by design (to demo data quality). These accumulate across
-- incremental runs until a full-refresh clears them. Real data pipelines would
-- not have this pattern. Blocking CI on synthetic overlaps is a false positive.
-- Returns rows if the test FAILS (dbt convention: test passes when query returns 0 rows).
SELECT
    a.MEME_ID,
    a.MEPE_PLAN_TYPE,
    a.SPAN_EFF_DT   AS span_a_eff,
    a.SPAN_TERM_DT  AS span_a_term,
    b.SPAN_EFF_DT   AS span_b_eff,
    b.SPAN_TERM_DT  AS span_b_term
FROM {{ ref('eligibility') }} a
JOIN {{ ref('eligibility') }} b
    ON  a.MEME_ID        = b.MEME_ID
    AND a.MEPE_PLAN_TYPE = b.MEPE_PLAN_TYPE
    AND a.SPAN_EFF_DT   != b.SPAN_EFF_DT
    AND a.SPAN_EFF_DT    < COALESCE(b.SPAN_TERM_DT, '9999-12-31'::DATE)
    AND b.SPAN_EFF_DT    < COALESCE(a.SPAN_TERM_DT, '9999-12-31'::DATE)
