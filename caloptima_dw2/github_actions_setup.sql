-- =============================================================================
-- FILE: github_actions_setup.sql
-- PURPOSE: Configure Snowflake to allow connections from GitHub Actions CI/CD.
--          Run this once as ACCOUNTADMIN before triggering the dbt CI workflow.
--
-- REFERENCE: https://www.snowflake.com/en/developers/guides/data-engineering-with-notebooks/#deploy-to-production
--
-- GITHUB SECRETS REQUIRED (repo → Settings → Secrets and variables → Actions):
--   SNOWFLAKE_ACCOUNT  = sfsenorthamerica-tim_jones_demo
--   SNOWFLAKE_USER     = ADMIN
--   SNOWFLAKE_PASSWORD = <ADMIN user password>
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- Step 1: Create a network policy that allows inbound connections from GitHub Actions
--         Uses Snowflake's managed network rule for GitHub Actions IP ranges.
--         This avoids having to maintain a static IP allowlist as GitHub rotates IPs.
CREATE NETWORK POLICY github_actions_policy
  ALLOWED_NETWORK_RULE_LIST = (
    'SNOWFLAKE.NETWORK_SECURITY.GITHUBACTIONS_GLOBAL'
  )
  BLOCKED_NETWORK_RULE_LIST = ();

-- Step 2: Attach the network policy to the CI user (ADMIN in this demo account)
ALTER USER ADMIN SET NETWORK_POLICY = github_actions_policy;

-- Step 3: Verify the policy is attached
DESCRIBE USER ADMIN;

-- Step 4: Verify the network rule exists and is accessible
SHOW NETWORK RULES LIKE 'GITHUBACTIONS_GLOBAL' IN SNOWFLAKE.NETWORK_SECURITY;
