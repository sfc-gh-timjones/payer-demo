WITH ranked AS (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PRPR_NPI
            ORDER BY SYS_LAST_UPD_DTM DESC NULLS LAST, PRPR_ID DESC
        )                                       AS rn,
        COUNT(*) OVER (PARTITION BY PRPR_NPI)   AS npi_count
    FROM {{ ref('stg_prpr_prov') }}
    WHERE NPI_VALID = TRUE
)
SELECT *,
    CASE WHEN rn = 1 THEN FALSE ELSE TRUE END   AS IS_DUPLICATE,
    npi_count - 1                               AS DUPLICATE_COUNT
FROM ranked
