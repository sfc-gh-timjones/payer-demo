/*
Integrations are on of those important features that account admins
should do because it's allowing outside snowflake connections to your data.
*/
use role accountadmin;

create or replace storage integration azure_integration
    type = external_stage
    storage_provider = 'azure'
    enabled = true 
    azure_tenant_id = '9a2d78cb-73e9-40ee-a558-fc1ac5ef57a7' 
    storage_allowed_locations = ('azure://timjones.blob.core.windows.net/data');

-- Give the sysadmin access to use the integration later.
grant usage on integration azure_integration to role sysadmin;

-- Get the URL to authenticate with azure and the app name to use later.
describe storage integration azure_integration;
select "property", 
case  when "property" = 'AZURE_MULTI_TENANT_APP_NAME' then split_part("property_value", '_', 1) else "property_value"end as "property_value"
from table(result_scan(last_query_id()))
where "property" in ('AZURE_CONSENT_URL', 'AZURE_MULTI_TENANT_APP_NAME');