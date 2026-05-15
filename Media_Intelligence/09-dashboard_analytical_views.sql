USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

CREATE OR REPLACE VIEW V_BRAND_SENTIMENT_FLAT AS
SELECT
    file_path,
    file_name,
    PARSE_JSON(brand_sentiment_json:value):primary_brand::STRING AS primary_brand,
    PARSE_JSON(brand_sentiment_json:value):overall_sentiment::STRING AS overall_sentiment,
    PARSE_JSON(brand_sentiment_json:value):sentiment_confidence::FLOAT AS sentiment_confidence,
    PARSE_JSON(brand_sentiment_json:value):competitive_positioning::STRING AS competitive_positioning,
    PARSE_JSON(brand_sentiment_json:value):target_audience_inferred::STRING AS target_audience,
    PARSE_JSON(brand_sentiment_json:value):content_category::STRING AS content_category,
    b.value:brand_name::STRING AS detected_brand,
    b.value:sentiment::STRING AS brand_specific_sentiment,
    b.value:role::STRING AS brand_role,
    b.value:screen_time_pct::FLOAT AS screen_time_pct,
    analyzed_at
FROM BRAND_SENTIMENT_RESULTS,
    LATERAL FLATTEN(input => PARSE_JSON(brand_sentiment_json:value):brands_detected) b
WHERE brand_sentiment_json:error IS NULL;

CREATE OR REPLACE VIEW V_CONTENT_SAFETY_SUMMARY AS
SELECT
    file_path,
    file_name,
    PARSE_JSON(moderation_json:value):overall_safety_rating::STRING AS safety_rating,
    PARSE_JSON(moderation_json:value):harmful_content_detected::BOOLEAN AS harmful_detected,
    PARSE_JSON(moderation_json:value):age_rating::STRING AS age_rating,
    PARSE_JSON(moderation_json:value):moderation_action::STRING AS moderation_action,
    PARSE_JSON(moderation_json:value):moderation_categories:violence::STRING AS violence_level,
    PARSE_JSON(moderation_json:value):moderation_categories:sexual_content::STRING AS sexual_content_level,
    PARSE_JSON(moderation_json:value):moderation_categories:hate_speech::STRING AS hate_speech_level,
    PARSE_JSON(moderation_json:value):moderation_categories:profanity::STRING AS profanity_level,
    PARSE_JSON(moderation_json:value):platform_suitability:youtube::BOOLEAN AS youtube_safe,
    PARSE_JSON(moderation_json:value):platform_suitability:tiktok::BOOLEAN AS tiktok_safe,
    PARSE_JSON(moderation_json:value):platform_suitability:instagram::BOOLEAN AS instagram_safe,
    analyzed_at
FROM CONTENT_MODERATION_RESULTS
WHERE moderation_json:error IS NULL;
CREATE OR REPLACE VIEW V_COMPLIANCE_DASHBOARD AS
SELECT
    file_path,
    file_name,
    PARSE_JSON(compliance_json:value):brand_placement_quality::STRING AS placement_quality,
    PARSE_JSON(compliance_json:value):messaging_alignment::STRING AS messaging_alignment,
    PARSE_JSON(compliance_json:value):tone_assessment:tone_brand_fit::STRING AS tone_fit,
    PARSE_JSON(compliance_json:value):disclosure_compliance:disclosure_present::BOOLEAN AS disclosure_present,
    PARSE_JSON(compliance_json:value):disclosure_compliance:ftc_compliant::BOOLEAN AS ftc_compliant,
    PARSE_JSON(compliance_json:value):brand_safety_score::FLOAT AS brand_safety_score,
    PARSE_JSON(compliance_json:value):approval_recommendation::STRING AS approval_recommendation,
    analyzed_at
FROM COMPLIANCE_RESULTS
WHERE compliance_json:error IS NULL;