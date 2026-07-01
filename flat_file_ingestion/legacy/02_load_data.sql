create database raw;
use database raw;
create schema azure;
use schema azure;
-- use role sysadmin;
-- use warehouse development;

/*
   Stages are synonymous with the idea of folders
   that can be either internal or external.
*/
create or replace stage azure_stage
storage_integration = azure_integration
url = 'azure://timjones.blob.core.windows.net/data'  
--url = 'azure://<STORAGE NAME>.blob.core.windows.net/<CONTAINER NAME>' 
directory = ( enable = true);

/* 
    Create a file format so the "copy into"
    command knows how to copy the data.
*/
create or replace file format raw.azure.json
    type = 'json';

-- Create the table to load into.
create or replace table my_table (
    file_name varchar,
    data variant
);


-- Load the json file from the json folder.
copy into my_table(file_name,data)
from (
    select 
        metadata$filename,
        $1
    from
        @azure_stage/json
        (file_format => json)
);

select *
from raw.azure.my_table; 