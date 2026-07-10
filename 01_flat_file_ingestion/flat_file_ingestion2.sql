-- Flat file ingestion demo with infer schema, schema evolution, Snowpipe, and tasks
/***********************************************************************
DEMO: Ingesting data into Snowflake via Cloud Bucket (AWS S3) and setting up
Snowpipe for automated data ingestion. 

Starting Bucket:
csv: pharmacy_claims.csv, pharmacy_claims_bad_records.csv
xml: medical_claims.xml
************************************************************************/

/***********************************************************************
 SET CONTEXT
************************************************************************/
USE ROLE ACCOUNTADMIN; 

CREATE DATABASE IF NOT EXISTS INGEST_DEMO;
CREATE SCHEMA IF NOT EXISTS INGEST_DEMO.CLOUDBUCKET;

USE DATABASE INGEST_DEMO;
USE SCHEMA CLOUDBUCKET;

/***********************************************************************
CREATE STAGE, CREATE FILE FORMAT 
************************************************************************/

CREATE OR REPLACE STAGE MY_STAGE
  STORAGE_INTEGRATION = capstone_timjones_storageintegration
  URL = 's3://capstone-timjones/';

-- CSV file format with PARSE_HEADER so column names come from row 1
-- ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE is required for schema evolution
CREATE OR REPLACE FILE FORMAT my_csv_file_format
    TYPE = 'CSV'
    PARSE_HEADER = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

LIST @MY_STAGE/ingest_demo/;

/***********************************************************************
INFER SCHEMA & SCHEMA EVOLUTION
  https://docs.snowflake.com/en/user-guide/data-load-schema-evolution

  Use INFER_SCHEMA to auto-create a table from file metadata, then
  enable SCHEMA EVOLUTION so the table adapts as source files change.
  Requires:
    1. ENABLE_SCHEMA_EVOLUTION = TRUE on the table
    2. MATCH_BY_COLUMN_NAME on the COPY INTO
    3. EVOLVE SCHEMA or OWNERSHIP privilege on the table
************************************************************************/

-- Infer Schema: inspect detected column names and data types
SELECT *
FROM TABLE(
    INFER_SCHEMA(
      LOCATION => '@MY_STAGE/ingest_demo/csv_example/'
    , FILE_FORMAT => 'my_csv_file_format'
    , FILES => ('pharmacy_claims.csv')
    )
);

-- Create table automatically from the inferred schema
CREATE OR REPLACE TABLE pharmacy_claims
  ENABLE_SCHEMA_EVOLUTION = TRUE
  USING TEMPLATE (
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
      FROM TABLE(
        INFER_SCHEMA(
          LOCATION => '@MY_STAGE/ingest_demo/csv_example/'
        , FILE_FORMAT => 'my_csv_file_format'
        , FILES => ('pharmacy_claims.csv')
        )
      ));

-- Confirm table structure (matches inferred columns)
SELECT * FROM pharmacy_claims;

-- Load the CSV into the table
COPY INTO pharmacy_claims
FROM @my_stage/ingest_demo/csv_example/
  FILES = ('pharmacy_claims.csv')
  FILE_FORMAT = (FORMAT_NAME = 'my_csv_file_format')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

-- Verify the load
SELECT * FROM pharmacy_claims;

/***********************************************************************
 VALIDATION MODE
************************************************************************/

