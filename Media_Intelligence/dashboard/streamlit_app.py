import streamlit as st
import altair as alt
import pandas as pd

st.set_page_config(
    page_title="Media Intelligence Dashboard",
    page_icon=":material/monitoring:",
    layout="wide",
)

def get_connection():
    return st.connection("snowflake")


@st.cache_data(ttl=300)
def load_brand_sentiment() -> pd.DataFrame:
    df = get_connection().query("SELECT * FROM V_BRAND_SENTIMENT_FLAT")
    df.columns = df.columns.str.lower()
    return df


@st.cache_data(ttl=300)
def load_top_brands() -> pd.DataFrame:
    df = get_connection().query("""
        SELECT
            detected_brand,
            COUNT(*) AS total_appearances,
            SUM(CASE WHEN brand_specific_sentiment = 'positive' THEN 1 ELSE 0 END) AS positive_count,
            ROUND(positive_count / total_appearances * 100, 1) AS positive_pct
        FROM V_BRAND_SENTIMENT_FLAT
        GROUP BY detected_brand
        ORDER BY total_appearances DESC
        LIMIT 20
    """)
    df.columns = df.columns.str.lower()
    return df


@st.cache_data(ttl=300)
def load_content_safety() -> pd.DataFrame:
    df = get_connection().query("SELECT * FROM V_CONTENT_SAFETY_SUMMARY")
    df.columns = df.columns.str.lower()
    return df


@st.cache_data(ttl=300)
def load_moderation_actions() -> pd.DataFrame:
    df = get_connection().query("""
        SELECT
            file_name,
            safety_rating,
            moderation_action,
            violence_level,
            hate_speech_level,
            age_rating
        FROM V_CONTENT_SAFETY_SUMMARY
        WHERE moderation_action IN ('flag_for_review', 'restrict', 'remove')
        ORDER BY
            CASE moderation_action
                WHEN 'remove' THEN 1
                WHEN 'restrict' THEN 2
                WHEN 'flag_for_review' THEN 3
            END
    """)
    df.columns = df.columns.str.lower()
    return df


@st.cache_data(ttl=300)
def load_compliance() -> pd.DataFrame:
    df = get_connection().query("SELECT * FROM V_COMPLIANCE_DASHBOARD")
    df.columns = df.columns.str.lower()
    return df


@st.cache_data(ttl=300)
def load_compliance_failures() -> pd.DataFrame:
    df = get_connection().query("""
        SELECT
            file_name,
            placement_quality,
            ftc_compliant,
            brand_safety_score,
            approval_recommendation
        FROM V_COMPLIANCE_DASHBOARD
        WHERE approval_recommendation IN ('reject', 'escalate', 'approve_with_edits')
        ORDER BY brand_safety_score ASC
    """)
    df.columns = df.columns.str.lower()
    return df


st.title("Media intelligence dashboard")

sentiment_df = load_brand_sentiment()
safety_df = load_content_safety()
compliance_df = load_compliance()

total_brands = sentiment_df["detected_brand"].nunique() if not sentiment_df.empty else 0
positive_pct = (
    round(
        (sentiment_df["brand_specific_sentiment"] == "positive").sum()
        / len(sentiment_df)
        * 100,
        1,
    )
    if not sentiment_df.empty
    else 0
)
flagged_count = (
    safety_df["moderation_action"]
    .isin(["flag_for_review", "restrict", "remove"])
    .sum()
    if not safety_df.empty
    else 0
)
compliance_fail_count = (
    compliance_df["approval_recommendation"]
    .isin(["reject", "escalate", "approve_with_edits"])
    .sum()
    if not compliance_df.empty
    else 0
)

with st.container(horizontal=True):
    st.metric("Brands detected", total_brands, border=True)
    st.metric("Positive sentiment", f"{positive_pct}%", border=True)
    st.metric("Flagged for moderation", int(flagged_count), border=True)
    st.metric("Compliance failures", int(compliance_fail_count), border=True)

tab_sentiment, tab_safety, tab_compliance = st.tabs(
    [
        ":material/analytics: Brand sentiment",
        ":material/shield: Content safety",
        ":material/verified: Compliance",
    ]
)

with tab_sentiment:
    top_brands_df = load_top_brands()

    col1, col2 = st.columns(2)
    with col1:
        with st.container(border=True):
            st.subheader("Top brands by appearances")
            if not top_brands_df.empty:
                chart = (
                    alt.Chart(top_brands_df)
                    .mark_bar()
                    .encode(
                        x=alt.X("total_appearances:Q", title="Total appearances"),
                        y=alt.Y("detected_brand:N", title="Brand", sort="-x"),
                        tooltip=["detected_brand", "total_appearances", "positive_pct"],
                    )
                    .properties(height=400)
                )
                st.altair_chart(chart)
            else:
                st.info("No brand sentiment data available.")

    with col2:
        with st.container(border=True):
            st.subheader("Sentiment distribution")
            if not sentiment_df.empty:
                sentiment_counts = (
                    sentiment_df["brand_specific_sentiment"]
                    .value_counts()
                    .reset_index()
                )
                sentiment_counts.columns = ["sentiment", "count"]
                chart = (
                    alt.Chart(sentiment_counts)
                    .mark_arc(innerRadius=50)
                    .encode(
                        theta=alt.Theta("count:Q"),
                        color=alt.Color(
                            "sentiment:N",
                            scale=alt.Scale(
                                domain=["positive", "neutral", "negative"],
                                range=["#4CAF50", "#FFC107", "#F44336"],
                            ),
                        ),
                        tooltip=["sentiment", "count"],
                    )
                    .properties(height=400)
                )
                st.altair_chart(chart)
            else:
                st.info("No sentiment data available.")

    with st.container(border=True):
        st.subheader("Brand sentiment details")
        if not sentiment_df.empty:
            st.dataframe(
                sentiment_df[
                    [
                        "file_name",
                        "detected_brand",
                        "brand_specific_sentiment",
                        "brand_role",
                        "sentiment_confidence",
                        "screen_time_pct",
                        "content_category",
                    ]
                ],
                column_config={
                    "sentiment_confidence": st.column_config.ProgressColumn(
                        "Confidence", min_value=0.0, max_value=1.0
                    ),
                    "screen_time_pct": st.column_config.NumberColumn(
                        "Screen time %", format="%.1f%%"
                    ),
                },
                hide_index=True,
            )
        else:
            st.info("No brand sentiment data available.")

