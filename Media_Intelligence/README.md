# Media Intelligence

Media Intelligence demonstrates how to setup a video and audio pipeline to perform automated brand and sentiment analysis at production scale on Snowflake. Upload a video and it will use Snowflake multimodal AI FUNCTIONS to discover brands and sentiment towards them both visually (e.g., logos on a jacket) and from audio transcriptions. Then, it will determine sentiment for each. Visualize the results in a dashboard also directly deployed into Snowflake.

### Credits
The project is based off Satish Kumar's Medium article [**Building a Production-Grade Multimodal Video & Audio Intelligence Pipeline with Snowflake Cortex AI**](https://pub.towardsai.net/building-a-production-grade-multimodal-video-audio-intelligence-pipeline-with-snowflake-cortex-ai-686a579486f2). Please take a read on Satish's excellent article and then implement it here. The project takes Satish's initial solution forward in terms of productionizing a Video/Audio AI pipeline. The upgrades applied here include error handling, no more duplicated AI FUNCTION logic across CTAS and TASKs, more efficient triggering and processing of media files, as well as a new Streamlit dashboard to visualize findings on brand sentiment and analysis.

## Deploy whole solution
Using Snowflake CoCo, ask:

"Run .sql files prefixed with 01-12 in order.
Deploy the streamlit application."


## Uploading videos / audios

The AI video/audio pipeline triggeres when new video and audio files land in their respective stage on Snowflake.
Remember the files must support Snowflake codecs and fall within size limits. Check Snowflake documentation for
details. It is best practice to prepare files before landing them in Snowflake. Preparing video/audio files for you is beyond the scope of the project, but there are examples below. For example, use FFMPEG to chunk large videos into smaller 
files (see example in /scripts/chunk_videos.py) and encode them properly (see below). 

AI_COMPLETE - handles 100 MB files

AI_TRANSCRIPT - handles up to 700 MB files

Here's an example of the requirements for `AI_TRANSCRIBE`:

**Supported video formats:** MKV, MP4, OGV, WEBM  
**Required audio codec within video:** FLAC, MP3, OPUS, VORBIS, or WAV

The key constraint is: **video files must contain at least one audio track in FLAC, MP3, OPUS, VORBIS, or WAV format.**

To ensure compliance, re-encode your video with H.264 video + AAC won't work — you need one of the listed audio codecs. The safest ffmpeg command:

```bash
ffmpeg -i input.mov -c:v copy -c:a mp3 -ar 16000 -ac 1 output.mp4
```

Or if you want to normalize everything (video codec included):

```bash
ffmpeg -i input.mov -c:v libx264 -c:a libmp3lame -ar 16000 -ac 1 output.mp4
```

**Explanation:**
- `-c:v copy` (or `libx264`): keeps/re-encodes video as H.264 in MP4 container
- `-c:a libmp3lame`: encodes audio as MP3 (one of the 5 supported codecs)
- `-ar 16000`: resamples to 16kHz (what AI_TRANSCRIBE uses internally anyway)
- `-ac 1`: mono (AI_TRANSCRIBE uses monophonic audio internally)

This also keeps file size down (max 700MB) and respects the 60/120 min duration limits.


## Upgrades & Differences: Source Code vs. Article

### 1. Incremental Processing Architecture (Major Upgrade)

| Aspect | Article | Source Code |
|--------|---------|-------------|
| AI analysis pattern | `CREATE OR REPLACE TABLE ... AS SELECT` (full reprocess every run) | `CREATE TABLE IF NOT EXISTS` + **stored procedures** with `LEFT JOIN ... WHERE IS NULL` (incremental — only new files) |
| Task model | Single `REFRESH_VIDEO_CATALOG` task with `NOT IN` subquery | Proper stored procedures called by tasks; reusable and manually invocable |

With AI FUNCTION code in stored procedures, logic exists one place versus the article which duplicates the AI FUNCTION calls in multiple places. This enables easier refactoring, testing, and troubleshooting your video / audio pipeline components.


### 2. Catalog Sync via Streams (Major Upgrade)

| Article | Source Code |
|---------|-------------|
| Cron-based `INSERT ... WHERE NOT IN (SELECT file_path FROM VIDEO_CATALOG)` every 4 hours | **Stage streams** (`VIDEO_STAGE_STREAM`, `AUDIO_STAGE_STREAM`) with `SYSTEM$STREAM_HAS_DATA` condition — event-driven, 1-minute cadence, only runs when files actually arrive |

