USE ROLE ACCOUNTADMIN;
USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS;
USE WAREHOUSE AI_MEDIA_WH;

-- Persistent target table
CREATE TABLE IF NOT EXISTS COMPLIANCE_RESULTS (
    file_path       STRING,
    file_name       STRING,
    compliance_json VARIANT,
    analyzed_at     TIMESTAMP_LTZ
);

-- Stored procedure: incremental sponsored content compliance analysis
CREATE OR REPLACE PROCEDURE ANALYZE_COMPLIANCE()
RETURNS STRING
LANGUAGE SQL
AS
BEGIN
    INSERT INTO COMPLIANCE_RESULTS (file_path, file_name, compliance_json, analyzed_at)
    SELECT
        vc.file_path,
        vc.file_name,
        AI_COMPLETE(
            'gemini-3.1-pro',
            'You are a brand compliance auditor. Analyze this sponsored content video for guideline adherence.
Evaluate:
- Brand placement quality (prominent, natural, forced, hidden)
- Messaging alignment with typical brand values (family-friendly, premium, edgy, etc.)
- Tone consistency (does the creator tone match brand expectations?)
- Disclosure compliance (is sponsorship clearly disclosed per FTC/ASA guidelines?)
- Safety issues (profanity, controversial topics, competitor mentions, off-brand imagery)
- Overall brand-safe score (1-10)
Respond in JSON only.',
            vc.video_file,
            {},
            {
                'type': 'json',
                'schema': {
                    'type': 'object',
                    'properties': {
                        'brand_placement_quality': {'type': 'string', 'enum': ['excellent', 'good', 'acceptable', 'poor', 'hidden']},
                        'brand_placement_timing_seconds': {'type': 'array', 'items': {'type': 'number'}},
                        'messaging_alignment': {'type': 'string', 'enum': ['fully_aligned', 'mostly_aligned', 'partially_aligned', 'misaligned']},
                        'tone_assessment': {
                            'type': 'object',
                            'properties': {
                                'creator_tone': {'type': 'string'},
                                'tone_brand_fit': {'type': 'string', 'enum': ['excellent', 'good', 'fair', 'poor']},
                                'tone_notes': {'type': 'string'}
                            },
                            'required': ['creator_tone', 'tone_brand_fit']
                        },
                        'disclosure_compliance': {
                            'type': 'object',
                            'properties': {
                                'disclosure_present': {'type': 'boolean'},
                                'disclosure_type': {'type': 'string'},
                                'disclosure_timing': {'type': 'string'},
                                'ftc_compliant': {'type': 'boolean'}
                            },
                            'required': ['disclosure_present', 'ftc_compliant']
                        },
                        'safety_flags': {
                            'type': 'array',
                            'items': {
                                'type': 'object',
                                'properties': {
                                    'flag_type': {'type': 'string', 'enum': ['profanity', 'competitor_mention', 'controversial_topic', 'off_brand_imagery', 'alcohol', 'violence', 'sexual_content', 'political']},
                                    'severity': {'type': 'string', 'enum': ['low', 'medium', 'high', 'critical']},
                                    'description': {'type': 'string'},
                                    'timestamp_approx': {'type': 'string'}
                                },
                                'required': ['flag_type', 'severity', 'description']
                            }
                        },
                        'brand_safety_score': {'type': 'number'},
                        'approval_recommendation': {'type': 'string', 'enum': ['approve', 'approve_with_edits', 'reject', 'escalate']},
                        'required_edits': {'type': 'array', 'items': {'type': 'string'}}
                    },
                    'required': ['brand_placement_quality', 'messaging_alignment', 'tone_assessment',
                                 'disclosure_compliance', 'safety_flags', 'brand_safety_score',
                                 'approval_recommendation']
                }
            }
        ),
        CURRENT_TIMESTAMP()
    FROM VIDEO_CATALOG vc
    LEFT JOIN COMPLIANCE_RESULTS cr
        ON vc.file_path = cr.file_path
    WHERE cr.file_path IS NULL;

    RETURN 'Compliance analysis complete — new files processed';
END;

-- Run once at setup
CALL ANALYZE_COMPLIANCE();

-- Scheduled task: process new files every 5 minutes
CREATE OR REPLACE TASK COMPLIANCE_TASK
    WAREHOUSE = AI_MEDIA_WH
    SCHEDULE = '5 MINUTE'
AS
    CALL ANALYZE_COMPLIANCE();

ALTER TASK COMPLIANCE_TASK RESUME;
