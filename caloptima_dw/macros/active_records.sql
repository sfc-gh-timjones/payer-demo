{% macro active_records() %}
  1 = 1
{% endmacro %}
{# Filter removed — _SNOWFLAKE_DELETED is now passed as IS_DELETED through staging → Silver.
   Gold views filter WHERE NOT IS_DELETED to expose only active records to consumers. #}
