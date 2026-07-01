-- Flat file ingestion demo with infer schema, schema evolution, Snowpipe, and tasks
/***********************************************************************
DEMO: Ingesting data into Snowflake via Cloud Bucket and setting up
Snowpipe or Tasks for automated data ingestion. 

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

CREATE OR REPLACE FILE FORMAT my_csv_file_format
    TYPE = 'CSV'
    PARSE_HEADER = TRUE;

list @MY_STAGE/ingest_demo/;

/***********************************************************************
OPTION 1A: INFER SCHEMA, SCHEMA EVOLUTION & TASK-BASED LOADING
  https://docs.snowflake.com/en/user-guide/data-load-schema-evolution

  Use INFER_SCHEMA to auto-create a table from file metadata, then
  enable SCHEMA EVOLUTION so the table adapts as source files change.
  Requires:
    1. ENABLE_SCHEMA_EVOLUTION = TRUE on the table
    2. MATCH_BY_COLUMN_NAME on the COPY INTO
    3. EVOLVE SCHEMA or OWNERSHIP privilege on the table

************************************************************************/

/***********************************************************************
  Step 1: Infer schema and create table from csv
************************************************************************/

--Infer Schema
SELECT *
  FROM TABLE(
    INFER_SCHEMA(
      LOCATION=>'@MY_STAGE/ingest_demo/csv_example/'
      , FILE_FORMAT=>'my_csv_file_format'
      , FILES => ( 'pharmacy_claims.csv' )
      )
    );

--Create Table via Infer Schema 
CREATE OR REPLACE TABLE pharmacy_claims
  ENABLE_SCHEMA_EVOLUTION = TRUE
  USING TEMPLATE (
    SELECT ARRAY_AGG(OBJECT_CONSTRUCT(*))
      FROM TABLE(
        INFER_SCHEMA(
      LOCATION=>'@MY_STAGE/ingest_demo/csv_example/'
      , FILE_FORMAT=>'my_csv_file_format'
      , FILES => ('pharmacy_claims.csv')
        )
      ));

--DESCRIBE TABLE pharmacy_claims;
SELECT * FROM pharmacy_claims;

--Copy Data into table. 
COPY INTO pharmacy_claims
FROM @my_stage/ingest_demo/csv_example/
  FILES = ('pharmacy_claims.csv')
  FILE_FORMAT = (FORMAT_NAME= 'my_csv_file_format')
  MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

--Table now has data. 
SELECT * FROM pharmacy_claims;
SELECT COUNT(*) AS rows_loaded FROM pharmacy_claims;


/***********************************************************************
  Step 2: Validation Mode - Begin 
************************************************************************/

COPY INTO pharmacy_claims
FROM @MY_STAGE/ingest_demo/csv_example/
FILES = ('pharmacy_claims_bad_records.csv')
FILE_FORMAT = (
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
VALIDATION_MODE = 'RETURN_ERRORS';


COPY INTO pharmacy_claims
FROM @MY_STAGE/ingest_demo/csv_example/
FILES = ('pharmacy_claims_bad_records.csv')
FILE_FORMAT = (
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
ON_ERROR = 'ABORT_STATEMENT';

--continue/ignore errors. 
COPY INTO pharmacy_claims
FROM @MY_STAGE/ingest_demo/csv_example/
FILES = ('pharmacy_claims_bad_records.csv')
FILE_FORMAT = (
  TYPE = CSV
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
)
ON_ERROR = 'CONTINUE';


SELECT *
FROM TABLE(VALIDATE(pharmacy_claims, JOB_ID => '_last'));


-- SKIP_FILE:
-- If any error is found in a file, skip that entire file.
-- Useful when you only want completely clean files loaded.

-- SKIP_FILE_<num>:
-- Skip the entire file when the number of error rows is equal to or greater than the specified number.
-- Example: skip the file once it hits 10 bad rows.

-- SKIP_FILE_<num>%:
-- Skip the entire file when the percentage of error rows reaches or exceeds the specified threshold.
-- Example: skip the file if 5% or more of rows are bad.

/***********************************************************************
 Step 2: Validation Mode - End 
************************************************************************/


/***********************************************************************
LOAD VIA SNOWPIPE 
************************************************************************/
/***********************************************************************
  Create table, pipe, and validate. Snowpipe auto-ingests new files
  as they land in S3 via SQS event notifications. 

************************************************************************/


CREATE OR REPLACE PIPE pipe_demo
AUTO_INGEST = TRUE
  AS
    COPY INTO pharmacy_claims
    FROM @my_stage/ingest_demo/csv_example/
    PATTERN = '.*\.csv$'
    FILE_FORMAT = (FORMAT_NAME= 'my_csv_file_format')
    MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE;

--add files: pharmcy_claims_inc1.csv, pharmacy_claims_inc2.csv (1k records each)
SHOW PIPES;

SELECT "name", "notification_channel" AS queue
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

SELECT SYSTEM$PIPE_STATUS('pipe_demo');

SELECT *
FROM pharmacy_claims;


/***********************************************************************
  XML LOADING  
************************************************************************/
-- Create File Format 
CREATE OR REPLACE FILE FORMAT MEDICAL_CLAIMS_XML_FF
  TYPE = XML
  STRIP_OUTER_ELEMENT = TRUE
  PRESERVE_SPACE = FALSE
  IGNORE_UTF8_ERRORS = FALSE;

-- Create Landing Table 
CREATE OR REPLACE TABLE MEDICAL_CLAIMS_RAW (
    src             VARIANT         NOT NULL,
    file_name       VARCHAR(500),
    load_timestamp  TIMESTAMP_NTZ   DEFAULT CURRENT_TIMESTAMP()
);

-- Load XML data 
COPY INTO MEDICAL_CLAIMS_RAW (src, file_name)
FROM (
  SELECT $1, METADATA$FILENAME
  FROM @my_stage/ingest_demo/xml_example/
)
FILES = ('medical_claims.xml')
FILE_FORMAT = (FORMAT_NAME = MEDICAL_CLAIMS_XML_FF)
ON_ERROR = ABORT_STATEMENT;

-- View raw XML loaded data 
SELECT *
FROM MEDICAL_CLAIMS_RAW;

-- Create Structured/Flattened table. 
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

SELECT *
FROM MEDICAL_CLAIMS_STRUCTURED;

/***********************************************************************
  XML LOADING - END 
************************************************************************/