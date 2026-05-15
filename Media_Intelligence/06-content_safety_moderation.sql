USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

-- Persistent target table
CREATE TABLE IF NOT EXISTS CONTENT_MODERATION_RESULTS (
    file_path       STRING,
    file_name       STRING,
    moderation_json VARIANT,
    analyzed_at     TIMESTAMP_LTZ
);

-- Stored procedure: incremental content safety moderation
CREATE OR REPLACE PROCEDURE ANALYZE_CONTENT_MODERATION()
RETURNS STRING
LANGUAGE SQL
AS
BEGIN
    INSERT INTO CONTENT_MODERATION_RESULTS (file_path, file_name, moderation_json, analyzed_at)
    SELECT
        vc.file_path,
        vc.file_name,
        AI_COMPLETE(
            'gemini-3.1-pro',
            'You are a content safety classifier. Analyze this video for harmful, unsafe, or policy-violating content.
Classify across all major moderation dimensions. Be thorough and flag anything that could pose risk
for a brand or platform. Respond in JSON only.',
            vc.video_file,
            {},
            {
                'type': 'json',
                'schema': {
                    'type': 'object',
                    'properties': {
                        'overall_safety_rating': {'type': 'string', 'enum': ['safe', 'low_risk', 'medium_risk', 'high_risk', 'unsafe']},
                        'harmful_content_detected': {'type': 'boolean'},
                        'moderation_categories': {
                            'type': 'object',
                            'properties': {
                                'violence': {'type': 'string', 'enum': ['none', 'mild', 'moderate', 'severe']},
                                'sexual_content': {'type': 'string', 'enum': ['none', 'suggestive', 'explicit']},
                                'hate_speech': {'type': 'string', 'enum': ['none', 'mild', 'moderate', 'severe']},
                                'self_harm': {'type': 'string', 'enum': ['none', 'referenced', 'depicted']},
                                'dangerous_activities': {'type': 'string', 'enum': ['none', 'mild', 'moderate', 'severe']},
                                'substance_use': {'type': 'string', 'enum': ['none', 'referenced', 'depicted', 'promoted']},
                                'profanity': {'type': 'string', 'enum': ['none', 'mild', 'moderate', 'heavy']},
                                'misinformation_risk': {'type': 'string', 'enum': ['none', 'low', 'medium', 'high']},
                                'child_safety': {'type': 'string', 'enum': ['safe', 'concern', 'violation']}
                            }
                        },
                        'flagged_moments': {
                            'type': 'array',
                            'items': {
                                'type': 'object',
                                'properties': {
                                    'timestamp_approx': {'type': 'string'},
                                    'category': {'type': 'string'},
                                    'severity': {'type': 'string'},
                                    'description': {'type': 'string'}
                                }
                            }
                        },
                        'platform_suitability': {
                            'type': 'object',
                            'properties': {
                                'youtube': {'type': 'boolean'},
                                'tiktok': {'type': 'boolean'},
                                'instagram': {'type': 'boolean'},
                                'facebook': {'type': 'boolean'},
                                'linkedin': {'type': 'boolean'}
                            }
                        },
                        'age_rating': {'type': 'string', 'enum': ['all_ages', '13_plus', '16_plus', '18_plus']},
                        'moderation_action': {'type': 'string', 'enum': ['approve', 'flag_for_review', 'restrict', 'remove']}
                    }
                }
            }
        ),
        CURRENT_TIMESTAMP()
    FROM VIDEO_CATALOG vc
    LEFT JOIN CONTENT_MODERATION_RESULTS cmr
        ON vc.file_path = cmr.file_path
    WHERE cmr.file_path IS NULL;

    RETURN 'Content moderation complete — new files processed';
END;

-- Run once at setup
CALL ANALYZE_CONTENT_MODERATION();

-- Scheduled task: process new files every 5 minutes
CREATE OR REPLACE TASK CONTENT_MODERATION_TASK
    WAREHOUSE = AI_MEDIA_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL ANALYZE_CONTENT_MODERATION();

ALTER TASK CONTENT_MODERATION_TASK RESUME;
