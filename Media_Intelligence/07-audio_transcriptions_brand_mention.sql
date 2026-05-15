USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

-- Persistent target tables
CREATE TABLE IF NOT EXISTS AUDIO_TRANSCRIPTIONS (
    file_path           STRING,
    file_name           STRING,
    transcription_result VARIANT,
    transcribed_at      TIMESTAMP_LTZ
);

CREATE TABLE IF NOT EXISTS AUDIO_BRAND_MENTIONS (
    file_path       STRING,
    file_name       STRING,
    brand_analysis  VARIANT,
    transcribed_at  TIMESTAMP_LTZ
);

-- Stored procedure: incremental audio transcription
CREATE OR REPLACE PROCEDURE TRANSCRIBE_AUDIO()
RETURNS STRING
LANGUAGE SQL
AS
BEGIN
    INSERT INTO AUDIO_TRANSCRIPTIONS (file_path, file_name, transcription_result, transcribed_at)
    SELECT
        ac.file_path,
        ac.file_name,
        AI_TRANSCRIBE(ac.audio_file, {}, TRUE),
        CURRENT_TIMESTAMP()
    FROM AUDIO_CATALOG ac
    LEFT JOIN AUDIO_TRANSCRIPTIONS at
        ON ac.file_path = at.file_path
    WHERE at.file_path IS NULL;

    RETURN 'Audio transcription complete — new files processed';
END;

-- Stored procedure: incremental brand mention analysis on transcripts
CREATE OR REPLACE PROCEDURE ANALYZE_AUDIO_BRAND_MENTIONS()
RETURNS STRING
LANGUAGE SQL
AS
BEGIN
    INSERT INTO AUDIO_BRAND_MENTIONS (file_path, file_name, brand_analysis, transcribed_at)
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
    FROM AUDIO_TRANSCRIPTIONS t
    LEFT JOIN AUDIO_BRAND_MENTIONS abm
        ON t.file_path = abm.file_path
    WHERE abm.file_path IS NULL
      AND t.transcription_result:error IS NULL;

    RETURN 'Audio brand mention analysis complete — new transcripts processed';
END;

-- Run once at setup (order matters: transcribe first, then analyze)
CALL TRANSCRIBE_AUDIO();
CALL ANALYZE_AUDIO_BRAND_MENTIONS();

-- Scheduled task chain: transcription runs first, brand analysis follows
CREATE OR REPLACE TASK AUDIO_TRANSCRIPTION_TASK
    WAREHOUSE = AI_MEDIA_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL TRANSCRIBE_AUDIO();

CREATE OR REPLACE TASK AUDIO_BRAND_MENTIONS_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER AUDIO_TRANSCRIPTION_TASK
AS
    CALL ANALYZE_AUDIO_BRAND_MENTIONS();

ALTER TASK AUDIO_BRAND_MENTIONS_TASK RESUME;
ALTER TASK AUDIO_TRANSCRIPTION_TASK RESUME;
