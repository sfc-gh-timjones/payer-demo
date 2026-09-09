-- =============================================================
-- Payer Agent Demo - Step 2: MEMBER_ENROLLMENT flat view
-- Joins MEMBER + ELIGIBILITY (deduped) + PROVIDER into 1 row/member
-- =============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;
USE SCHEMA FACETS_PROD.AGENTS;

-- MEMBER  → ELIGIBILITY: 1-to-many (avg ~1.5 spans/member).
-- ROW_NUMBER dedup picks the most recent active span per member;
-- falls back to most recent inactive span if no active spans exist.
-- MEMBER  → PROVIDER: many-to-1 via ACTIVE_PCP_PRPR_ID.
-- Result: 105,843 rows — one per member, zero fanout.

CREATE OR REPLACE VIEW FACETS_PROD.AGENTS.MEMBER_ENROLLMENT AS
WITH ranked_eligibility AS (
  SELECT
    MEME_ID,
    MEPE_PLAN_TYPE,
    PLAN_TYPE_DESC,
    SPAN_EFF_DT,
    SPAN_TERM_DT,
    HAD_OVERLAP,
    IS_ACTIVE,
    SOURCE_SPAN_COUNT,
    ROW_NUMBER() OVER (
      PARTITION BY MEME_ID
      ORDER BY IS_ACTIVE DESC, SPAN_EFF_DT DESC
    ) AS rn
  FROM FACETS_DEV.SILVER.ELIGIBILITY
)
SELECT
  -- Member identity
  m.MEME_ID,
  m.SBSB_ID,
  m.MEME_FIRST_NAME,
  m.MEME_LAST_NAME,
  m.MEME_DOB,
  -- Relationship / demographics
  m.RELATIONSHIP_DESC,
  m.MEME_REL_CD,
  m.SEX_DESC,
  m.MEME_SEX,
  m.MEMBER_STATUS,
  m.MEME_MCTR_TYPE,
  -- Medicaid
  m.MECD_AID_CD,
  m.MEDICAID_EFF_DT,
  m.MEDICAID_TERM_DT,
  -- PCP assignment
  m.ACTIVE_PCP_PRPR_ID,
  m.ACTIVE_PCP_NAME,
  m.ACTIVE_PCP_NPI,
  m.PCP_EFF_DT,
  m.ACTIVE_PCP_TYPE,
  m.DUPLICATE_COUNT,
  -- Active plan (deduped from ELIGIBILITY — latest active span per member)
  e.MEPE_PLAN_TYPE,
  e.PLAN_TYPE_DESC,
  e.SPAN_EFF_DT,
  e.SPAN_TERM_DT,
  e.HAD_OVERLAP,
  e.IS_ACTIVE       AS HAS_ACTIVE_ELIGIBILITY,
  e.SOURCE_SPAN_COUNT,
  -- PCP provider info (IS_CURRENT = TRUE only)
  p.PRPR_NAME       AS PCP_PRPR_NAME,
  p.PROVIDER_TYPE   AS PCP_PROVIDER_TYPE,
  p.CONTRACT_TYPE   AS PCP_CONTRACT_TYPE,
  p.PRACTICE_CITY   AS PCP_CITY,
  p.PRACTICE_STATE  AS PCP_STATE,
  p.PRACTICE_ZIP    AS PCP_ZIP,
  p.IS_PCP_ELIGIBLE,
  p.ACTIVE_NETWORK_COUNT
FROM FACETS_DEV.SILVER.MEMBER m
LEFT JOIN ranked_eligibility e
  ON m.MEME_ID = e.MEME_ID AND e.rn = 1
LEFT JOIN FACETS_DEV.SILVER.PROVIDER p
  ON m.ACTIVE_PCP_PRPR_ID = p.PRPR_ID AND p.IS_CURRENT = TRUE;
