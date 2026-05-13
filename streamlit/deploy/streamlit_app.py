import streamlit as st
import pandas as pd
import json
import plotly.graph_objects as go
import _snowflake
from snowflake.snowpark.context import get_active_session

session = get_active_session()

def coerce_numeric(df, cols=None):
    if df is None or len(df) == 0:
        return df
    target = cols or [c for c in df.columns if df[c].dtype == "object"]
    for c in target:
        try:
            df[c] = pd.Series([float(x) if x is not None else None for x in df[c]], index=df.index, dtype="float64")
        except (TypeError, ValueError):
            pass
    return df

st.set_page_config(page_title="Demand Forecast Optimization", layout="wide", page_icon="chart")

RISK_COLORS = {"STOCKOUT": "#E74C3C", "LOW": "#F39C12", "HEALTHY": "#2ECC71", "OVERSTOCK": "#3498DB"}
ANOMALY_COLORS = {True: "#E74C3C", False: "#2ECC71"}

page = st.sidebar.radio("Navigation", [
    "Overview",
    "Forecast Accuracy",
    "Inventory Health",
    "Demand Anomalies",
    "Demand Signals",
    "Planning Intelligence",
    "Ask Demand"
], label_visibility="collapsed")
st.sidebar.divider()
st.sidebar.markdown("### Demand Optimization")
st.sidebar.caption("500 SKUs / 10 warehouses | Forecast + Anomaly Detection + AI Classify")


