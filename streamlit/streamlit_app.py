import streamlit as st
import pandas as pd
import json
import plotly.express as px
import plotly.graph_objects as go
import _snowflake
from snowflake.snowpark.context import get_active_session

session = get_active_session()
st.set_page_config(page_title="Demand Forecast Optimization", layout="wide", page_icon="chart")

RISK_COLORS = {"STOCKOUT": "#E74C3C", "LOW": "#F39C12", "HEALTHY": "#2ECC71", "OVERSTOCK": "#3498DB"}

page = st.sidebar.radio("Navigation", ["Overview", "Forecast Accuracy", "Inventory Health", "Demand Signals", "Iceberg Export (AWS Glue)", "Ask Demand", "AWS Architecture"], label_visibility="collapsed")
st.sidebar.divider()
st.sidebar.markdown("### Demand Optimization")
st.sidebar.caption("Forecast accuracy, inventory risk, and demand signals across 500 SKUs / 15 warehouses")


@st.cache_data(ttl=60)
def load_forecast():
    df = session.sql("SELECT * FROM MANUFACTURING_DEMAND.CURATED.FORECAST_ACCURACY ORDER BY WEEK_START").to_pandas()
    for c in ["AVG_ACCURACY_PCT", "BIAS", "UNITS_OVER_FORECAST", "UNITS_UNDER_FORECAST", "RECORD_COUNT"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


@st.cache_data(ttl=60)
def load_inventory():
    df = session.sql("SELECT * FROM MANUFACTURING_DEMAND.CURATED.INVENTORY_HEALTH").to_pandas()
    for c in ["AVG_ON_HAND", "DAYS_OF_SUPPLY", "VALUE_AT_RISK"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


@st.cache_data(ttl=60)
def load_signals():
    df = session.sql("SELECT * FROM MANUFACTURING_DEMAND.CURATED.DEMAND_SIGNALS ORDER BY VELOCITY_RANK").to_pandas()
    for c in ["UNITS_7D", "UNITS_30D", "AVG_DAILY_7D", "AVG_DAILY_30D", "GROWTH_RATE_PCT"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df


if page == "Overview":
    st.title("Demand Forecast Optimization")
    st.caption("Forecast accuracy, inventory health, and demand signal analysis")
    fa = load_forecast()
    inv = load_inventory()

    elec_acc = fa[fa["CATEGORY"] == "Electronics"]["AVG_ACCURACY_PCT"].mean()
    overall_acc = fa["AVG_ACCURACY_PCT"].mean()
    stockout = int((inv["RISK_LEVEL"] == "STOCKOUT").sum())
    low = int((inv["RISK_LEVEL"] == "LOW").sum())
    overstock = int((inv["RISK_LEVEL"] == "OVERSTOCK").sum())
    var_total = inv["VALUE_AT_RISK"].sum()

    st.error(f"INCIDENT: Electronics forecast accuracy {elec_acc:.1f}% (target 85%) - {stockout} SKUs in STOCKOUT, {low} LOW, ${var_total/1e6:.1f}M value at risk")

    c1, c2, c3, c4, c5 = st.columns(5)
    c1.metric("Avg Forecast Accuracy", f"{overall_acc:.1f}%", delta=f"{overall_acc - 85:+.1f}% vs target")
    c2.metric("Stockout Risk", stockout, delta=f"{stockout} SKUs", delta_color="inverse")
    c3.metric("Low Stock", low, delta=f"{low} SKUs", delta_color="inverse")
    c4.metric("Overstock", overstock, delta=f"{overstock} SKUs", delta_color="inverse")
    c5.metric("Value at Risk", f"${var_total/1e6:.1f}M")

    st.divider()
    cc1, cc2 = st.columns(2)
    with cc1:
        cat = fa.groupby("CATEGORY")["AVG_ACCURACY_PCT"].mean().reset_index().sort_values("AVG_ACCURACY_PCT")
        fig = px.bar(cat, x="AVG_ACCURACY_PCT", y="CATEGORY", orientation="h", color="AVG_ACCURACY_PCT", color_continuous_scale="RdYlGn", range_color=[40, 100], title="Avg Forecast Accuracy by Category")
        fig.add_vline(x=85, line_dash="dash", line_color="green", annotation_text="Target 85%")
        fig.update_layout(height=350, margin=dict(t=40, b=10), coloraxis_showscale=False)
        st.plotly_chart(fig, use_container_width=True)
    with cc2:
        rc = inv["RISK_LEVEL"].value_counts().reset_index()
        rc.columns = ["RISK_LEVEL", "COUNT"]
        fig = px.pie(rc, names="RISK_LEVEL", values="COUNT", color="RISK_LEVEL", color_discrete_map=RISK_COLORS, title="Inventory Risk Distribution", hole=0.4)
        fig.update_layout(height=350, margin=dict(t=40, b=10))
        st.plotly_chart(fig, use_container_width=True)

elif page == "Forecast Accuracy":
    st.title("Forecast Accuracy")
    st.caption("Weekly accuracy by product category vs 85% target")
    fa = load_forecast()
    if fa.empty:
        st.info("No data."); st.stop()

    fig = px.line(fa, x="WEEK_START", y="AVG_ACCURACY_PCT", color="CATEGORY", title="Forecast Accuracy by Category Over Time", markers=True)
    fig.add_hline(y=85, line_dash="dash", line_color="green", annotation_text="Target 85%")
    fig.update_layout(height=420, margin=dict(t=40, b=10), yaxis=dict(range=[40, 100], title="Accuracy %"))
    st.plotly_chart(fig, use_container_width=True)

    cc1, cc2 = st.columns(2)
    with cc1:
        bias = fa.groupby("CATEGORY")["BIAS"].mean().reset_index().sort_values("BIAS")
        fig = px.bar(bias, x="BIAS", y="CATEGORY", orientation="h", color="BIAS", color_continuous_scale="RdBu", color_continuous_midpoint=0, title="Forecast Bias by Category (forecast - actual)")
        fig.update_layout(height=350, margin=dict(t=40, b=10), coloraxis_showscale=False)
        st.plotly_chart(fig, use_container_width=True)
    with cc2:
        ou = fa.groupby("CATEGORY")[["UNITS_OVER_FORECAST", "UNITS_UNDER_FORECAST"]].sum().reset_index().melt(id_vars="CATEGORY", var_name="DIRECTION", value_name="UNITS")
        fig = px.bar(ou, x="CATEGORY", y="UNITS", color="DIRECTION", barmode="group", title="Over vs Under-Forecast Units", color_discrete_map={"UNITS_OVER_FORECAST": "#3498DB", "UNITS_UNDER_FORECAST": "#E74C3C"})
        fig.update_layout(height=350, margin=dict(t=40, b=10))
        st.plotly_chart(fig, use_container_width=True)

elif page == "Inventory Health":
    st.title("Inventory Health")
    st.caption("Days-of-supply analysis: stockout risk, low stock, healthy, and overstock")
    inv = load_inventory()
    if inv.empty:
        st.info("No data."); st.stop()

    cc1, cc2 = st.columns(2)
    with cc1:
        rc = inv["RISK_LEVEL"].value_counts().reset_index()
        rc.columns = ["RISK_LEVEL", "COUNT"]
        fig = px.pie(rc, names="RISK_LEVEL", values="COUNT", color="RISK_LEVEL", color_discrete_map=RISK_COLORS, title="Inventory Risk Distribution", hole=0.4)
        fig.update_layout(height=380, margin=dict(t=40, b=10))
        st.plotly_chart(fig, use_container_width=True)
    with cc2:
        cv = inv.groupby("CATEGORY")["VALUE_AT_RISK"].sum().reset_index().sort_values("VALUE_AT_RISK", ascending=True)
        cv["VAR_M"] = cv["VALUE_AT_RISK"] / 1e6
        fig = px.bar(cv, x="VAR_M", y="CATEGORY", orientation="h", color="VAR_M", color_continuous_scale="OrRd", title="Value at Risk by Category ($M)", text_auto=".1f")
        fig.update_layout(height=380, margin=dict(t=40, b=10), coloraxis_showscale=False, xaxis_title="$M")
        st.plotly_chart(fig, use_container_width=True)

    st.subheader("Critical Items (Stockout / Low)")
    crit = inv[inv["RISK_LEVEL"].isin(["STOCKOUT", "LOW"])].sort_values("DAYS_OF_SUPPLY").head(30)
    if not crit.empty:
        st.dataframe(crit[["PRODUCT_NAME", "CATEGORY", "WAREHOUSE_NAME", "AVG_ON_HAND", "DAYS_OF_SUPPLY", "RISK_LEVEL", "VALUE_AT_RISK"]], use_container_width=True, hide_index=True)

    st.subheader("Overstock (Capital Tied Up)")
    over = inv[inv["RISK_LEVEL"] == "OVERSTOCK"].sort_values("VALUE_AT_RISK", ascending=False).head(15)
    if not over.empty:
        st.dataframe(over[["PRODUCT_NAME", "CATEGORY", "WAREHOUSE_NAME", "AVG_ON_HAND", "DAYS_OF_SUPPLY", "VALUE_AT_RISK"]], use_container_width=True, hide_index=True)

elif page == "Demand Signals":
    st.title("Demand Signals")
    st.caption("Top growing SKUs and velocity ranks")
    sig = load_signals()
    if sig.empty:
        st.info("No data."); st.stop()

    c1, c2, c3 = st.columns(3)
    c1.metric("Tracked SKUs", len(sig))
    c2.metric("Avg 7D Daily", f"{sig['AVG_DAILY_7D'].mean():.1f}")
    c3.metric("High Growth (>20%)", int((sig["GROWTH_RATE_PCT"] > 20).sum()))

    cc1, cc2 = st.columns(2)
    with cc1:
        top = sig.nlargest(15, "GROWTH_RATE_PCT")
        fig = px.bar(top.sort_values("GROWTH_RATE_PCT"), x="GROWTH_RATE_PCT", y="PRODUCT_NAME", orientation="h", color="CATEGORY", title="Top 15 Growing SKUs (% 7d vs 30d)")
        fig.update_layout(height=500, margin=dict(t=40, b=10, l=180))
        st.plotly_chart(fig, use_container_width=True)
    with cc2:
        vel = sig.nsmallest(15, "VELOCITY_RANK") if "VELOCITY_RANK" in sig.columns else sig.head(15)
        fig = px.bar(vel.sort_values("AVG_DAILY_7D"), x="AVG_DAILY_7D", y="PRODUCT_NAME", orientation="h", color="CATEGORY", title="Top 15 by 7d Daily Velocity")
        fig.update_layout(height=500, margin=dict(t=40, b=10, l=180))
        st.plotly_chart(fig, use_container_width=True)

elif page == "Iceberg Export (AWS Glue)":
    st.title("Iceberg Forecast Export")
    st.caption("Apache Iceberg on S3 + AWS Glue catalog `mfg_demand_iceberg` -> queryable from Athena & QuickSight")
    try:
        s = session.sql("SELECT * FROM MANUFACTURING_DEMAND.LAKE.VW_FORECAST_ICEBERG_STATS").to_pandas().iloc[0]
        c1, c2, c3, c4, c5 = st.columns(5)
        c1.metric("Rows Exported", f"{int(s['ROW_COUNT']):,}")
        c2.metric("Format", "Apache Iceberg")
        c3.metric("Catalog", "AWS Glue")
        c4.metric("Distinct Categories", int(s["DISTINCT_CATEGORIES"]))
        c5.metric("Avg Accuracy %", f"{float(s['AVG_ACCURACY_PCT']):.1f}")
        st.success(f"{int(s['ROW_COUNT']):,} forecast rows exported as Apache Iceberg under `s3://sg-retail-demos-2026/iceberg/manufacturing-demand/forecast/`. Glue catalog `mfg_demand_iceberg` registers the table; Athena and QuickSight read directly from S3 — no copy, no sync.")
        sample = session.sql("SELECT * FROM MANUFACTURING_DEMAND.LAKE.FORECAST_ICEBERG SAMPLE (200 ROWS)").to_pandas()
        st.subheader("Sample (first 200 rows)")
        st.dataframe(sample, use_container_width=True)
        st.subheader("Athena query (paste into Athena console)")
        st.code("""SELECT category, AVG(accuracy_pct) avg_acc, COUNT(*) rows
FROM mfg_demand_iceberg.forecast_iceberg
GROUP BY category
ORDER BY avg_acc;""", language="sql")
    except Exception as e:
        st.error(f"Iceberg export error: {e}")

elif page == "Ask Demand":
    st.title("Ask the Data")
    st.caption("Natural language questions powered by Cortex Analyst")
    samples = ["Which category has lowest forecast accuracy?", "How many SKUs are at stockout risk?", "What is the total value at risk?"]
    sample = st.selectbox("Sample questions:", [""] + samples)
    q = st.text_input("Or type your question:", value=sample)
    if q:
        with st.spinner("Cortex Analyst..."):
            try:
                body = {"messages": [{"role": "user", "content": [{"type": "text", "text": q}]}], "semantic_view": "MANUFACTURING_DEMAND.AI.DEMAND_PLANNING_SEMANTIC_VIEW"}
                resp = _snowflake.send_snow_api_request("POST", "/api/v2/cortex/analyst/message", {}, {}, body, None, 30000)
                parsed = json.loads(resp["content"])
                if resp["status"] < 400:
                    for block in parsed.get("message", {}).get("content", []):
                        if block.get("type") == "text":
                            st.markdown(block.get("text", ""))
                        elif block.get("type") == "sql":
                            sql = block.get("statement", "")
                            with st.expander("SQL"):
                                st.code(sql, language="sql")
                            try:
                                st.dataframe(session.sql(sql).to_pandas(), use_container_width=True, hide_index=True)
                            except Exception:
                                pass
                else:
                    st.error(parsed)
            except Exception as e:
                st.error(f"Error: {e}")

elif page == "AWS Architecture":
    st.title("AWS Architecture - Open Forecast Data Lake")
    st.caption("Snowflake + Apache Iceberg + AWS Glue + Athena + QuickSight")
    a, b, c, d = st.columns(4)
    a.metric("AWS Hero", "Glue + Athena")
    b.metric("Format", "Apache Iceberg")
    c.metric("Bucket", "sg-retail-demos-2026")
    d.metric("Glue Catalog", "mfg_demand_iceberg")
    st.markdown(
        """
**Data flow**

1. **Snowflake** runs the forecast (`SNOWFLAKE.ML.FORECAST` + ML anomaly detection) on `CURATED` Dynamic Tables.
2. The output lands in `LAKE.FORECAST_ICEBERG` -> Apache Iceberg files on `s3://sg-retail-demos-2026/iceberg/manufacturing-demand/forecast/`.
3. **AWS Glue catalog** `mfg_demand_iceberg` registers the table. Schema and partitions stay in sync because Iceberg is the source of truth.
4. **Amazon Athena** can `SELECT * FROM mfg_demand_iceberg.forecast_iceberg` with no copy.
5. **QuickSight** dashboard `mfg-demand-dashboard` and the **Amazon Q topic** `mfg-demand-q` consume the same governed forecast either via Snowflake or via Athena/Iceberg, depending on the consumer.

**Why this matters**

- One forecast, two consumption surfaces (Snowflake compute + AWS data lake)
- No nightly copy job, no data drift, no separate SLA
- Customers keep their AWS-native BI / ML tools while letting Snowflake run the heavy compute

**ARNs**

- `arn:aws:s3:::sg-retail-demos-2026/iceberg/manufacturing-demand/forecast/`
- `arn:aws:glue:us-west-2:018437500440:catalog/mfg_demand_iceberg`
- `arn:aws:athena:us-west-2:018437500440:workgroup/mfg-demand-wg`
        """
    )
