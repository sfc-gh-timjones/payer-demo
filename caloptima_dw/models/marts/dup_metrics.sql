{{ config(materialized='table') }}

SELECT
    'Provider'                                              AS domain,
    COUNT(*)                                                AS bronze_rows,
    SUM(CASE WHEN IS_DUPLICATE THEN 1 ELSE 0 END)          AS duplicate_rows,
    ROUND(
        100.0 * SUM(CASE WHEN IS_DUPLICATE THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 2
    )                                                       AS duplicate_pct,
    SUM(CASE WHEN NOT IS_DUPLICATE THEN 1 ELSE 0 END)      AS silver_rows
FROM {{ ref('int_prpr_dedup') }}

UNION ALL

SELECT
    'Member',
    COUNT(*),
    SUM(CASE WHEN IS_DUPLICATE THEN 1 ELSE 0 END),
    ROUND(
        100.0 * SUM(CASE WHEN IS_DUPLICATE THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 2
    ),
    SUM(CASE WHEN NOT IS_DUPLICATE THEN 1 ELSE 0 END)
FROM {{ ref('int_meme_dedup') }}
