USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

-- Persistent target table
CREATE TABLE IF NOT EXISTS PRODUCT_TREND_RESULTS (
    file_path       STRING,
    file_name       STRING,
    trend_json      VARIANT,
    analyzed_at     TIMESTAMP_LTZ
);

-- Stored procedure: incremental product trend discovery
CREATE OR REPLACE PROCEDURE ANALYZE_PRODUCT_TRENDS()
RETURNS STRING
LANGUAGE SQL
AS
BEGIN
    INSERT INTO PRODUCT_TREND_RESULTS (file_path, file_name, trend_json, analyzed_at)
    SELECT
        vc.file_path,
        vc.file_name,
        AI_COMPLETE(
            'gemini-3.1-pro',
            'You are a consumer trends researcher. Analyze this video to identify products being used
and emerging trends. Focus on:
- Products shown in use (whether sponsored or organic)
- Context of usage (location, activity, occasion)
- Unexpected or novel use cases
- Emerging behavioral patterns or aesthetic trends
- Demographics and lifestyle signals of the content creator/subjects
Respond in JSON only.',
            vc.video_file,
            {},
            {
                'type': 'json',
                'schema': {
                    'type': 'object',
                    'properties': {
                        'products_identified': {
                            'type': 'array',
                            'items': {
                                'type': 'object',
                                'properties': {
                                    'product_name': {'type': 'string'},
                                    'category': {'type': 'string'},
                                    'brand': {'type': 'string'},
                                    'usage_context': {'type': 'string'},
                                    'is_sponsored': {'type': 'boolean'},
                                    'novel_use_case': {'type': 'boolean'},
                                    'novel_use_description': {'type': 'string'}
                                },
                                'required': ['product_name', 'category', 'usage_context', 'is_sponsored']
                            }
                        },
                        'emerging_trends': {
                            'type': 'array',
                            'items': {
                                'type': 'object',
                                'properties': {
                                    'trend_name': {'type': 'string'},
                                    'trend_category': {'type': 'string', 'enum': ['aesthetic', 'behavioral', 'product_usage', 'lifestyle', 'cultural']},
                                    'confidence': {'type': 'string', 'enum': ['low', 'medium', 'high']},
                                    'evidence': {'type': 'string'}
                                },
                                'required': ['trend_name', 'trend_category', 'confidence', 'evidence']
                            }
                        },
                        'creator_demographics': {
                            'type': 'object',
                            'properties': {
                                'estimated_age_range': {'type': 'string'},
                                'lifestyle_signals': {'type': 'array', 'items': {'type': 'string'}},
                                'setting': {'type': 'string'},
                                'content_style': {'type': 'string'}
                            }
                        },
                        'campaign_opportunity_score': {'type': 'number'},
                        'campaign_angle_suggestion': {'type': 'string'}
                    },
                    'required': ['products_identified', 'emerging_trends', 'creator_demographics',
                                 'campaign_opportunity_score', 'campaign_angle_suggestion']
                }
            }
        ),
        CURRENT_TIMESTAMP()
    FROM VIDEO_CATALOG vc
    LEFT JOIN PRODUCT_TREND_RESULTS ptr
        ON vc.file_path = ptr.file_path
    WHERE ptr.file_path IS NULL;

    RETURN 'Product trend discovery complete — new files processed';
END;

-- Run once at setup
CALL ANALYZE_PRODUCT_TRENDS();

-- Scheduled task: process new files every 5 minutes
CREATE OR REPLACE TASK PRODUCT_TREND_TASK
    WAREHOUSE = AI_MEDIA_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL ANALYZE_PRODUCT_TRENDS();

ALTER TASK PRODUCT_TREND_TASK RESUME;
