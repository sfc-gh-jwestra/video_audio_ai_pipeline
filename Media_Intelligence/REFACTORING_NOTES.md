# Refactoring: CTAS → Stored Procedures + Scheduled Tasks

## Problem

All AI analysis tables used `CREATE OR REPLACE TABLE ... AS SELECT` (CTAS). This pattern:

1. **Re-processes everything** on each run (expensive AI_COMPLETE calls repeated on already-analyzed files)
2. **Duplicates logic** if you want both an initial setup script and a scheduled refresh
3. **Replaces the table** each time, breaking downstream references momentarily

## Solution Applied

Each AI analysis file now follows this pattern:

```
┌─────────────────────────────────┐
│  CREATE TABLE IF NOT EXISTS     │  ← Schema lives here (persistent)
├─────────────────────────────────┤
│  CREATE OR REPLACE PROCEDURE    │  ← Logic lives here (single source of truth)
│    INSERT ... WHERE NOT EXISTS  │     Only processes new files (incremental)
├─────────────────────────────────┤
│  CALL procedure()               │  ← Initial setup invocation
├─────────────────────────────────┤
│  CREATE TASK ... SCHEDULE       │  ← Recurring invocation (same procedure)
│    CALL procedure()             │
└─────────────────────────────────┘
```

### Key design decisions:

- **Incremental processing**: `LEFT JOIN ... WHERE IS NULL` ensures only unprocessed files trigger AI calls
- **Idempotent**: Safe to run the procedure any number of times — no duplicates
- **Task chaining**: For dependent steps (transcribe → analyze), uses `AFTER` task dependency
- **Combined view**: `08-combined_intelligence_view.sql` is now a VIEW (not a table), so it always reflects the latest state without needing its own task

## Files Changed

| File | Tables | Procedures | Tasks |
|------|--------|-----------|-------|
| `03-brand_sentiment_analysis.sql` | BRAND_SENTIMENT_RESULTS | ANALYZE_BRAND_SENTIMENT() | BRAND_SENTIMENT_TASK (5 min) |
| `04-product_trend_discovery.sql` | PRODUCT_TREND_RESULTS | ANALYZE_PRODUCT_TRENDS() | PRODUCT_TREND_TASK (5 min) |
| `05-sponsored_content_compliance.sql` | COMPLIANCE_RESULTS | ANALYZE_COMPLIANCE() | COMPLIANCE_TASK (5 min) |
| `06-content_safety_moderation.sql` | CONTENT_MODERATION_RESULTS | ANALYZE_CONTENT_MODERATION() | CONTENT_MODERATION_TASK (5 min) |
| `07-audio_transcrption_brand_mention.sql` | AUDIO_TRANSCRIPTIONS, AUDIO_BRAND_MENTIONS | TRANSCRIBE_AUDIO(), ANALYZE_AUDIO_BRAND_MENTIONS() | AUDIO_TRANSCRIPTION_TASK → AUDIO_BRAND_MENTIONS_TASK (chained) |
| `07a-video_transcriptions_brand_mention.sql` | VIDEO_TRANSCRIPTIONS, VIDEO_BRAND_MENTIONS | TRANSCRIBE_VIDEO(), ANALYZE_VIDEO_BRAND_MENTIONS() | VIDEO_TRANSCRIPTION_TASK → VIDEO_BRAND_MENTIONS_TASK (chained) |
| `08-combined_intelligence_view.sql` | VIDEO_FULL_INTELLIGENCE (VIEW) | — | — |

## Alternatives Considered

### 1. Dynamic Tables (`TARGET_LAG = '5 minutes'`)

**Pros**: No procedure or task needed; Snowflake handles scheduling and incremental refresh automatically.

**Cons**: Dynamic tables may fully recompute the underlying query on each refresh. Since `AI_COMPLETE` is non-deterministic and expensive, this risks re-processing all rows every cycle. Dynamic tables are best suited for deterministic transformations where Snowflake can detect which rows changed.

**Verdict**: Not appropriate for AI function workloads.

### 2. Streams + Tasks (CDC approach)

**Pros**: Snowflake streams capture exactly which rows are new in VIDEO_CATALOG, giving precise change data capture.

