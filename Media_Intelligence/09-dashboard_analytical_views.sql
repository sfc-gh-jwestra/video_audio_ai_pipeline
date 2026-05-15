USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

CREATE OR REPLACE VIEW V_BRAND_SENTIMENT_FLAT AS
SELECT
    file_path,
    file_name,
    brand_sentiment_json:structured_output[0]:raw_message:primary_brand::STRING AS primary_brand,
    brand_sentiment_json:structured_output[0]:raw_message:overall_sentiment::STRING AS overall_sentiment,
    brand_sentiment_json:structured_output[0]:raw_message:sentiment_confidence::FLOAT AS sentiment_confidence,
    brand_sentiment_json:structured_output[0]:raw_message:competitive_positioning::STRING AS competitive_positioning,
    brand_sentiment_json:structured_output[0]:raw_message:target_audience_inferred::STRING AS target_audience,
    brand_sentiment_json:structured_output[0]:raw_message:content_category::STRING AS content_category,
    b.value:brand_name::STRING AS detected_brand,
    b.value:sentiment::STRING AS brand_specific_sentiment,
    b.value:role::STRING AS brand_role,
    b.value:screen_time_pct::FLOAT AS screen_time_pct,
    analyzed_at
FROM BRAND_SENTIMENT_RESULTS,
    LATERAL FLATTEN(input => brand_sentiment_json:structured_output[0]:raw_message:brands_detected) b;

CREATE OR REPLACE VIEW V_CONTENT_SAFETY_SUMMARY AS
SELECT
    file_path,
    file_name,
    moderation_json:structured_output[0]:raw_message:overall_safety_rating::STRING AS safety_rating,
    moderation_json:structured_output[0]:raw_message:harmful_content_detected::BOOLEAN AS harmful_detected,
    moderation_json:structured_output[0]:raw_message:age_rating::STRING AS age_rating,
    moderation_json:structured_output[0]:raw_message:moderation_action::STRING AS moderation_action,
    moderation_json:structured_output[0]:raw_message:moderation_categories:violence::STRING AS violence_level,
    moderation_json:structured_output[0]:raw_message:moderation_categories:sexual_content::STRING AS sexual_content_level,
    moderation_json:structured_output[0]:raw_message:moderation_categories:hate_speech::STRING AS hate_speech_level,
    moderation_json:structured_output[0]:raw_message:moderation_categories:profanity::STRING AS profanity_level,
    moderation_json:structured_output[0]:raw_message:platform_suitability:youtube::BOOLEAN AS youtube_safe,
    moderation_json:structured_output[0]:raw_message:platform_suitability:tiktok::BOOLEAN AS tiktok_safe,
    moderation_json:structured_output[0]:raw_message:platform_suitability:instagram::BOOLEAN AS instagram_safe,
    analyzed_at
FROM CONTENT_MODERATION_RESULTS;

CREATE OR REPLACE VIEW V_COMPLIANCE_DASHBOARD AS
SELECT
    file_path,
    file_name,
    compliance_json:structured_output[0]:raw_message:brand_placement_quality::STRING AS placement_quality,
    compliance_json:structured_output[0]:raw_message:messaging_alignment::STRING AS messaging_alignment,
    compliance_json:structured_output[0]:raw_message:tone_assessment:tone_brand_fit::STRING AS tone_fit,
    compliance_json:structured_output[0]:raw_message:disclosure_compliance:disclosure_present::BOOLEAN AS disclosure_present,
    compliance_json:structured_output[0]:raw_message:disclosure_compliance:ftc_compliant::BOOLEAN AS ftc_compliant,
    compliance_json:structured_output[0]:raw_message:brand_safety_score::FLOAT AS brand_safety_score,
    compliance_json:structured_output[0]:raw_message:approval_recommendation::STRING AS approval_recommendation,
    analyzed_at
FROM COMPLIANCE_RESULTS;
