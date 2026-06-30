{{ config(materialized='table') }}

SELECT 'CMC_PRPR_PROV'      AS layer, 'Bronze' AS stage, COUNT(*) AS row_count
FROM {{ source('raw', 'CMC_PRPR_PROV') }}      WHERE _SNOWFLAKE_DELETED = FALSE
UNION ALL
SELECT 'silver_provider',    'Silver',           COUNT(*) FROM {{ ref('provider') }}
UNION ALL
SELECT 'CMC_MEME_MEMBER',    'Bronze',           COUNT(*)
FROM {{ source('raw', 'CMC_MEME_MEMBER') }}     WHERE _SNOWFLAKE_DELETED = FALSE
UNION ALL
SELECT 'silver_member',      'Silver',           COUNT(*) FROM {{ ref('member') }}
UNION ALL
SELECT 'CMC_MEPE_PRCS_ELIG', 'Bronze',           COUNT(*)
FROM {{ source('raw', 'CMC_MEPE_PRCS_ELIG') }}  WHERE _SNOWFLAKE_DELETED = FALSE
UNION ALL
SELECT 'silver_eligibility', 'Silver',           COUNT(*) FROM {{ ref('eligibility') }}
ORDER BY layer, stage
