-- =============================================================================
-- FILE: restore_ba_access.sql
-- PURPOSE: Restore BUSINESS_ANALYST_ROLE access after the REVOKE demo in
--          03_security_demo.sql Part 2. Run this before the next demo session.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

GRANT USAGE ON DATABASE zFACETS_DEV_CLONE              TO ROLE BUSINESS_ANALYST_ROLE;
GRANT USAGE ON SCHEMA zFACETS_DEV_CLONE.SILVER         TO ROLE BUSINESS_ANALYST_ROLE;
GRANT SELECT ON TABLE zFACETS_DEV_CLONE.SILVER.MEMBER  TO ROLE BUSINESS_ANALYST_ROLE;

-- Verify access is restored
USE ROLE BUSINESS_ANALYST_ROLE;
SELECT COUNT(*) AS visible_members FROM zFACETS_DEV_CLONE.SILVER.MEMBER;
-- Expected: ~30,593 (COMM only — row access policy still enforced)
