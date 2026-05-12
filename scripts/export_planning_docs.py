#!/usr/bin/env python3
"""Export planning docs from Snowflake to text files for Bedrock KB ingestion."""
import os
import snowflake.connector

conn = snowflake.connector.connect(connection_name=os.getenv("SNOWFLAKE_CONNECTION_NAME") or "demo43")
cur = conn.cursor()
cur.execute("SELECT DOC_ID, TITLE, CATEGORY, CONTENT FROM MANUFACTURING_DEMAND.RAW.PLANNING_DOCS")

out_dir = "/tmp/planning_docs"
os.makedirs(out_dir, exist_ok=True)

count = 0
for row in cur:
    doc_id, title, category, content = row
    fname = f"{doc_id}_{title.replace(' ', '_').replace('/', '_')[:60]}.txt"
    with open(os.path.join(out_dir, fname), "w") as f:
        f.write(f"Title: {title}\nCategory: {category}\n\n{content}\n")
    count += 1

cur.close()
conn.close()
print(f"Exported {count} docs to {out_dir}")
