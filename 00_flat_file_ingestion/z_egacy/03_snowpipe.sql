use role accountadmin;

-- Setup the storage notification to know when storage events happen.
create or replace notification integration azure_snowpipe_integration
    enabled = true
    type = queue
    notification_provider = azure_storage_queue
    azure_storage_queue_primary_uri = 'https://timjones.queue.core.windows.net/timjones-snowflake-queue' 
    azure_tenant_id = '9a2d78cb-73e9-40ee-a558-fc1ac5ef57a7'; 

-- Give the sysadmin access to use the integration.
grant usage on integration azure_snowpipe_integration to role sysadmin;

describe storage integration azure_integration;
describe notification integration azure_snowpipe_integration;

select "property", 
case  when "property" = 'AZURE_MULTI_TENANT_APP_NAME' then split_part("property_value", '_', 1) else "property_value"end as "property_value"
from table(result_scan(last_query_id()))
where "property" in ('AZURE_CONSENT_URL', 'AZURE_MULTI_TENANT_APP_NAME');


--use role sysadmin;
use database raw;
use schema azure;
--use warehouse development;

/*
    Copy CSV data using a pipe without having
    to write out the column names.
*/
create or replace file format infer
    type = csv
    parse_header = true
    skip_blank_lines = true
    field_optionally_enclosed_by ='"'
    trim_space = true
    error_on_column_count_mismatch = false;

/*
    Creat the table with the column names
    generated for us.
*/
create or replace table csv_table
    using template (
        select array_agg(object_construct(*))
        within group (order by order_id)
        from table(
            infer_schema(        
            LOCATION=>'@azure_stage/csv'
        , file_format => 'infer')
        )
    );

/*
    Load the data and assign the pipe notification
    to know when a file is added.
*/
create or replace pipe my_pipe 
    auto_ingest = true 
    integration = 'AZURE_SNOWPIPE_INTEGRATION'
    as

    COPY into
        csv_table
    from
        @azure_stage/csv

    file_format = (format_name= 'infer')
    match_by_column_name=case_insensitive;

/* 
    Refresh the state of the pipe to make
    sure it's updated with all files.
*/
alter pipe my_pipe refresh;

select *
from csv_table;


SHOW PIPES;

SELECT "name", "notification_channel" AS queue
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

SELECT SYSTEM$PIPE_STATUS('my_pipe');