**Cons**: Requires creating a stream on VIDEO_CATALOG, and the stream advances on read — so if the task fails mid-run, those rows are consumed and lost. More complex operationally. The `LEFT JOIN WHERE NULL` pattern achieves the same incremental effect without stream management overhead.

**Verdict**: Viable but adds complexity without clear benefit here. Would be better if VIDEO_CATALOG had frequent updates/deletes (not just inserts).

### 3. Re-running the full CTAS via a Task

**Pros**: Simplest code — just wrap the original CTAS in a task.

**Cons**: Re-processes ALL files every 5 minutes. With AI functions costing real money per call, this is wasteful. Also replaces the table each time, which can cause brief downtime for queries.

**Verdict**: Rejected — the original problem statement.

## Task Dependency Graph

```
BRAND_SENTIMENT_TASK (5 min) ─────────────────────────┐
PRODUCT_TREND_TASK (5 min) ───────────────────────────┤
COMPLIANCE_TASK (5 min) ──────────────────────────────┤── All feed into
CONTENT_MODERATION_TASK (5 min) ──────────────────────┤   VIDEO_FULL_INTELLIGENCE (view)
                                                      │
AUDIO_TRANSCRIPTION_TASK (5 min)                      │
    └── AUDIO_BRAND_MENTIONS_TASK (after)             │
                                                      │
VIDEO_TRANSCRIPTION_TASK (5 min)                      │
    └── VIDEO_BRAND_MENTIONS_TASK (after) ────────────┘
```

All analysis tasks run independently on their own 5-minute schedule. The combined intelligence VIEW reads from all result tables with no scheduling needed.

## Access Control Updates (`12-access_control.sql`)

The introduction of stored procedures, tasks, and the table-to-view change required corresponding access control updates:

### 1. Stored Procedure Grants

`MEDIA_ADMIN` can now manually trigger any analysis procedure:

```sql
GRANT USAGE ON PROCEDURE ANALYZE_BRAND_SENTIMENT() TO ROLE MEDIA_ADMIN;
GRANT USAGE ON PROCEDURE ANALYZE_PRODUCT_TRENDS() TO ROLE MEDIA_ADMIN;
-- ... (all 9 procedures)
```

### 2. Task Operations

`MEDIA_ADMIN` can suspend, resume, and inspect task history:

```sql
GRANT MONITOR, OPERATE ON ALL TASKS IN SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS TO ROLE MEDIA_ADMIN;
```

### 3. Warehouse Usage

Required for `MEDIA_ADMIN` to execute procedures manually (tasks run under ACCOUNTADMIN ownership):

```sql
GRANT USAGE ON WAREHOUSE AI_MEDIA_WH TO ROLE MEDIA_ADMIN;
```

### 4. Future Grants

Auto-apply privileges to newly created objects without re-running the access control script:

```sql
GRANT SELECT ON FUTURE TABLES IN SCHEMA ... TO ROLE MEDIA_ANALYST;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA ... TO ROLE MEDIA_ANALYST;
GRANT USAGE ON FUTURE PROCEDURES IN SCHEMA ... TO ROLE MEDIA_ADMIN;
GRANT MONITOR, OPERATE ON FUTURE TASKS IN SCHEMA ... TO ROLE MEDIA_ADMIN;
```

### 5. Analyst Table Access

Added `GRANT SELECT ON ALL TABLES` for `MEDIA_ANALYST` — previously they only had view access, but now the persistent result tables (BRAND_SENTIMENT_RESULTS, etc.) should be queryable directly.

### Summary of Access Control Changes

| Object Type | Privilege | Role | Purpose |
|---|---|---|---|
| All procedures (9) | USAGE | MEDIA_ADMIN | Manual re-runs / debugging |
| All tasks (8) | MONITOR, OPERATE | MEDIA_ADMIN | Suspend/resume/inspect history |
| Warehouse | USAGE | MEDIA_ADMIN | Execute procedures ad-hoc |
| Future procedures | USAGE | MEDIA_ADMIN | Auto-grant on new procs |
| Future tasks | MONITOR, OPERATE | MEDIA_ADMIN | Auto-grant on new tasks |
| All tables | SELECT | MEDIA_ANALYST | Query result tables directly |
| Future tables/views | SELECT | MEDIA_ANALYST | Auto-grant on new tables/views |
