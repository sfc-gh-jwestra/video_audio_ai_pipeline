# Media Intelligence Task Design

## Task Dependency Graph

```
                    ┌─────────────────────────────────────────────────────────────────┐
                    │                    SCHEDULED ROOT TASKS                          │
                    │                    (run on their own timer)                      │
                    └─────────────────────────────────────────────────────────────────┘

 ┌──────────────────────┐   ┌──────────────────────┐
 │  SYNC_VIDEO_CATALOG  │   │  SYNC_AUDIO_CATALOG  │
 │  ⏱ every 1 min       │   │  ⏱ every 1 min       │
 │  (stream-triggered)  │   │  (stream-triggered)  │
 └──────────────────────┘   └──────────────────────┘
           │                           │
           ▼                           ▼
   VIDEO_CATALOG table          AUDIO_CATALOG table
           │                           │
     ┌─────┼──────────────┬────────────┘
     │     │              │            │
     ▼     ▼              ▼            ▼
┌────────────────┐ ┌───────────┐ ┌───────────┐ ┌──────────────────────────┐
│BRAND_SENTIMENT │ │ PRODUCT_  │ │COMPLIANCE │ │  CONTENT_MODERATION_TASK │
│    _TASK       │ │TREND_TASK │ │   _TASK   │ │                          │
│ ⏱ every 5 min │ │⏱ every 5m │ │⏱ every 5m │ │  ⏱ every 5 min           │
└────────────────┘ └───────────┘ └───────────┘ └──────────────────────────┘
        │                │             │                    │
        ▼                ▼             ▼                    ▼
 BRAND_SENTIMENT   PRODUCT_TREND  COMPLIANCE      CONTENT_MODERATION
    _RESULTS         _RESULTS      _RESULTS           _RESULTS


┌──────────────────────────┐         ┌─────────────────────────┐
│ VIDEO_TRANSCRIPTION_TASK │         │ AUDIO_TRANSCRIPTION_TASK│
│ ⏱ every 5 min            │         │ ⏱ every 5 min           │
└─────────────┬────────────┘         └────────────┬────────────┘
              │                                    │
              ▼                                    ▼
┌──────────────────────────┐         ┌─────────────────────────┐
│VIDEO_BRAND_MENTIONS_TASK │         │AUDIO_BRAND_MENTIONS_TASK│
│ (AFTER transcription)    │         │ (AFTER transcription)   │
└──────────────────────────┘         └─────────────────────────┘
              │                                    │
              ▼                                    ▼
     VIDEO_BRAND_MENTIONS               AUDIO_BRAND_MENTIONS


              ┌────────────────────────────────────────────┐
              │         ALL RESULTS FEED INTO:             │
              │                                            │
              │    VIDEO_FULL_INTELLIGENCE (VIEW)          │
              │    V_BRAND_SENTIMENT_FLAT (VIEW)           │
              │    V_CONTENT_SAFETY_SUMMARY (VIEW)         │
              │    V_COMPLIANCE_DASHBOARD (VIEW)           │
              └────────────────────────────────────────────┘
```

## Task Inventory

| Root Task (scheduled) | Schedule | Child Task (AFTER) |
|---|---|---|
| `SYNC_VIDEO_CATALOG` | 1 min (stream-conditional) | — |
| `SYNC_AUDIO_CATALOG` | 1 min (stream-conditional) | — |
| `BRAND_SENTIMENT_TASK` | 5 min | — |
| `PRODUCT_TREND_TASK` | 5 min | — |
| `COMPLIANCE_TASK` | 5 min | — |
| `CONTENT_MODERATION_TASK` | 5 min | — |
| `VIDEO_TRANSCRIPTION_TASK` | 5 min | `VIDEO_BRAND_MENTIONS_TASK` |
| `AUDIO_TRANSCRIPTION_TASK` | 5 min | `AUDIO_BRAND_MENTIONS_TASK` |

## Design Notes

- **6 independent root tasks** fire every 5 minutes (plus 2 catalog sync tasks on 1-minute).
- The only dependency chains are the transcription → brand mentions pairs, which use `AFTER` to guarantee the transcript exists before analysis runs.
- The catalog sync tasks use stream conditions (`SYSTEM$STREAM_HAS_DATA`) so they only consume compute when new files arrive.
- All analysis procedures are incremental (`LEFT JOIN ... WHERE IS NULL`) — they skip already-processed files regardless of how often the task fires.
- The 4 video analysis tasks (brand sentiment, product trends, compliance, content moderation) run in parallel since they are independent analyses of the same source data.
- Downstream views (`VIDEO_FULL_INTELLIGENCE`, `V_BRAND_SENTIMENT_FLAT`, etc.) require no task — they read live from the result tables.

## Alternative DAG Approach

Instead of 8 independent root tasks, the pipeline could be consolidated into 2 DAGs (one per media type) where analysis tasks run `AFTER` their catalog sync:

```
SYNC_VIDEO_CATALOG (root, 5 min, stream-conditional)
    ├── BRAND_SENTIMENT_TASK (AFTER sync)
    ├── PRODUCT_TREND_TASK (AFTER sync)
    ├── COMPLIANCE_TASK (AFTER sync)
    ├── CONTENT_MODERATION_TASK (AFTER sync)
    └── VIDEO_TRANSCRIPTION_TASK (AFTER sync)
            └── VIDEO_BRAND_MENTIONS_TASK (AFTER transcription)

SYNC_AUDIO_CATALOG (root, 5 min, stream-conditional)
    └── AUDIO_TRANSCRIPTION_TASK (AFTER sync)
            └── AUDIO_BRAND_MENTIONS_TASK (AFTER transcription)
```