with tab_safety:
    col1, col2 = st.columns(2)
    with col1:
        with st.container(border=True):
            st.subheader("Moderation action breakdown")
            if not safety_df.empty:
                action_counts = (
                    safety_df["moderation_action"].value_counts().reset_index()
                )
                action_counts.columns = ["action", "count"]
                chart = (
                    alt.Chart(action_counts)
                    .mark_bar()
                    .encode(
                        x=alt.X("action:N", title="Action", sort="-y"),
                        y=alt.Y("count:Q", title="Count"),
                        color=alt.Color(
                            "action:N",
                            scale=alt.Scale(
                                domain=[
                                    "remove",
                                    "restrict",
                                    "flag_for_review",
                                    "approve",
                                ],
                                range=["#F44336", "#FF9800", "#FFC107", "#4CAF50"],
                            ),
                        ),
                        tooltip=["action", "count"],
                    )
                    .properties(height=300)
                )
                st.altair_chart(chart)
            else:
                st.info("No content safety data available.")

    with col2:
        with st.container(border=True):
            st.subheader("Platform suitability")
            if not safety_df.empty:
                platform_data = pd.DataFrame(
                    {
                        "platform": ["YouTube", "TikTok", "Instagram"],
                        "safe": [
                            safety_df["youtube_safe"].sum(),
                            safety_df["tiktok_safe"].sum(),
                            safety_df["instagram_safe"].sum(),
                        ],
                        "unsafe": [
                            (~safety_df["youtube_safe"].astype(bool)).sum(),
                            (~safety_df["tiktok_safe"].astype(bool)).sum(),
                            (~safety_df["instagram_safe"].astype(bool)).sum(),
                        ],
                    }
                )
                melted = platform_data.melt(
                    id_vars="platform", var_name="status", value_name="count"
                )
                chart = (
                    alt.Chart(melted)
                    .mark_bar()
                    .encode(
                        x=alt.X("platform:N", title="Platform"),
                        y=alt.Y("count:Q", title="Count"),
                        color=alt.Color(
                            "status:N",
                            scale=alt.Scale(
                                domain=["safe", "unsafe"],
                                range=["#4CAF50", "#F44336"],
                            ),
                        ),
                        xOffset="status:N",
                        tooltip=["platform", "status", "count"],
                    )
                    .properties(height=300)
                )
                st.altair_chart(chart)
            else:
                st.info("No platform suitability data available.")

    with st.container(border=True):
        st.subheader("Content requiring moderation")
        moderation_df = load_moderation_actions()
        if not moderation_df.empty:
            st.dataframe(moderation_df, hide_index=True)
        else:
            st.info("No content flagged for moderation.")

with tab_compliance:
    col1, col2 = st.columns(2)
    with col1:
        with st.container(border=True):
            st.subheader("Brand safety score distribution")
            if not compliance_df.empty:
                chart = (
                    alt.Chart(compliance_df)
                    .mark_bar()
                    .encode(
                        x=alt.X(
                            "brand_safety_score:Q",
                            bin=alt.Bin(maxbins=20),
                            title="Safety score",
                        ),
                        y=alt.Y("count():Q", title="Count"),
                    )
                    .properties(height=300)
                )
                st.altair_chart(chart)
            else:
                st.info("No compliance data available.")

    with col2:
        with st.container(border=True):
            st.subheader("Approval recommendation breakdown")
            if not compliance_df.empty:
                rec_counts = (
                    compliance_df["approval_recommendation"]
                    .value_counts()
                    .reset_index()
                )
                rec_counts.columns = ["recommendation", "count"]
                chart = (
                    alt.Chart(rec_counts)
                    .mark_bar()
                    .encode(
                        x=alt.X("recommendation:N", title="Recommendation", sort="-y"),
                        y=alt.Y("count:Q", title="Count"),
                        color=alt.Color(
                            "recommendation:N",
                            scale=alt.Scale(
                                domain=[
                                    "approve",
                                    "approve_with_edits",
                                    "escalate",
                                    "reject",
                                ],
                                range=["#4CAF50", "#FFC107", "#FF9800", "#F44336"],
                            ),
                        ),
                        tooltip=["recommendation", "count"],
                    )
                    .properties(height=300)
                )
                st.altair_chart(chart)
            else:
                st.info("No compliance data available.")

    with st.container(border=True):
        st.subheader("Compliance failures")
        failures_df = load_compliance_failures()
        if not failures_df.empty:
            styled = failures_df.style.background_gradient(
                subset=["brand_safety_score"], cmap="RdYlGn", vmin=0, vmax=100
            )
            st.dataframe(
                styled,
                column_config={
                    "brand_safety_score": st.column_config.NumberColumn(
                        "Safety score", format="%.1f"
                    ),
                },
                hide_index=True,
            )
        else:
            st.info("No compliance failures found.")
