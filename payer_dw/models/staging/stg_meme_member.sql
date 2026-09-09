WITH source AS (
    SELECT * FROM {{ source('raw', 'CMC_MEME_MEMBER') }}
)
SELECT
    MEME_ID,
    SBSB_ID,
    MEME_LAST_NAME,
    MEME_FIRST_NAME,
    MEME_DOB,
    MEME_SEX,
    CASE MEME_SEX
        WHEN 'M' THEN 'Male'
        WHEN 'F' THEN 'Female'
        WHEN 'U' THEN 'Unknown'
        ELSE MEME_SEX
    END                             AS SEX_DESC,
    MEME_REL_CD,
    CASE MEME_REL_CD
        WHEN '01' THEN 'Subscriber'
        WHEN '02' THEN 'Spouse'
        WHEN '03' THEN 'Child'
        WHEN '04' THEN 'Other Dependent'
        ELSE MEME_REL_CD
    END                             AS RELATIONSHIP_DESC,
    MEME_STS,
    CASE MEME_STS
        WHEN 'AC' THEN 'Active'
        WHEN 'IN' THEN 'Inactive'
        ELSE MEME_STS
    END                             AS STATUS_DESC,
    MEME_MCTR_TYPE,
    MD5(CONCAT_WS('|',
        COALESCE(SBSB_ID::VARCHAR, ''),
        COALESCE(MEME_DOB::VARCHAR, ''),
        COALESCE(MEME_SEX, ''),
        COALESCE(UPPER(MEME_LAST_NAME), ''),
        COALESCE(UPPER(MEME_FIRST_NAME), '')
    ))                              AS DEMO_KEY,
    SYS_LAST_UPD_DTM,
    _SNOWFLAKE_UPDATED_AT           AS updated_at,
    _SNOWFLAKE_DELETED              AS IS_DELETED
FROM source
