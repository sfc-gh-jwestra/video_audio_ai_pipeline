USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

-- A view that always reflects the latest state of all analysis tables.
-- No AI functions here — just joins — so a view is the correct choice.
CREATE OR REPLACE VIEW VIDEO_FULL_INTELLIGENCE AS
SELECT
    v.file_path,
    v.file_name,
    bs.brand_sentiment_json,
    pt.trend_json,
    cr.compliance_json,
    cm.moderation_json,
    vt.transcription_result,
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
