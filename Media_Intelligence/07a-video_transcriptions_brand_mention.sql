USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

-- Persistent target tables
CREATE TABLE IF NOT EXISTS VIDEO_TRANSCRIPTIONS (
    file_path           STRING,
    file_name           STRING,
    transcription_result VARIANT,
    transcribed_at      TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS VIDEO_BRAND_MENTIONS (
    file_path       STRING,
    file_name       STRING,
    brand_analysis  VARIANT,
    transcribed_at  TIMESTAMP_LTZ
);

-- Stored procedure: incremental video transcription
CREATE OR REPLACE PROCEDURE TRANSCRIBE_VIDEO()
RETURNS STRING
LANGUAGE SQL
AS
BEGIN
    INSERT INTO VIDEO_TRANSCRIPTIONS (file_path, file_name, transcription_result, transcribed_at)
    SELECT
        vc.file_path,
        vc.file_name,
        TO_VARIANT(AI_TRANSCRIBE(vc.video_file, {}, TRUE)),
        CURRENT_TIMESTAMP()
    FROM VIDEO_CATALOG vc
    LEFT JOIN VIDEO_TRANSCRIPTIONS vt
        ON vc.file_path = vt.file_path
    WHERE vt.file_path IS NULL;

    RETURN 'Video transcription complete — new files processed';
END;

-- Stored procedure: incremental brand mention analysis on video transcripts
CREATE OR REPLACE PROCEDURE ANALYZE_VIDEO_BRAND_MENTIONS()
RETURNS STRING
LANGUAGE SQL
AS
BEGIN
    INSERT INTO VIDEO_BRAND_MENTIONS (file_path, file_name, brand_analysis, transcribed_at)
    SELECT
        t.file_path,
        t.file_name,
        AI_COMPLETE(
            'claude-sonnet-4-6',
            PROMPT('You are a brand intelligence analyst. Analyze this transcript for brand mentions, sentiment, and marketing insights.
Transcript:
{0}
Extract all brand mentions with context, sentiment, and whether the mention is organic or paid.
Respond in JSON only.', TO_VARCHAR(PARSE_JSON(t.transcription_result:value):text))
        ),
        t.transcribed_at
    FROM VIDEO_TRANSCRIPTIONS t
    LEFT JOIN VIDEO_BRAND_MENTIONS vbm
        ON t.file_path = vbm.file_path
    WHERE vbm.file_path IS NULL
      AND TO_VARCHAR(t.transcription_result:error) IS NULL;

    RETURN 'Video brand mention analysis complete — new transcripts processed';
END;

-- Run once at setup (order matters: transcribe first, then analyze)
CALL TRANSCRIBE_VIDEO();
CALL ANALYZE_VIDEO_BRAND_MENTIONS();

-- Scheduled task chain: transcription runs first, brand analysis follows
CREATE OR REPLACE TASK VIDEO_TRANSCRIPTION_TASK
    WAREHOUSE = AI_MEDIA_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL TRANSCRIBE_VIDEO();

CREATE OR REPLACE TASK VIDEO_BRAND_MENTIONS_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER VIDEO_TRANSCRIPTION_TASK
AS
    CALL ANALYZE_VIDEO_BRAND_MENTIONS();

ALTER TASK VIDEO_BRAND_MENTIONS_TASK RESUME;
ALTER TASK VIDEO_TRANSCRIPTION_TASK RESUME;