@st.cache_data(ttl=60)
def load_forecast():
    df = coerce_numeric(session.sql("SELECT * FROM MANUFACTURING_DEMAND.CURATED.FORECAST_ACCURACY ORDER BY WEEK_START").to_pandas())
    for c in ["AVG_ACCURACY_PCT", "BIAS", "UNITS_OVER_FORECAST", "UNITS_UNDER_FORECAST", "RECORD_COUNT"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    return df

@st.cache_data(ttl=60)
def load_inventory():
    df = coerce_numeric(session.sql("SELECT * FROM MANUFACTURING_DEMAND.CURATED.INVENTORY_HEALTH").to_pandas())
    for c in ["AVG_ON_HAND", "DAYS_OF_SUPPLY", "VALUE_AT_RISK"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    return df

@st.cache_data(ttl=60)
def load_signals():
    df = coerce_numeric(session.sql("SELECT * FROM MANUFACTURING_DEMAND.CURATED.DEMAND_SIGNALS ORDER BY VELOCITY_RANK").to_pandas())
    for c in ["UNITS_7D", "UNITS_30D", "AVG_DAILY_7D", "AVG_DAILY_30D", "GROWTH_RATE_PCT"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    return df

@st.cache_data(ttl=60)
def load_anomalies():
    df = coerce_numeric(session.sql("SELECT * FROM MANUFACTURING_DEMAND.ML.DEMAND_ANOMALY_RESULTS ORDER BY SERIES, TS").to_pandas())
    for c in ["Y", "FORECAST", "LOWER_BOUND", "UPPER_BOUND", "PERCENTILE", "DISTANCE"]:
        if c in df.columns:
            df[c] = pd.to_numeric(df[c], errors="coerce")
    if "SERIES" in df.columns:
        df["SERIES"] = df["SERIES"].astype(str).str.strip('"')
    if "IS_ANOMALY" in df.columns:
        df["IS_ANOMALY"] = df["IS_ANOMALY"].astype(str).str.lower().isin(["true", "1"])
    return df


if page == "Overview":
    st.title("Demand Forecast Optimization")
    st.caption("AI-powered demand consensus: forecast, detect, classify, alert, orchestrate")
    fa = load_forecast()
    inv = load_inventory()
    anom = load_anomalies()

    elec_acc = fa[fa["CATEGORY"] == "Electronics"]["AVG_ACCURACY_PCT"].mean()
    overall_acc = fa["AVG_ACCURACY_PCT"].mean()
    stockout = int((inv["RISK_LEVEL"] == "STOCKOUT").sum())
    low = int((inv["RISK_LEVEL"] == "LOW").sum())
    overstock = int((inv["RISK_LEVEL"] == "OVERSTOCK").sum())
    var_total = inv["VALUE_AT_RISK"].sum()
    elec_anomalies = int(anom[(anom["SERIES"] == "Electronics") & (anom["IS_ANOMALY"] == True)].shape[0])

    st.error(f"INCIDENT: Electronics forecast accuracy {elec_acc:.1f}% (target 85%) — {elec_anomalies} anomalous days detected by ML.ANOMALY_DETECTION — {stockout} SKUs in STOCKOUT, ${var_total/1e6:.1f}M value at risk")

    c1, c2, c3, c4, c5, c6 = st.columns(6)
    c1.metric("Avg Accuracy", f"{overall_acc:.1f}%", delta=f"{overall_acc - 85:+.1f}% vs target")
    c2.metric("Stockout SKUs", stockout, delta=f"{stockout}", delta_color="inverse")
    c3.metric("Low Stock", low, delta=f"{low}", delta_color="inverse")
    c4.metric("Overstock", overstock, delta=f"{overstock}", delta_color="inverse")
    c5.metric("Value at Risk", f"${var_total/1e6:.1f}M")
    c6.metric("Anomalies (7d)", int(anom[anom["IS_ANOMALY"] == True].shape[0]), delta="ML detected", delta_color="inverse")

    st.divider()
    cc1, cc2 = st.columns(2)
    with cc1:
        cat = fa.groupby("CATEGORY")["AVG_ACCURACY_PCT"].mean().reset_index().sort_values("AVG_ACCURACY_PCT")
        x_vals = [float(v) for v in cat["AVG_ACCURACY_PCT"].tolist()]
        y_vals = [str(v) for v in cat["CATEGORY"].tolist()]
        fig = go.Figure(data=[go.Bar(x=x_vals, y=y_vals, orientation="h", marker=dict(color=x_vals, colorscale="RdYlGn", cmin=40, cmax=100), hovertemplate="<b>%{y}</b><br>Accuracy: %{x:.1f}%<extra></extra>")])
        fig.add_vline(x=85, line_dash="dash", line_color="green", annotation_text="Target 85%")
        fig.update_layout(title="Avg Forecast Accuracy by Category", height=350, margin=dict(t=40, b=10), xaxis_title="Accuracy %", yaxis_title="")
        st.plotly_chart(fig, use_container_width=True)
    with cc2:
        rc = inv["RISK_LEVEL"].value_counts().reset_index()
        rc.columns = ["RISK_LEVEL", "COUNT"]
        labels = [str(v) for v in rc["RISK_LEVEL"].tolist()]
        values = [int(v) for v in rc["COUNT"].tolist()]
        colors = [RISK_COLORS.get(l, "#888") for l in labels]
        fig = go.Figure(data=[go.Pie(labels=labels, values=values, hole=0.4, marker=dict(colors=colors), sort=False, textinfo="label+percent")])
        fig.update_layout(title="Inventory Risk Distribution", height=350, margin=dict(t=40, b=10))
        st.plotly_chart(fig, use_container_width=True)


elif page == "Forecast Accuracy":
    st.title("Forecast Accuracy")
    st.caption("Weekly accuracy by product category vs 85% target")
    fa = load_forecast()
    if fa.empty:
        st.info("No data."); st.stop()

    fig = go.Figure()
    for cat_name in sorted(fa["CATEGORY"].dropna().unique()):
        sub = fa[fa["CATEGORY"] == cat_name].sort_values("WEEK_START")
        fig.add_trace(go.Scatter(x=[str(v) for v in sub["WEEK_START"].tolist()], y=[float(v) for v in sub["AVG_ACCURACY_PCT"].tolist()], mode="lines+markers", name=str(cat_name)))
    fig.add_hline(y=85, line_dash="dash", line_color="green", annotation_text="Target 85%")
    fig.update_layout(title="Forecast Accuracy by Category Over Time", height=420, margin=dict(t=40, b=10), yaxis=dict(range=[40, 100], title="Accuracy %"), xaxis_title="Week")
    st.plotly_chart(fig, use_container_width=True)

    cc1, cc2 = st.columns(2)
    with cc1:
        bias = fa.groupby("CATEGORY")["BIAS"].mean().reset_index().sort_values("BIAS")
        x_vals = [float(v) for v in bias["BIAS"].tolist()]
        y_vals = [str(v) for v in bias["CATEGORY"].tolist()]
        fig = go.Figure(data=[go.Bar(x=x_vals, y=y_vals, orientation="h", marker=dict(color=x_vals, colorscale="RdBu", cmid=0), hovertemplate="<b>%{y}</b><br>Bias: %{x:.2f}<extra></extra>")])
        fig.update_layout(title="Forecast Bias by Category", height=350, margin=dict(t=40, b=10), xaxis_title="Bias", yaxis_title="")
        st.plotly_chart(fig, use_container_width=True)
    with cc2:
        ou = fa.groupby("CATEGORY")[["UNITS_OVER_FORECAST", "UNITS_UNDER_FORECAST"]].sum().reset_index()
        cats = [str(v) for v in ou["CATEGORY"].tolist()]
        over_vals = [float(v) for v in ou["UNITS_OVER_FORECAST"].tolist()]
        under_vals = [float(v) for v in ou["UNITS_UNDER_FORECAST"].tolist()]
        fig = go.Figure(data=[
            go.Bar(name="Over Forecast", x=cats, y=over_vals, marker_color="#3498DB"),
            go.Bar(name="Under Forecast", x=cats, y=under_vals, marker_color="#E74C3C"),
        ])
        fig.update_layout(title="Over vs Under-Forecast Units", barmode="group", height=350, margin=dict(t=40, b=10), xaxis_title="Category", yaxis_title="Units")
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
        labels = [str(v) for v in rc["RISK_LEVEL"].tolist()]
        values = [int(v) for v in rc["COUNT"].tolist()]
        colors = [RISK_COLORS.get(l, "#888") for l in labels]
        fig = go.Figure(data=[go.Pie(labels=labels, values=values, hole=0.4, marker=dict(colors=colors), sort=False, textinfo="label+percent")])
        fig.update_layout(title="Inventory Risk Distribution", height=380, margin=dict(t=40, b=10))
        st.plotly_chart(fig, use_container_width=True)
    with cc2:
        cv = inv.groupby("CATEGORY")["VALUE_AT_RISK"].sum().reset_index().sort_values("VALUE_AT_RISK", ascending=True)
        cv["VAR_M"] = cv["VALUE_AT_RISK"] / 1e6
        x_vals = [float(v) for v in cv["VAR_M"].tolist()]
        y_vals = [str(v) for v in cv["CATEGORY"].tolist()]
        fig = go.Figure(data=[go.Bar(x=x_vals, y=y_vals, orientation="h", marker=dict(color=x_vals, colorscale="OrRd"), text=[f"{v:.1f}" for v in x_vals], textposition="auto", hovertemplate="<b>%{y}</b><br>$%{x:.1f}M<extra></extra>")])
        fig.update_layout(title="Value at Risk by Category ($M)", height=380, margin=dict(t=40, b=10), xaxis_title="$M", yaxis_title="")
        st.plotly_chart(fig, use_container_width=True)

    st.subheader("Critical Items (Stockout / Low)")
    crit = inv[inv["RISK_LEVEL"].isin(["STOCKOUT", "LOW"])].sort_values("DAYS_OF_SUPPLY").head(30)
    if not crit.empty:
        st.dataframe(crit[["PRODUCT_NAME", "CATEGORY", "WAREHOUSE_NAME", "AVG_ON_HAND", "DAYS_OF_SUPPLY", "RISK_LEVEL", "VALUE_AT_RISK"]].reset_index(drop=True), use_container_width=True)

    st.subheader("Overstock (Capital Tied Up)")
    over = inv[inv["RISK_LEVEL"] == "OVERSTOCK"].sort_values("VALUE_AT_RISK", ascending=False).head(15)
    if not over.empty:
        st.dataframe(over[["PRODUCT_NAME", "CATEGORY", "WAREHOUSE_NAME", "AVG_ON_HAND", "DAYS_OF_SUPPLY", "VALUE_AT_RISK"]].reset_index(drop=True), use_container_width=True)


elif page == "Demand Anomalies":
    st.title("Demand Anomalies")
    st.caption("ML.ANOMALY_DETECTION: demand spikes and crashes flagged per category")
    anom = load_anomalies()
    if anom.empty:
        st.info("No anomaly data."); st.stop()
    anom["SERIES"] = anom["SERIES"].astype(str).str.strip('"')

    anom_count = anom.groupby("SERIES")["IS_ANOMALY"].sum().reset_index()
    anom_count.columns = ["CATEGORY", "ANOMALY_COUNT"]
    anom_count = anom_count.sort_values("ANOMALY_COUNT", ascending=False)

    cols = st.columns(5)
    for i, row in anom_count.iterrows():
        idx = list(anom_count.index).index(i)
        if idx < 5:
            color = "inverse" if int(row["ANOMALY_COUNT"]) > 0 else "normal"
            cols[idx].metric(str(row["CATEGORY"]), f"{int(row['ANOMALY_COUNT'])} anomalies", delta=f"of 8 days", delta_color=color)

    st.divider()
    cat_list = sorted(anom["SERIES"].str.strip('"').unique())
    default_idx = cat_list.index("Electronics") if "Electronics" in cat_list else 0
    selected_cat = st.selectbox("Category", cat_list, index=default_idx)
    cat_data = anom[anom["SERIES"] == selected_cat].sort_values("TS")

    fig = go.Figure()
    dates = [str(v)[:10] for v in cat_data["TS"].tolist()]
    fig.add_trace(go.Scatter(x=dates, y=[float(v) for v in cat_data["UPPER_BOUND"].tolist()], mode="lines", name="Upper Bound", line=dict(dash="dot", color="#95a5a6"), showlegend=True))
    fig.add_trace(go.Scatter(x=dates, y=[float(v) for v in cat_data["LOWER_BOUND"].tolist()], mode="lines", name="Lower Bound", line=dict(dash="dot", color="#95a5a6"), fill="tonexty", fillcolor="rgba(149,165,166,0.1)", showlegend=True))
    fig.add_trace(go.Scatter(x=dates, y=[float(v) for v in cat_data["FORECAST"].tolist()], mode="lines", name="Forecast", line=dict(color="#3498DB", width=2)))
    anomaly_colors = ["#E74C3C" if v else "#2ECC71" for v in cat_data["IS_ANOMALY"].tolist()]
    fig.add_trace(go.Scatter(x=dates, y=[float(v) for v in cat_data["Y"].tolist()], mode="markers+lines", name="Actual", marker=dict(color=anomaly_colors, size=12, line=dict(width=2, color="white")), line=dict(color="#2C3E50", width=1)))
    fig.update_layout(title=f"Anomaly Detection: {selected_cat}", height=450, margin=dict(t=40, b=10), yaxis_title="Daily Demand (units)", xaxis_title="Date")
    st.plotly_chart(fig, use_container_width=True)

    st.subheader("Anomaly Detail")
    display_cols = ["SERIES", "TS", "Y", "FORECAST", "LOWER_BOUND", "UPPER_BOUND", "IS_ANOMALY", "PERCENTILE"]
    st.dataframe(cat_data[[c for c in display_cols if c in cat_data.columns]].reset_index(drop=True), use_container_width=True)

    st.info("Red dots = anomalous demand (outside 95% prediction interval). Electronics shows 5/8 days anomalous — the forecast model is systematically wrong for this category.")


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
    palette = ["#3498DB", "#E74C3C", "#2ECC71", "#F39C12", "#9B59B6", "#1ABC9C", "#E67E22", "#34495E"]
    with cc1:
        top = sig.nlargest(15, "GROWTH_RATE_PCT").sort_values("GROWTH_RATE_PCT")
        cats = [str(v) for v in top["CATEGORY"].tolist()]
        unique_cats = list(dict.fromkeys(cats))
        cmap = {c: palette[i % len(palette)] for i, c in enumerate(unique_cats)}
        bar_colors = [cmap[c] for c in cats]
        x_vals = [float(v) for v in top["GROWTH_RATE_PCT"].tolist()]
        y_vals = [str(v) for v in top["PRODUCT_NAME"].tolist()]
        fig = go.Figure(data=[go.Bar(x=x_vals, y=y_vals, orientation="h", marker_color=bar_colors, customdata=cats, hovertemplate="<b>%{y}</b><br>Growth: %{x:.1f}%<br>Category: %{customdata}<extra></extra>")])
        fig.update_layout(title="Top 15 Growing SKUs (% 7d vs 30d)", height=500, margin=dict(t=40, b=10, l=180), xaxis_title="Growth %", yaxis_title="")
        st.plotly_chart(fig, use_container_width=True)
    with cc2:
        vel = (sig.nsmallest(15, "VELOCITY_RANK") if "VELOCITY_RANK" in sig.columns else sig.head(15)).sort_values("AVG_DAILY_7D")
        cats = [str(v) for v in vel["CATEGORY"].tolist()]
        unique_cats = list(dict.fromkeys(cats))
        cmap = {c: palette[i % len(palette)] for i, c in enumerate(unique_cats)}
        bar_colors = [cmap[c] for c in cats]
        x_vals = [float(v) for v in vel["AVG_DAILY_7D"].tolist()]
        y_vals = [str(v) for v in vel["PRODUCT_NAME"].tolist()]
        fig = go.Figure(data=[go.Bar(x=x_vals, y=y_vals, orientation="h", marker_color=bar_colors, customdata=cats, hovertemplate="<b>%{y}</b><br>7d daily: %{x:.1f}<br>Category: %{customdata}<extra></extra>")])
        fig.update_layout(title="Top 15 by 7d Daily Velocity", height=500, margin=dict(t=40, b=10, l=180), xaxis_title="Avg Daily (7d)", yaxis_title="")
        st.plotly_chart(fig, use_container_width=True)


elif page == "Planning Intelligence":
    st.title("Planning Intelligence")
    st.caption("The forecast says Electronics is broken — what do the planning documents say? Claude Sonnet classifies 80 docs in a single SQL statement.")

    docs = coerce_numeric(session.sql("SELECT * FROM MANUFACTURING_DEMAND.AI.DOC_RISK_CLASSIFICATION ORDER BY RISK_LEVEL, DOC_ID").to_pandas())
    if docs.empty:
        st.warning("No classified docs."); st.stop()

    risk_order = ["CRITICAL", "HIGH_RISK", "MEDIUM_RISK", "LOW_RISK"]
    risk_colors_map = {"CRITICAL": "#E74C3C", "HIGH_RISK": "#F39C12", "MEDIUM_RISK": "#3498DB", "LOW_RISK": "#2ECC71"}
    risk_icons = {"CRITICAL": "🔴", "HIGH_RISK": "🟠", "MEDIUM_RISK": "🔵", "LOW_RISK": "🟢"}
    risk_counts = docs["RISK_LEVEL"].value_counts().to_dict()
    total_docs = len(docs)
    crit_count = risk_counts.get("CRITICAL", 0)
    high_count = risk_counts.get("HIGH_RISK", 0)

    cols = st.columns(4)
    for i, rl in enumerate(risk_order):
        cnt = risk_counts.get(rl, 0)
        pct = f"{cnt / total_docs * 100:.0f}% of {total_docs}"
        cols[i].metric(f"{risk_icons[rl]} {rl.replace('_', ' ')}", cnt, delta=pct, delta_color="off")

    if crit_count + high_count > 0:
        st.error(f"**{crit_count + high_count} documents** flagged CRITICAL or HIGH RISK — all {crit_count} CRITICAL docs are Demand Strategy, the same category driving the Electronics forecast failure.")

    def color_risk(val):
        c = risk_colors_map.get(val, "")
        return f"background-color: {c}; color: white; border-radius: 4px; padding: 2px 6px" if c else ""

    fc1, fc2 = st.columns(2)
    selected_risk = fc1.selectbox("Risk level", ["All"] + risk_order, index=1)
    categories = sorted(docs["DOC_CATEGORY"].unique().tolist())
    selected_cat = fc2.selectbox("Category", ["All"] + categories)
    filtered = docs.copy()
    if selected_risk != "All":
        filtered = filtered[filtered["RISK_LEVEL"] == selected_risk]
    if selected_cat != "All":
        filtered = filtered[filtered["DOC_CATEGORY"] == selected_cat]

    display_df = filtered[["DOC_ID", "TITLE", "DOC_CATEGORY", "RISK_LEVEL", "SUMMARY"]].reset_index(drop=True)
    st.dataframe(display_df.style.map(color_risk, subset=["RISK_LEVEL"]), use_container_width=True, height=480)


elif page == "Ask Demand":
    st.title("Ask the Data")
    st.caption("Natural language questions powered by Cortex Analyst + Semantic View")
    samples = [
        "Which category has lowest forecast accuracy?",
        "How many SKUs are at stockout risk?",
        "What is the total value at risk?",
        "Which warehouse has the most overstock?",
        "What is the average days of supply for Electronics?"
    ]
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
                                st.dataframe(session.sql(sql).to_pandas().reset_index(drop=True), use_container_width=True)
                            except Exception:
                                pass
                else:
                    st.error(parsed)
            except Exception as e:
                st.error(f"Error: {e}")
