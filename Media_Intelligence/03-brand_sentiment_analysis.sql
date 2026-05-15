USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

-- Persistent target table (survives re-runs)
CREATE TABLE IF NOT EXISTS BRAND_SENTIMENT_RESULTS (
    file_path           STRING,
    file_name           STRING,
    ingested_at         TIMESTAMP_TZ,
    brand_sentiment_json VARIANT,
    analyzed_at         TIMESTAMP_LTZ
);

-- Stored procedure: incremental brand sentiment analysis
CREATE OR REPLACE PROCEDURE ANALYZE_BRAND_SENTIMENT()
RETURNS STRING
LANGUAGE SQL
AS
BEGIN
    INSERT INTO BRAND_SENTIMENT_RESULTS (file_path, file_name, ingested_at, brand_sentiment_json, analyzed_at)
    SELECT
        vc.file_path,
        vc.file_name,
        vc.ingested_at,
        AI_COMPLETE(
            'gemini-3.1-pro',
            'You are a brand intelligence analyst. Analyze this video for brand presence and sentiment.
Identify all brands (mentioned verbally OR shown visually). For each brand, determine:
- How it is positioned (positive, negative, neutral)
- Whether it is the primary subject or a competitor reference
- Sentiment drivers (what visual/audio cues inform the sentiment)
- Brand visibility type (logo, product placement, verbal mention, text overlay)
Respond in JSON only.',
            vc.video_file,
            {},
            {
                'type': 'json',
                'schema': {
                    'type': 'object',
                    'properties': {
                        'primary_brand': {'type': 'string'},
                        'overall_sentiment': {'type': 'string', 'enum': ['very_positive', 'positive', 'neutral', 'negative', 'very_negative']},
                        'sentiment_confidence': {'type': 'number'},
                        'brands_detected': {
                            'type': 'array',
                            'items': {
                                'type': 'object',
                                'properties': {
                                    'brand_name': {'type': 'string'},
                                    'sentiment': {'type': 'string', 'enum': ['positive', 'neutral', 'negative']},
                                    'role': {'type': 'string', 'enum': ['primary', 'competitor', 'incidental']},
                                    'visibility_types': {'type': 'array', 'items': {'type': 'string'}},
                                    'sentiment_drivers': {'type': 'array', 'items': {'type': 'string'}},
                                    'screen_time_pct': {'type': 'number'}
                                },
                                'required': ['brand_name', 'sentiment', 'role', 'visibility_types', 'sentiment_drivers']
                            }
                        },
                        'competitive_positioning': {'type': 'string'},
                        'key_visual_cues': {'type': 'array', 'items': {'type': 'string'}},
                        'key_audio_cues': {'type': 'array', 'items': {'type': 'string'}},
                        'target_audience_inferred': {'type': 'string'},
                        'content_category': {'type': 'string'}
                    },
                    'required': ['primary_brand', 'overall_sentiment', 'sentiment_confidence',
                                 'brands_detected', 'competitive_positioning', 'key_visual_cues',
                                 'key_audio_cues', 'target_audience_inferred', 'content_category']
                }
            }
        ),
        CURRENT_TIMESTAMP()
    FROM VIDEO_CATALOG vc
    LEFT JOIN BRAND_SENTIMENT_RESULTS bsr
        ON vc.file_path = bsr.file_path
    WHERE bsr.file_path IS NULL;

    RETURN 'Brand sentiment analysis complete — new files processed';
END;

-- Run once at setup
CALL ANALYZE_BRAND_SENTIMENT();

-- Scheduled task: process new files every 5 minutes
CREATE OR REPLACE TASK BRAND_SENTIMENT_TASK
    WAREHOUSE = AI_MEDIA_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL ANALYZE_BRAND_SENTIMENT();

ALTER TASK BRAND_SENTIMENT_TASK RESUME;
