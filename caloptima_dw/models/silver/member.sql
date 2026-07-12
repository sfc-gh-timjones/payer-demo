{{ config(
    materialized='incremental',
    unique_key='MEME_ID',
    incremental_strategy='merge',
    on_schema_change='sync_all_columns'
) }}

SELECT
    m.MEME_ID,
    m.SBSB_ID,
    m.MEME_LAST_NAME,
    m.MEME_FIRST_NAME,
    m.MEME_DOB,
    m.RELATIONSHIP_DESC,
    m.MEME_REL_CD,
    m.SEX_DESC,
    m.MEME_SEX,
    m.STATUS_DESC                               AS MEMBER_STATUS,
    m.MEME_STS,
    m.MEME_MCTR_TYPE,
    m.SUBSCRIBER_LAST_NAME,
    m.SUBSCRIBER_FIRST_NAME,
    m.SUBSCRIBER_DOB,
    m.SUBSCRIBER_STATUS,
    m.SUBSCRIBER_MCTR_TYPE,
    pcp.ACTIVE_PCP_PRPR_ID,
    pcp.ACTIVE_PCP_NAME,
    pcp.ACTIVE_PCP_NPI,
    pcp.PCP_EFF_DT,
    pcp.ACTIVE_PCP_TYPE,
    mcd.MECD_AID_CD,
    mcd.MECD_BIC,
    mcd.MECD_EFF_DT                             AS MEDICAID_EFF_DT,
    mcd.MECD_TERM_DT                            AS MEDICAID_TERM_DT,
    m.DUPLICATE_COUNT,
    m.IS_DELETED,
    m.updated_at                                AS BRONZE_UPDATED_AT,
    CURRENT_TIMESTAMP()                         AS SILVER_LOADED_AT
FROM 
    {{ ref('int_meme_with_subscriber') }} m
    LEFT JOIN {{ ref('int_meme_pcp_current') }} pcp ON m.MEME_ID = pcp.MEME_ID
    LEFT JOIN {{ ref('int_meme_medicaid') }}    mcd ON m.MEME_ID = mcd.MEME_ID
WHERE 
    m.IS_DUPLICATE = FALSE
    {% if is_incremental() %}
        AND m.updated_at > (
            SELECT COALESCE(MAX(BRONZE_UPDATED_AT), '1900-01-01'::TIMESTAMP_NTZ)
            FROM {{ this }}
        )
    {% endif %}
