import os
import snowflake.connector

conn = snowflake.connector.connect(
    connection_name=os.getenv("SNOWFLAKE_CONNECTION_NAME") or "default"
)
cur = conn.cursor()

cur.execute("USE ROLE ACCOUNTADMIN")
cur.execute("USE SCHEMA MEDIA_INTELLIGENCE.BRAND_INSIGHTS")
cur.execute("USE WAREHOUSE AI_MEDIA_WH")

base = os.path.dirname(os.path.abspath(__file__))

for fname in ["streamlit_app.py", "pyproject.toml"]:
    local_path = os.path.join(base, fname)
    cur.execute(
        f"PUT 'file://{local_path}' @STREAMLIT_STAGE/app AUTO_COMPRESS=FALSE OVERWRITE=TRUE"
    )
    print(f"Uploaded {fname}")

cur.execute("""
    CREATE OR REPLACE STREAMLIT MEDIA_INTELLIGENCE_DASHBOARD
    FROM '@MEDIA_INTELLIGENCE.BRAND_INSIGHTS.STREAMLIT_STAGE/app'
    MAIN_FILE = 'streamlit_app.py'
    RUNTIME_NAME = 'SYSTEM$ST_CONTAINER_RUNTIME_PY3_11'
    COMPUTE_POOL = SYSTEM_COMPUTE_POOL_CPU
    QUERY_WAREHOUSE = AI_MEDIA_WH
    EXTERNAL_ACCESS_INTEGRATIONS = (PYPI_ACCESS)
""")
print("Streamlit object created")

cur.execute("ALTER STREAMLIT MEDIA_INTELLIGENCE_DASHBOARD ADD LIVE VERSION FROM LAST")
print("Live version published")

cur.execute("DESCRIBE STREAMLIT MEDIA_INTELLIGENCE_DASHBOARD")
for row in cur.fetchall():
    print(row)

cur.close()
conn.close()
