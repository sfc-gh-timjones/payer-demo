-- =============================================================
-- CalOptima Agent Demo - Step 3: Semantic View
-- FACETS_PROD.AGENTS.CALOPTIMA_MEMBER_SV
-- Based on the flat MEMBER_ENROLLMENT view (1 row per member)
-- =============================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE WH_XS;
USE SCHEMA FACETS_PROD.AGENTS;

-- DDL note: LEFT side of AS = user-facing semantic name
--           RIGHT side of AS = physical column or expression
-- Single quotes inside VQR SQL strings must be escaped as ''

CREATE OR REPLACE SEMANTIC VIEW FACETS_PROD.AGENTS.CALOPTIMA_MEMBER_SV
  TABLES (
    member_enrollment AS FACETS_PROD.AGENTS.MEMBER_ENROLLMENT
      PRIMARY KEY (MEME_ID)
  )
  FACTS (
    member_enrollment.meme_id           AS MEME_ID,
    member_enrollment.duplicate_count   AS DUPLICATE_COUNT,
    member_enrollment.source_span_count AS SOURCE_SPAN_COUNT,
    member_enrollment.active_network_count AS ACTIVE_NETWORK_COUNT
  )
  DIMENSIONS (
    member_enrollment.member_status          AS MEMBER_STATUS,
    member_enrollment.relationship_desc      AS RELATIONSHIP_DESC,
    member_enrollment.meme_rel_cd            AS MEME_REL_CD,
    member_enrollment.sex_desc               AS SEX_DESC,
    member_enrollment.meme_mctr_type         AS MEME_MCTR_TYPE,
    member_enrollment.mepe_plan_type         AS MEPE_PLAN_TYPE,
    member_enrollment.plan_type_desc         AS PLAN_TYPE_DESC,
    member_enrollment.mecd_aid_cd            AS MECD_AID_CD,
    member_enrollment.has_active_eligibility AS HAS_ACTIVE_ELIGIBILITY,
    member_enrollment.had_overlap            AS HAD_OVERLAP,
    member_enrollment.active_pcp_type        AS ACTIVE_PCP_TYPE,
    member_enrollment.pcp_provider_type      AS PCP_PROVIDER_TYPE,
    member_enrollment.pcp_contract_type      AS PCP_CONTRACT_TYPE,
    member_enrollment.pcp_city               AS PCP_CITY,
    member_enrollment.pcp_state              AS PCP_STATE,
    member_enrollment.is_pcp_eligible        AS IS_PCP_ELIGIBLE
  )
  METRICS (
    member_enrollment.total_members    AS COUNT(member_enrollment.MEME_ID),
    member_enrollment.active_members   AS COUNT_IF(member_enrollment.MEMBER_STATUS = 'Active'),
    member_enrollment.members_with_pcp AS COUNT_IF(member_enrollment.ACTIVE_PCP_PRPR_ID IS NOT NULL)
  )
  COMMENT = 'CalOptima member enrollment, plan assignment, and PCP attribution — Orange County, CA'
  AI_SQL_GENERATION
    'CalOptima Health is a Medi-Cal managed care plan serving Orange County, CA.
     This semantic view covers member enrollment at member grain (one row per member).
     Plan types: HMO (Health Maintenance Organization), DSNP (Dual Special Needs Plan),
     MEDICAID, PPO (Preferred Provider Organization), EPO.
     MEMBER_STATUS = ''Active'' for currently enrolled members.
     ACTIVE_PCP_PRPR_ID IS NULL means no PCP has been assigned.
     MECD_AID_CD is the Medicaid aid category code.
     PCP_CITY and PCP_STATE reflect the PCP''s practice location (all in Orange County, CA).
     RELATIONSHIP_DESC values: Subscriber, Spouse, Child, Other Dependent.
     HAS_ACTIVE_ELIGIBILITY = TRUE means the member has at least one active eligibility span.'
  AI_QUESTION_CATEGORIZATION
    'This semantic view covers quantitative questions about member counts, plan enrollment,
     PCP assignment rates, Medicaid aid categories, and demographic breakdowns.
     Route to this tool for any question involving counts, percentages, or distributions
     across member, plan, PCP, or geographic dimensions.'
  AI_VERIFIED_QUERIES (

    active_enrollment_by_plan_type AS (
      QUESTION 'How many active members are enrolled in each plan type?'
      SQL 'SELECT member_enrollment.PLAN_TYPE_DESC, member_enrollment.MEPE_PLAN_TYPE,
                  COUNT(*) AS member_count
           FROM member_enrollment
           WHERE member_enrollment.MEMBER_STATUS = ''Active''
             AND member_enrollment.MEPE_PLAN_TYPE IS NOT NULL
           GROUP BY 1, 2
           ORDER BY 3 DESC'
      ONBOARDING_QUESTION TRUE
    ),

    pcp_assignment_rate AS (
      QUESTION 'What percentage of active members have a PCP assigned?'
      SQL 'SELECT COUNT(*) AS total_active_members,
                  COUNT(member_enrollment.ACTIVE_PCP_PRPR_ID) AS members_with_pcp,
                  ROUND(COUNT(member_enrollment.ACTIVE_PCP_PRPR_ID) / COUNT(*) * 100, 2)
                    AS pcp_assignment_pct
           FROM member_enrollment
           WHERE member_enrollment.MEMBER_STATUS = ''Active'''
      ONBOARDING_QUESTION TRUE
    ),

    active_members_by_aid_category AS (
      QUESTION 'How many active members are in each Medicaid aid category?'
      SQL 'SELECT member_enrollment.MECD_AID_CD,
                  COUNT(*) AS member_count
           FROM member_enrollment
           WHERE member_enrollment.MEMBER_STATUS = ''Active''
             AND member_enrollment.MECD_AID_CD IS NOT NULL
           GROUP BY 1
           ORDER BY 2 DESC'
      ONBOARDING_QUESTION FALSE
    ),

    active_members_by_pcp_city AS (
      QUESTION 'Which cities have the most active members assigned to PCPs?'
      SQL 'SELECT member_enrollment.PCP_CITY,
                  member_enrollment.PCP_STATE,
                  COUNT(*) AS member_count
           FROM member_enrollment
           WHERE member_enrollment.MEMBER_STATUS = ''Active''
             AND member_enrollment.PCP_CITY IS NOT NULL
           GROUP BY 1, 2
           ORDER BY 3 DESC'
      ONBOARDING_QUESTION TRUE
    ),

    enrollment_by_relationship_type AS (
      QUESTION 'What is the breakdown of active members by relationship type?'
      SQL 'SELECT member_enrollment.RELATIONSHIP_DESC,
                  COUNT(*) AS member_count
           FROM member_enrollment
           WHERE member_enrollment.MEMBER_STATUS = ''Active''
           GROUP BY 1
           ORDER BY 2 DESC'
      ONBOARDING_QUESTION FALSE
    )

  );
