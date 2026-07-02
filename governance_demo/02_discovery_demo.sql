-- =============================================================================
-- FILE: 02_discovery_demo.sql
-- PURPOSE: CalOptima RFP 26-038 | Topic 4: Data Governance — Discovery
--          "Snowflake automatically finds and labels sensitive data in your
--           Facets PHI — no manual cataloging required."
--
-- AUDIENCE FLOW (3 beats):
--   Beat 1 → Show raw PHI: names, DOBs, Medi-Cal IDs all exposed
--   Beat 2 → Run AI classification: Snowflake tells us what's sensitive
--   Beat 3 → Create a copy: governance tags follow the data automatically
--
-- SETUP REFERENCE: 01_governance_setup.sql
--   Classification tag:     Section B, lines 77-100
--   Classification profile: Section B, lines 102-160
--   AI classification run:  Section C, lines 162-195
--   Tag propagation:        DATA_CLASSIFICATION tag PROPAGATE = ON_DEPENDENCY...
-- =============================================================================

USE ROLE DATA_GOVERNOR_ROLE;
USE WAREHOUSE WH_XS;
USE DATABASE zFACETS_DEV_CLONE;
USE SCHEMA SILVER;


-- =============================================================================
-- BEAT 1: THE PROBLEM — RAW PHI IS FULLY EXPOSED
-- "Let's look at what a CalOptima member record looks like right now."
-- =============================================================================

-- Show the audience what's in the raw MEMBER table: names, DOB, Medi-Cal IDs
-- Everything is visible with no restrictions — this is the problem we're solving.
SELECT
    MEME_ID,
    MEME_LAST_NAME,
    MEME_FIRST_NAME,
    MEME_DOB,
    MEME_SEX,
    MECD_AID_CD,      -- Medi-Cal aid code — HIPAA PHI
    MECD_BIC,         -- Medi-Cal beneficiary ID card — HIPAA PHI
    MEME_MCTR_TYPE,
    ACTIVE_PCP_NAME
FROM MEMBER
ORDER BY MEME_ID
LIMIT 20;


-- =============================================================================
-- BEAT 2: AI CLASSIFICATION — SNOWFLAKE IDENTIFIES WHAT'S SENSITIVE
-- "Watch Snowflake's AI scan every column and assign a classification level."
-- =============================================================================

-- Step 2a: Preview mode — read-only, no tags applied yet
-- Shows the AI's recommendations with confidence scores
CALL SYSTEM$CLASSIFY(
    'zFACETS_DEV_CLONE.SILVER.MEMBER',
    {'auto_tag': false}
);

-- Parse the JSON output into a readable table
SELECT
    col.key                                                        AS column_name,
    col.value:recommendation:semantic_category::STRING             AS semantic_category,
    col.value:recommendation:privacy_category::STRING              AS privacy_category,
    col.value:recommendation:confidence::STRING                    AS confidence
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID())) r,
    LATERAL FLATTEN(input => r."SYSTEM$CLASSIFY":classification_result) col
ORDER BY
    CASE col.value:recommendation:privacy_category::STRING
        WHEN 'IDENTIFIER' THEN 1
        WHEN 'QUASI_IDENTIFIER' THEN 2
        WHEN 'SENSITIVE' THEN 3
        ELSE 4
    END,
    col.key;

-- Step 2b: Show the tags that were already applied by the classification profile
--          (01_governance_setup.sql ran SYSTEM$CLASSIFY with auto_tag:true in Section C)
-- Expected: MEME_DOB → RESTRICTED, MEME_LAST/FIRST_NAME → SENSITIVE, etc.
SELECT
    COLUMN_NAME,
    TAG_VALUE AS classification_level
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'zFACETS_DEV_CLONE.SILVER.MEMBER', 'table'
    )
)
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
ORDER BY
    CASE TAG_VALUE
        WHEN 'PII'        THEN 1
        WHEN 'RESTRICTED' THEN 2
        WHEN 'SENSITIVE'  THEN 3
        WHEN 'INTERNAL'   THEN 4
        WHEN 'PUBLIC'     THEN 5
    END,
    COLUMN_NAME;

-- Talking point: Snowflake scanned 29 columns automatically.
-- Named every HIPAA PHI element — we didn't write a single business rule.
-- This runs on a schedule via the classification profile (Section B, lines 102-160).


-- =============================================================================
-- BEAT 3: TAG PROPAGATION — GOVERNANCE FOLLOWS THE DATA
-- "If a data engineer copies this table, do the labels follow?"
-- =============================================================================

-- An analyst creates a working copy using CREATE TABLE AS SELECT
-- (common in healthcare analytics — "give me a copy to work with")
USE ROLE DATA_ENGINEER_ROLE;

CREATE OR REPLACE TABLE zFACETS_DEV_CLONE.SILVER.MEMBER_ANALYTICS_COPY
    AS SELECT * FROM zFACETS_DEV_CLONE.SILVER.MEMBER;

-- Check: did the DATA_CLASSIFICATION tags propagate to the copy?
USE ROLE DATA_GOVERNOR_ROLE;

SELECT
    COLUMN_NAME,
    TAG_VALUE AS classification_level
FROM TABLE(
    zFACETS_DEV_CLONE.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'zFACETS_DEV_CLONE.SILVER.MEMBER_ANALYTICS_COPY', 'table'
    )
)
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
ORDER BY
    CASE TAG_VALUE
        WHEN 'PII'        THEN 1
        WHEN 'RESTRICTED' THEN 2
        WHEN 'SENSITIVE'  THEN 3
        WHEN 'INTERNAL'   THEN 4
    END,
    COLUMN_NAME;

-- Talking point: Zero manual tagging. All DATA_CLASSIFICATION labels propagated
-- automatically because the tag was created with:
--   PROPAGATE = ON_DEPENDENCY_AND_DATA_MOVEMENT
-- (01_governance_setup.sql Section B, lines 85-92)
-- This closes the governance gap: data engineers cannot create untagged PHI copies.


-- =============================================================================
-- BONUS: HOW MANY COLUMNS ARE TAGGED BY LEVEL?
-- Summary view for the governance slide deck
-- =============================================================================

SELECT
    TAG_VALUE                                AS classification_level,
    COUNT(*)                                 AS column_count,
    LISTAGG(COLUMN_NAME, ', ')
        WITHIN GROUP (ORDER BY COLUMN_NAME)  AS columns
FROM TABLE(
    INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS(
        'zFACETS_DEV_CLONE.SILVER.MEMBER', 'table'
    )
)
WHERE TAG_NAME = 'DATA_CLASSIFICATION'
GROUP BY TAG_VALUE
ORDER BY
    CASE TAG_VALUE
        WHEN 'PII'        THEN 1
        WHEN 'RESTRICTED' THEN 2
        WHEN 'SENSITIVE'  THEN 3
        WHEN 'INTERNAL'   THEN 4
        WHEN 'PUBLIC'     THEN 5
    END;

-- =============================================================================
-- Next: Run 03_security_demo.sql to see the masking and row access policies
-- in action across all 4 CalOptima roles.
-- =============================================================================