### Benefits

| Benefit | Impact |
|---|---|
| **No wasted runs** | Analysis tasks only fire when the catalog sync actually ran (new files detected via stream). Currently, analysis tasks fire every 5 min even when nothing is new. |
| **Guaranteed ordering** | Analysis always runs on a fresh catalog. No race condition where a task fires just before a sync adds new rows. |
| **Single schedule to manage** | Change the root task timer once; all children follow. |
| **Operational clarity** | `TASK_HISTORY()` shows a single tree execution per pipeline run instead of 8 independent histories. |
| **Sibling parallelism** | Snowflake runs sibling `AFTER` tasks concurrently — sentiment, trends, compliance, and moderation still execute in parallel. |

### Downsides

| Downside | Impact |
|---|---|
| **Single point of failure** | If the root sync task errors, no downstream analysis runs. Independent tasks can still process the existing backlog. |
| **Coupled cadence** | All analysis runs at the same frequency as sync. Cannot run compliance every 30 min while sentiment runs every 5 min. |
| **Tighter coupling** | Harder to reason about if one analysis type needs a fundamentally different trigger condition. |

### When to Prefer Each Approach

| Scenario | Recommended |
|---|---|
| All analysis should run only when new data arrives | DAG |
| Different analysis types need different schedules | Independent |
| Pipeline is small, operational simplicity matters | DAG |
| Individual analyses may be paused/resumed independently | Independent |
| Cost optimization is a priority (avoid empty runs) | DAG |
| Fault isolation is a priority | Independent |

### Migration SQL (if adopting the DAG approach)

```sql
-- Suspend current independent tasks
ALTER TASK BRAND_SENTIMENT_TASK SUSPEND;
ALTER TASK PRODUCT_TREND_TASK SUSPEND;
ALTER TASK COMPLIANCE_TASK SUSPEND;
ALTER TASK CONTENT_MODERATION_TASK SUSPEND;
ALTER TASK VIDEO_TRANSCRIPTION_TASK SUSPEND;
ALTER TASK VIDEO_BRAND_MENTIONS_TASK SUSPEND;
ALTER TASK AUDIO_TRANSCRIPTION_TASK SUSPEND;
ALTER TASK AUDIO_BRAND_MENTIONS_TASK SUSPEND;

-- Recreate as DAG children of SYNC_VIDEO_CATALOG
CREATE OR REPLACE TASK BRAND_SENTIMENT_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER SYNC_VIDEO_CATALOG
AS
    CALL ANALYZE_BRAND_SENTIMENT();

CREATE OR REPLACE TASK PRODUCT_TREND_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER SYNC_VIDEO_CATALOG
AS
    CALL ANALYZE_PRODUCT_TRENDS();

CREATE OR REPLACE TASK COMPLIANCE_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER SYNC_VIDEO_CATALOG
AS
    CALL ANALYZE_COMPLIANCE();

CREATE OR REPLACE TASK CONTENT_MODERATION_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER SYNC_VIDEO_CATALOG
AS
    CALL ANALYZE_CONTENT_MODERATION();

CREATE OR REPLACE TASK VIDEO_TRANSCRIPTION_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER SYNC_VIDEO_CATALOG
AS
    CALL TRANSCRIBE_VIDEO();

CREATE OR REPLACE TASK VIDEO_BRAND_MENTIONS_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER VIDEO_TRANSCRIPTION_TASK
AS
    CALL ANALYZE_VIDEO_BRAND_MENTIONS();

-- Recreate as DAG children of SYNC_AUDIO_CATALOG
CREATE OR REPLACE TASK AUDIO_TRANSCRIPTION_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER SYNC_AUDIO_CATALOG
AS
    CALL TRANSCRIBE_AUDIO();

CREATE OR REPLACE TASK AUDIO_BRAND_MENTIONS_TASK
    WAREHOUSE = AI_MEDIA_WH
    AFTER AUDIO_TRANSCRIPTION_TASK
AS
    CALL ANALYZE_AUDIO_BRAND_MENTIONS();

-- Resume in reverse dependency order (children first)
ALTER TASK VIDEO_BRAND_MENTIONS_TASK RESUME;
ALTER TASK VIDEO_TRANSCRIPTION_TASK RESUME;
ALTER TASK BRAND_SENTIMENT_TASK RESUME;
ALTER TASK PRODUCT_TREND_TASK RESUME;
ALTER TASK COMPLIANCE_TASK RESUME;
ALTER TASK CONTENT_MODERATION_TASK RESUME;
ALTER TASK AUDIO_BRAND_MENTIONS_TASK RESUME;
ALTER TASK AUDIO_TRANSCRIPTION_TASK RESUME;

-- Adjust root task schedule (sync now drives everything)
ALTER TASK SYNC_VIDEO_CATALOG SET SCHEDULE = '5 MINUTE';
ALTER TASK SYNC_AUDIO_CATALOG SET SCHEDULE = '5 MINUTE';
ALTER TASK SYNC_VIDEO_CATALOG RESUME;
ALTER TASK SYNC_AUDIO_CATALOG RESUME;
```

### Recommendation

For this pipeline, the **DAG approach is the better fit** because:
1. The stream-conditional sync tasks already gate on new data — making children inherit this "only run when needed" behavior eliminates empty analysis runs.
2. All analysis types logically operate on the same trigger (new files uploaded).
3. The procedures are idempotent, so even if ordering is slightly off during migration, no data corruption occurs.
