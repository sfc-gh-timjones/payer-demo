-- =============================================================================
-- FILE: 06.2_schema_change_snow.sql
-- PURPOSE: Run before and after the schema change in 06_schema_change_mssql.sql
--          to show Snowflake automatically picked up the new PRFA_COUNTY column
--          via Openflow schema evolution.
--
-- RUN ONCE before making the SQL Server change, then run again after Openflow
-- ingests the new records to see the column appear automatically.
-- =============================================================================

-- Show all columns on the Bronze table (PRFA_COUNTY absent before, present after)
DESCRIBE TABLE FACETS_BRONZE.RAW.CMC_PRFA_FACILITY;

-- Show all rows (original ~300 rows pre-change; ~305 rows with PRFA_COUNTY post-change)
SELECT * FROM FACETS_BRONZE.RAW.CMC_PRFA_FACILITY ORDER BY PRFA_ID;
