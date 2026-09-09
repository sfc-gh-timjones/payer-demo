-- Aggregates network participation and contract types per provider.
-- Joins to CMC_AGAG_AGREEMENT via CMC_NWPR_RELATION (AGAG_ID foreign key).
SELECT
    p.*,
    COUNT(DISTINCT n.NWNW_ID)                               AS ACTIVE_NETWORK_COUNT,
    MAX(CASE WHEN a.AGAG_MCTR_TYPE = 'CAP' THEN 1 ELSE 0 END) AS IS_PCP_ELIGIBLE,
    LISTAGG(DISTINCT a.CONTRACT_TYPE_DESC, ', ')
        WITHIN GROUP (ORDER BY a.CONTRACT_TYPE_DESC)        AS CONTRACT_TYPES
FROM {{ ref('int_prpr_with_address') }} p
LEFT JOIN {{ ref('stg_nwpr_relation') }} n
    ON  p.PRPR_ID = n.PRPR_ID
    AND n.IS_ACTIVE_PARTICIPATION = TRUE
LEFT JOIN {{ ref('stg_agag_agreement') }} a
    ON  n.AGAG_ID = a.AGAG_ID
    AND a.IS_ACTIVE_AGREEMENT = TRUE
GROUP BY
    p.PRPR_ID, p.PRPR_NPI, p.NPI_VALID, p.PRPR_NAME, p.PRPR_ENTITY,
    p.PROVIDER_TYPE, p.PRPR_STS, p.STATUS_DESC, p.PRPR_MCTR_TYPE,
    p.CONTRACT_TYPE, p.PRPR_TAXONOMY_CD, p.TERM_DT, p.ROW_HASH_HEX,
    p.SYS_USUS_ID, p.SYS_LAST_UPD_DTM, p._SNOWFLAKE_INSERTED_AT, p.updated_at,
    p.rn, p.npi_count, p.IS_DUPLICATE, p.DUPLICATE_COUNT,
    p.PRACTICE_ADDR1, p.PRACTICE_ADDR2, p.PRACTICE_CITY,
    p.PRACTICE_STATE, p.PRACTICE_ZIP,
    p.IS_DELETED