### 3. Video Transcription + Brand Mentions (New Phase)

The article only has **audio** transcription in Phase (`07`). The source code adds `07a-video_transcriptions_brand_mention.sql` — transcribing video files and running brand mention analysis on the video transcripts too.

### 4. AI_COMPLETE with `show_details=TRUE` (Technical Fix)

The source code passes `TRUE` as the final argument to AI_COMPLETE (enabling `show_details`), which returns structured output at `structured_output[0]:raw_message`. The article uses the simpler call signature without this flag.

### 5. Dashboard Views Use Different JSON Path

| Article | Source Code |
|---------|-------------|
| `brand_sentiment_json:primary_brand::STRING` | `brand_sentiment_json:structured_output[0]:raw_message:primary_brand::STRING` |

This reflects the actual output structure when `show_details=TRUE` is used.

### 6. Combined Intelligence is a VIEW (not a TABLE)

The article creates `VIDEO_FULL_INTELLIGENCE` as a `TABLE` (CTAS). The source code creates it as a **VIEW** with `PARSE_JSON(...)` unwrapping and **error columns** (`sentiment_error`, `trend_error`, etc.) for observability.

### 7. AI_COMPLETE Brand Mentions Uses Named Parameters + Structured Output

The article uses `PROMPT('...{0}...', col)` syntax. 

The source code uses:
- `model => 'claude-sonnet-4-6'` named parameter syntax
- `CONCAT(...)` instead of `PROMPT()`
- `response_format => {...}` with a full JSON schema (not free-form text)
- Error filtering: `WHERE TO_VARCHAR(t.transcription_result:error) IS NULL`

The article prompt says "Extract all brand mentions with context, sentiment, and whether the mention is organic or paid.
Respond in JSON only.". Unfortunately, 'Respond in JSON only' is not production-ready because the LLM will return different JSON structures each time. Instead, the source code here describes a structure and AI_COMPLETE calls return JSON in the same format making queries and data analysis consistent and easier.

### 8. AI_TRANSCRIBE with Error Handling

Source code wraps `AI_TRANSCRIBE` in `TO_VARIANT(AI_TRANSCRIBE(..., {}, TRUE))` to handle the OBJECT return type when `return_error_details=TRUE`. The article uses bare `AI_TRANSCRIBE(audio_file)`. This is true for video transcription as well.

### 9. Task DAG Design Document

Source includes `media_intelligence_task_design.md` — a comprehensive task dependency graph, alternative DAG approach analysis, and migration SQL. This adds more depth of understanding to the design not detailed in the article including trade-offs and alternatives, if you so choose to implement a different approach.

### 10. Streamlit Dashboard (Entirely New)

You can now visualize your video / audio brand and sentiment information in a dashboard.

The source code includes a full **Streamlit dashboard** (`dashboard/streamlit_app.py`) with:
- KPI metrics row (brands detected, positive %, flagged, compliance failures)
- Three tabs: Brand Sentiment, Content Safety, Compliance
- Altair charts (bar, donut, histogram, grouped bar)
- Deployed to Snowflake (SPCS-backed Streamlit)

### 11. Access Control is More Comprehensive

| Article | Source Code |
|---------|-------------|
| 3 roles, basic SELECT grants | Same 3 roles + procedure USAGE grants, task MONITOR/OPERATE, warehouse USAGE, stream SELECT, **future grants** for all object types |

### 12. Setup Scripts created by stage/step

The article did not provide a source code repository to clone and run your own pipeline. This repo contains SQL code to setup everything you need. It is in .sql scripts prefixed with phase. To setup your whole AI video/audio pipline simply ask Snowflake CoCo: 

**Deploy whole solution**
Run .sql files prefixed with 01-12 in order.
Deploy the streamlit application.

"Run all .sql scripts in order, except 99-teardown.sql and deploy the streamlit app in /dashboard".

### 13. Teardown Script

Source includes `99-teardown.sql` for clean removal — another handy addition, not in the article.

### 14. Task Scheduling

Article uses cron (`0 */4 * * *`). Source uses simple interval (`5 MINUTE` / `1 MINUTE`) which is more appropriate for near-real-time processing. Of course, change your cron to be reflective of your workload.