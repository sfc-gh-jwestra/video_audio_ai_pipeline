USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;


--With the views in place, here are ready-to-run queries for common reporting needs.

-- Top brands by positive sentiment:
SELECT
    detected_brand,
    COUNT(*) AS total_appearances,
    SUM(CASE WHEN brand_specific_sentiment = 'positive' THEN 1 ELSE 0 END) AS positive_count,
    ROUND(positive_count / total_appearances * 100, 1) AS positive_pct
FROM V_BRAND_SENTIMENT_FLAT
GROUP BY detected_brand
ORDER BY total_appearances DESC
LIMIT 20;


-- Content requiring moderation action
SELECT
    file_name,
    safety_rating,
    moderation_action,
    violence_level,
    hate_speech_level,
    age_rating
FROM V_CONTENT_SAFETY_SUMMARY
WHERE moderation_action IN ('flag_for_review', 'restrict', 'remove')
ORDER BY
    CASE moderation_action
        WHEN 'remove' THEN 1
        WHEN 'restrict' THEN 2
        WHEN 'flag_for_review' THEN 3
    END;


-- Compliance failure, needs attention
SELECT
    file_name,
    placement_quality,
    ftc_compliant,
    brand_safety_score,
    approval_recommendation
FROM V_COMPLIANCE_DASHBOARD
WHERE approval_recommendation IN ('reject', 'escalate', 'approve_with_edits')
ORDER BY brand_safety_score ASC;

