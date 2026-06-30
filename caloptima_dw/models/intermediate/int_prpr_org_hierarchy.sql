-- Links individual providers to their parent organization via CMC_PRER_RELATION.
SELECT
    p.*,
    rel.PRER_PRPR_ID    AS PARENT_ORG_PRPR_ID,
    org.PRPR_NAME       AS PARENT_ORG_NAME
FROM {{ ref('int_prpr_network_summary') }} p
LEFT JOIN {{ ref('stg_prer_relation') }} rel
    ON  p.PRPR_ID = rel.PRPR_ID
    AND p.PRPR_ENTITY = 'I'
    AND rel.IS_ACTIVE_LINK = TRUE
LEFT JOIN {{ ref('stg_prpr_prov') }} org
    ON  rel.PRER_PRPR_ID = org.PRPR_ID
    AND org.PRPR_ENTITY  = 'O'
