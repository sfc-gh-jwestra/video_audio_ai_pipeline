-- https://pub.towardsai.net/building-a-production-grade-multimodal-video-audio-intelligence-pipeline-with-snowflake-cortex-ai-686a579486f2

USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS MEDIA_INTELLIGENCE;
CREATE SCHEMA IF NOT EXISTS MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
CREATE WAREHOUSE IF NOT EXISTS AI_MEDIA_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Warehouse for multimodal AI media processing workloads';

USE WAREHOUSE AI_MEDIA_WH;

-- Internal stages for video and audio assets (SSE encryption required for AI functions)
CREATE OR REPLACE STAGE VIDEO_STAGE
    DIRECTORY = (ENABLE = TRUE, AUTO_REFRESH = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT = 'Marketing video assets for brand analysis';

CREATE OR REPLACE STAGE AUDIO_STAGE
    DIRECTORY = (ENABLE = TRUE, AUTO_REFRESH = TRUE)
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    COMMENT = 'Audio recordings for sentiment and brand mention analysis';