-- VALIDATION_MODE: preview errors without writing any data to the table
COPY INTO pharmacy_claims
FROM @MY_STAGE/ingest_demo/csv_example/
FILES = ('pharmacy_claims_bad_records.csv')
FILE_FORMAT = (
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
VALIDATION_MODE = 'RETURN_ERRORS';

-- ON_ERROR = ABORT_STATEMENT: load stops immediately on the first bad row
COPY INTO pharmacy_claims
FROM @MY_STAGE/ingest_demo/csv_example/
FILES = ('pharmacy_claims_bad_records.csv')
FILE_FORMAT = (
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
ON_ERROR = 'ABORT_STATEMENT';

-- ON_ERROR = CONTINUE: skip bad rows and load everything else
COPY INTO pharmacy_claims
FROM @MY_STAGE/ingest_demo/csv_example/
FILES = ('pharmacy_claims_bad_records.csv')
FILE_FORMAT = (
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
ON_ERROR = 'CONTINUE';

-- VALIDATE(): inspect which rows were skipped in the last COPY INTO job
SELECT *
FROM TABLE(VALIDATE(pharmacy_claims, JOB_ID => '_last'));

-- ON_ERROR options reference:
-- SKIP_FILE         — skip the entire file if any error is found
-- SKIP_FILE_<num>   — skip file if error row count >= num
-- SKIP_FILE_<num>%  — skip file if error percentage >= num%

-- Row count after validation loads
SELECT COUNT(*) AS total_rows FROM pharmacy_claims;

/***********************************************************************
SNOWPIPE — EVENT-DRIVEN AUTO-INGEST & SCHEMA EVOLUTION

  Snowpipe listens for S3 SQS event notifications and triggers a COPY INTO
  whenever a new file lands in the stage. No manual scheduling needed.

  Setup:
    1. Configure the S3 bucket event notification to point to Snowflake's SQS queue
    2. Copy the notification_channel (SQS ARN) from SHOW PIPES
    3. Add the SQS queue as an S3 event notification source in the AWS console
************************************************************************/

CREATE OR REPLACE PIPE pipe_demo
  AUTO_INGEST = TRUE
AS
  COPY INTO pharmacy_claims
  FROM @my_stage/ingest_demo/csv_example/
  PATTERN = '.*\.csv$'
  FILE_FORMAT = (FORMAT_NAME = 'my_csv_file_format')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

-- Step 1: Before drop — confirm table has 20 columns (no REFILL_NUMBER)
DESCRIBE TABLE pharmacy_claims;

-- Add files: pharmacy_claims_inc1.csv, pharmacy_claims_inc2.csv (1k records each)
SHOW PIPES;

SELECT "name", "notification_channel" AS queue
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Check pipe health and pending file queue
SELECT SYSTEM$PIPE_STATUS('pipe_demo');

/***********************************************************************
SCHEMA EVOLUTION DEMO
  Drop pharmacy_claims_add_refillnum.csv into the stage.
  This file has 21 columns (adds REFILL_NUMBER INTEGER).
  Snowpipe auto-ingests it; ENABLE_SCHEMA_EVOLUTION + MATCH_BY_COLUMN_NAME
  causes Snowflake to automatically ALTER the table and add the new column.

  Step 2: Upload pharmacy_claims_add_refillnum.csv to:
    s3://capstone-timjones/ingest_demo/csv_example/
  Snowpipe fires automatically via SQS event notification.
************************************************************************/

-- Step 3: After Snowpipe ingests — REFILL_NUMBER appears automatically
DESCRIBE TABLE pharmacy_claims;

-- Step 4: Check the data — new rows have REFILL_NUMBER populated
SELECT
    CLAIM_ID,
    DRUG_NAME,
    DAYS_SUPPLY,
    REFILL_NUMBER
FROM pharmacy_claims
WHERE REFILL_NUMBER IS NOT NULL
LIMIT 20;

-- Step 5: Count rows by batch origin
SELECT
    CASE WHEN REFILL_NUMBER IS NULL THEN 'Before evolution' ELSE 'After evolution' END AS batch,
    COUNT(*) AS row_count
FROM pharmacy_claims
GROUP BY 1;

/***********************************************************************
  XML LOADING  
************************************************************************/

-- XML file format: STRIP_OUTER_ELEMENT removes the root wrapper tag
CREATE OR REPLACE FILE FORMAT MEDICAL_CLAIMS_XML_FF
  TYPE = XML
  STRIP_OUTER_ELEMENT = TRUE
  PRESERVE_SPACE = FALSE
  IGNORE_UTF8_ERRORS = FALSE;

-- Raw landing table: one VARIANT row per XML element + metadata columns
CREATE OR REPLACE TABLE MEDICAL_CLAIMS_RAW (
    src             VARIANT         NOT NULL,
    file_name       VARCHAR(500),
    load_timestamp  TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- Load XML — METADATA$FILENAME captures which file each row came from
COPY INTO MEDICAL_CLAIMS_RAW (src, file_name)
FROM (
  SELECT $1, METADATA$FILENAME
  FROM @my_stage/ingest_demo/xml_example/
)
FILES = ('medical_claims.xml')
FILE_FORMAT = (FORMAT_NAME = MEDICAL_CLAIMS_XML_FF)
ON_ERROR = ABORT_STATEMENT;

-- Inspect the raw VARIANT data
SELECT * FROM MEDICAL_CLAIMS_RAW;

-- Flatten XML into a typed structured table using XMLGET
-- XMLGET(src, 'TagName'):"$"::TYPE extracts the text content of each XML element
CREATE OR REPLACE TABLE MEDICAL_CLAIMS_STRUCTURED AS (
SELECT
    XMLGET(src, 'ClaimID')             :"$"::VARCHAR(20)    AS claim_id,
    XMLGET(src, 'MemberID')            :"$"::VARCHAR(20)    AS member_id,
    XMLGET(src, 'DateOfBirth')         :"$"::DATE           AS date_of_birth,
    XMLGET(src, 'Gender')              :"$"::VARCHAR(1)     AS gender,
    XMLGET(src, 'PlanType')            :"$"::VARCHAR(10)    AS plan_type,
    XMLGET(src, 'ServiceDate')         :"$"::DATE           AS service_date,
    XMLGET(src, 'ProviderNPI')         :"$"::VARCHAR(10)    AS provider_npi,
    XMLGET(src, 'ProviderName')        :"$"::VARCHAR(100)   AS provider_name,
    XMLGET(src, 'ProviderSpecialty')   :"$"::VARCHAR(50)    AS provider_specialty,
    XMLGET(src, 'PlaceOfService')      :"$"::VARCHAR(2)     AS place_of_service,
    XMLGET(src, 'DiagnosisCode1')      :"$"::VARCHAR(10)    AS diagnosis_code_1,
    XMLGET(src, 'DiagnosisCode2')      :"$"::VARCHAR(10)    AS diagnosis_code_2,
    XMLGET(src, 'ProcedureCode')       :"$"::VARCHAR(5)     AS procedure_code,
    XMLGET(src, 'ProcedureDescription'):"$"::VARCHAR(100)   AS procedure_description,
    XMLGET(src, 'Units')               :"$"::INTEGER        AS units,
    XMLGET(src, 'BilledAmount')        :"$"::NUMBER(10,2)   AS billed_amount,
    XMLGET(src, 'AllowedAmount')       :"$"::NUMBER(10,2)   AS allowed_amount,
    XMLGET(src, 'PlanPaidAmount')      :"$"::NUMBER(10,2)   AS plan_paid_amount,
    XMLGET(src, 'MemberResponsibility'):"$"::NUMBER(10,2)   AS member_responsibility,
    XMLGET(src, 'ClaimStatus')         :"$"::VARCHAR(10)    AS claim_status,
    file_name,
    load_timestamp
FROM MEDICAL_CLAIMS_RAW
WHERE XMLGET(src, 'ClaimID') IS NOT NULL   -- excludes the 1 <BatchInfo> row
);

SELECT * FROM MEDICAL_CLAIMS_STRUCTURED;
