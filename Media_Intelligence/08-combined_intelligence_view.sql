USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

-- A view that always reflects the latest state of all analysis tables.
-- No AI functions here — just joins — so a view is the correct choice.
CREATE OR REPLACE VIEW VIDEO_FULL_INTELLIGENCE AS
SELECT
    v.file_path,
    v.file_name,
    PARSE_JSON(bs.brand_sentiment_json:value) AS brand_sentiment_json,
    PARSE_JSON(pt.trend_json:value) AS trend_json,
    PARSE_JSON(cr.compliance_json:value) AS compliance_json,
    PARSE_JSON(cm.moderation_json:value) AS moderation_json,
    PARSE_JSON(vt.transcription_result:value) AS transcription_result,
    bs.brand_sentiment_json:error::STRING AS sentiment_error,
    pt.trend_json:error::STRING AS trend_error,
    cr.compliance_json:error::STRING AS compliance_error,
    cm.moderation_json:error::STRING AS moderation_error,
    vt.transcription_result:error::STRING AS transcription_error,
    bs.analyzed_at AS sentiment_analyzed_at,
    pt.analyzed_at AS trend_analyzed_at,
    cr.analyzed_at AS compliance_analyzed_at,
    cm.analyzed_at AS moderation_analyzed_at,
    vt.transcribed_at
FROM VIDEO_CATALOG v
LEFT JOIN BRAND_SENTIMENT_RESULTS bs ON v.file_path = bs.file_path
LEFT JOIN PRODUCT_TREND_RESULTS pt ON v.file_path = pt.file_path
LEFT JOIN COMPLIANCE_RESULTS cr ON v.file_path = cr.file_path
LEFT JOIN CONTENT_MODERATION_RESULTS cm ON v.file_path = cm.file_path
LEFT JOIN VIDEO_TRANSCRIPTIONS vt ON v.file_path = vt.file_path;
