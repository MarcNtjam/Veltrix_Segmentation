"""Veltrix customer segmentation (seg-v1.0) as a Streamlit app.

Run locally (Anaconda Prompt, in the app folder):   streamlit run streamlit_app.py
Needs only the files in app/model/ (written by notebooks/08_export_model.ipynb): no database connection.
"""
from pathlib import Path

import altair as alt
import pandas as pd
import streamlit as st

from segmenter import Segmenter

st.set_page_config(page_title="Veltrix segmentation", page_icon="🏠", layout="wide")
HERE = Path(__file__).parent
NAVY, ORANGE, GREY = "#1F4E79", "#E8702A", "#9BA7B4"
TIER_COLOUR = {"P1": ORANGE, "P2": NAVY, "P3": "#7F8C99"}


@st.cache_resource
def load():
    return Segmenter(HERE / "model")


@st.cache_data
def lookup_table():
    return pd.read_csv(HERE / "model" / "customer_lookup.csv")


@st.cache_data
def example_batch():
    return pd.read_csv(HERE / "model" / "example_batch.csv")


seg = load()
P = seg.profiles
META = seg.meta
LABELS = {
    "budget_gbp": "Purchase budget (£)", "rent_budget_pcm_gbp": "Rent budget (£ per month)", "sessions_total": "Web sessions (logged in)",
    "night_session_share": "Sessions between 00:00 and 06:00 UK", "virtual_tour_share": "Virtual tours, share of property events",
    "enquiries_total": "Enquiries (leads) raised", "days_since_last_activity": "Days since last activity", "mobile_share": "Sessions on mobile",
    "new_build_share": "New-build listings, share of views", "london_share": "London listings, share of views",
    "preferred_region": "Region viewed most", "preferred_property_type": "Property type viewed most", "lead_source_primary": "Main lead source",
    "finance_type": "Finance type", "customer_type": "Customer type", "is_overseas": "Lives overseas", "buyer_position": "Buyer position",
    "age_band": "Age band",
}
SHARES = ["night_session_share", "virtual_tour_share", "mobile_share", "new_build_share", "london_share"]


def badge(tier):
    return (f"<span style='background:{TIER_COLOUR.get(tier, NAVY)};color:white;padding:2px 10px;border-radius:10px;"
            f"font-weight:600;font-size:0.85rem'>{tier}</span>")


def persona_card(row, title_prefix=""):
    st.markdown(f"### {title_prefix}{row.segment_name} &nbsp; {badge(row.priority_tier)}", unsafe_allow_html=True)
    c = st.columns(5)
    c[0].metric("Customers", f"{int(row.customers):,}", f"{row.pct_customers:.0f}% of all", delta_color="off")
    c[1].metric("Share of deal value", f"{row.pct_deal_value:.0f}%")
    c[2].metric("Conversion", f"{row.conversion_pct:.1f}%")
    c[3].metric("Late payments", f"{row.late_payment_pct:.1f}%")
    price = f"£{row.median_budget_gbp:,.0f}" if pd.notna(row.median_budget_gbp) else f"£{row.median_rent_pcm_gbp:,.0f} pcm"
    c[4].metric("Median budget", price)
    left, right = st.columns(2)
    left.markdown(
        f"**Typical profile**  \n"
        f"- Buyer position: {row.top_buyer_position}; finance: {row.top_finance}  \n"
        f"- Looks most at: {row.top_property_type.lower()}s in {row.top_region}  \n"
        f"- Main channel: {row.top_channel}  \n"
        f"- {row.pct_overseas:.0f}% live overseas · {row.mobile_share:.0f}% of sessions on mobile · "
        f"{row.night_share:.0f}% at night · {row.pct_no_enquiry:.0f}% never enquired")
    right.markdown(
        f"**What to do**  \n"
        f"- Route to: **{row.routed_desk}** ({row.agent_level})  \n"
        f"- Reply target: {row.reply_target}  \n"
        f"- First contact by: {row.best_first_contact}")


# ------------------------------------------------------------------ sidebar
with st.sidebar:
    st.markdown("## 🏠 Veltrix")
    st.markdown("Customer and buyer segmentation")
    st.caption(f"Model **{META['model_version']}** · {META['algorithm']} · k = {META['k']}  \n"
               f"Trained on data to {META['data_to']}  \n{META['trained_on']}")
    st.divider()
    st.caption("Tiers: **P1** senior agent, reply < 1 h · **P2** reply < 4 h · **P3** automated nurture / same day")

tab_over, tab_score, tab_batch, tab_look, tab_model = st.tabs(
    ["Segments", "Score a customer", "Batch scoring", "Look up a customer", "Model"])

# ------------------------------------------------------------------ 1. segments overview
with tab_over:
    p1 = P[P.priority_tier == "P1"]
    top = P.sort_values("pct_deal_value").iloc[-1]
    st.markdown(f"## {len(P)} customer segments")
    st.markdown(f"**{top.segment_name}** are {top.pct_customers:.0f}% of customers but bring **{top.pct_deal_value:.0f}%** of deal value. "
                f"The {len(p1)} priority-1 segments together bring **{p1.pct_deal_value.sum():.0f}%** of deal value.")
    k = st.columns(4)
    k[0].metric("Customers segmented", f"{int(P.customers.sum()):,}")
    k[1].metric("Segments", len(P))
    k[2].metric("Deal value in P1 segments", f"{p1.pct_deal_value.sum():.0f}%")
    k[3].metric("Silhouette / stability", f"{META['metrics']['silhouette_gower']:.3f} / {META['metrics']['bootstrap_ari_mean']:.2f}")

    long = P.melt(id_vars=["segment_name"], value_vars=["pct_customers", "pct_deal_value"], var_name="measure", value_name="pct")
    long["measure"] = long.measure.map({"pct_customers": "% of customers", "pct_deal_value": "% of deal value"})
    order = P.sort_values("pct_deal_value", ascending=False).segment_name.tolist()
    bars = alt.Chart(long).mark_bar(cornerRadiusEnd=3, height=14).encode(
        y=alt.Y("segment_name:N", sort=order, title=None, axis=alt.Axis(labelOverlap=False, labelLimit=220)),
        yOffset=alt.YOffset("measure:N", sort=["% of customers", "% of deal value"]),
        x=alt.X("pct:Q", title="%"),
        color=alt.Color("measure:N", scale=alt.Scale(range=[GREY, NAVY]), legend=alt.Legend(orient="bottom", title=None)),
        tooltip=["segment_name", "measure", alt.Tooltip("pct:Q", format=".1f")])
    st.altair_chart((bars + bars.mark_text(align="left", dx=3, fontSize=11).encode(text=alt.Text("pct:Q", format=".0f"), color=alt.value("#333")))
                    .properties(height=380, title="Share of customers vs share of deal value"), width="stretch")

    show = P[["segment_name", "priority_tier", "customers", "pct_customers", "pct_deal_value", "conversion_pct", "late_payment_pct", "routed_desk"]]
    st.dataframe(show.rename(columns={"segment_name": "Segment", "priority_tier": "Tier", "customers": "Customers", "pct_customers": "% customers",
                                      "pct_deal_value": "% deal value", "conversion_pct": "Conversion %", "late_payment_pct": "Late %",
                                      "routed_desk": "Routed to"}),
                 hide_index=True, width="stretch",
                 column_config={c: st.column_config.NumberColumn(format="%.1f") for c in ["% customers", "% deal value", "Conversion %", "Late %"]})
    st.markdown("### Persona cards")
    pick = st.selectbox("Segment", P.segment_name.tolist(), key="persona_pick")
    persona_card(P[P.segment_name == pick].iloc[0])

# ------------------------------------------------------------------ 2. score one customer
with tab_score:
    st.markdown("## Score a new customer")
    st.caption("Enter what we know about the customer; the model assigns the nearest segment prototype. "
               "Or start from a real customer in the example file and change a few answers.")
    ex = example_batch()
    start = st.selectbox("Start from", ["Typical values"] + ex.customer_id.tolist(), key="start_from")
    base = ex[ex.customer_id == start].iloc[0] if start != "Typical values" else None

    def default(c):
        if base is not None:
            return base[c]
        if c in seg.cat:
            return {"preferred_region": "London", "preferred_property_type": "Flat", "lead_source_primary": "Rightmove", "finance_type": "Mortgage",
                    "customer_type": "Individual", "is_overseas": "False", "buyer_position": "First-time buyer", "age_band": "25-34"}[c]
        if c in META["budget_ranges"]:
            return META["budget_ranges"][c][1]
        return META["numeric_ranges"][c][1]

    with st.form("score"):
        a, b, c = st.columns(3)
        vals = {}
        b0, r0 = default("budget_gbp"), default("rent_budget_pcm_gbp")
        intent = a.radio("Intent", ["Buy", "Rent"], horizontal=True,
                         index=0 if base is None or pd.notna(b0) and (pd.isna(r0) or r0 == 0) else 1)
        vals["budget_gbp"] = a.number_input(LABELS["budget_gbp"], min_value=0, max_value=20_000_000, step=5_000,
                                            value=int(b0) if pd.notna(b0) else int(META["budget_ranges"]["budget_gbp"][1]))
        vals["rent_budget_pcm_gbp"] = a.number_input(LABELS["rent_budget_pcm_gbp"], min_value=0, max_value=50_000, step=50,
                                                     value=int(r0) if pd.notna(r0) else int(META["budget_ranges"]["rent_budget_pcm_gbp"][1]))
        for col, f in zip([a, a, b, b, b, c, c, c], ["sessions_total", "enquiries_total", "days_since_last_activity", "night_session_share",
                                                     "virtual_tour_share", "mobile_share", "new_build_share", "london_share"]):
            if f in SHARES:
                vals[f] = col.slider(LABELS[f] + " (%)", 0, 100, int(round(100 * float(default(f))))) / 100
            else:
                vals[f] = col.number_input(LABELS[f], min_value=0, max_value=5000, value=int(round(float(default(f)))))
        st.markdown("**Profile**")
        cc = st.columns(4)
        for i, f in enumerate(seg.cat):
            opts = META["categories"][f]
            dv = str(default(f))
            vals[f] = cc[i % 4].selectbox(LABELS[f], opts, index=opts.index(dv) if dv in opts else 0)
        go = st.form_submit_button("Find the segment", type="primary")

    if go or "last_score" in st.session_state:
        if go:
            if intent == "Buy":
                vals["rent_budget_pcm_gbp"] = 0
            else:
                vals["budget_gbp"] = 0
            st.session_state["last_score"] = vals
        row = pd.DataFrame([st.session_state["last_score"]])
        res = seg.score(row).iloc[0]
        prof = P[P.segment_id == res.segment_id].iloc[0]
        st.divider()
        persona_card(prof, "Segment: ")
        st.info(f"**Recommended action:** {res.recommended_action}")
        dist = seg.segment_distances(row)
        dist["closest"] = dist.segment_name == res.segment_name
        st.markdown(f"**How close is the fit?** {'Clear: well inside this segment.' if res.fit == 'clear' else 'Borderline: almost as close to the next segment; check the answers.'}")
        st.altair_chart(alt.Chart(dist).mark_bar(cornerRadiusEnd=3).encode(
            y=alt.Y("segment_name:N", sort="x", title=None), x=alt.X("distance:Q", title="Distance to the segment prototype (lower = closer)"),
            color=alt.condition("datum.closest", alt.value(ORANGE), alt.value(GREY)), tooltip=["segment_name", "distance"]).properties(height=220),
            width="stretch")

# ------------------------------------------------------------------ 3. batch scoring
with tab_batch:
    st.markdown("## Batch scoring")
    st.markdown("Upload a CSV with one row per customer and these columns (a `customer_id` column is kept if present):")
    st.code(", ".join(seg.input_columns), language=None)
    st.caption("Budgets in £ (purchase) and £ per month (rent); leave the one that does not apply blank or 0. Shares between 0 and 1. "
               "Category values must match the model's (see the Model tab).")
    st.download_button("Download an example file (200 customers)", example_batch().to_csv(index=False), "example_batch.csv", "text/csv")
    up = st.file_uploader("CSV file", type="csv")
    if up is not None:
        df = pd.read_csv(up)
        missing, unseen = seg.check(df)
        if missing:
            st.error("Missing columns: " + ", ".join(missing))
        else:
            if unseen:
                st.warning("Values the model has never seen (they count as a mismatch on that field): " +
                           "; ".join(f"{k}: {', '.join(v[:5])}" for k, v in unseen.items()))
            out = seg.score(df)
            st.success(f"Scored {len(out):,} customers · {(out.fit == 'borderline').mean():.0%} borderline")
            cnt = out.groupby(["segment_name", "priority_tier"]).size().rename("customers").reset_index()
            st.altair_chart(alt.Chart(cnt).mark_bar(cornerRadiusEnd=3).encode(
                y=alt.Y("segment_name:N", sort="-x", title=None, axis=alt.Axis(labelOverlap=False, labelLimit=220)), x=alt.X("customers:Q", title="Customers"),
                color=alt.Color("priority_tier:N", scale=alt.Scale(domain=list(TIER_COLOUR), range=list(TIER_COLOUR.values())),
                                legend=alt.Legend(title="Tier", orient="bottom")), tooltip=["segment_name", "priority_tier", "customers"]).properties(height=60 + 34 * cnt.segment_name.nunique()),
                width="stretch")
            keep = (["customer_id"] if "customer_id" in out else []) + ["segment_id", "segment_name", "priority_tier", "routed_desk",
                                                                         "agent_level", "reply_target", "fit"]
            st.dataframe(out[keep], hide_index=True, width="stretch")
            st.download_button("Download the scored file", out.to_csv(index=False), "scored_customers.csv", "text/csv", type="primary")

# ------------------------------------------------------------------ 4. look up an existing customer
with tab_look:
    st.markdown("## Look up an existing customer")
    lk = lookup_table()
    cid = st.text_input("Customer ID", placeholder="e.g. " + lk.customer_id.iloc[0]).strip()
    if cid:
        hit = lk[lk.customer_id.str.upper() == cid.upper()]
        if hit.empty:
            st.warning("No customer with that ID in the segmented file (merged duplicates use the surviving ID).")
        else:
            persona_card(P[P.segment_id == hit.iloc[0].segment_id].iloc[0], f"{hit.iloc[0].customer_id}: ")

# ------------------------------------------------------------------ 5. model card
with tab_model:
    st.markdown("## How the model was chosen")
    st.markdown(
        f"- **Chosen:** k-prototypes with **k = {META['k']}** (numeric and categorical features together; categorical weight gamma = {META['gamma']}).  \n"
        f"- **Baseline:** k-means on the numeric features only. **Cross-check:** hierarchical clustering on Gower distance.  \n"
        f"- **Why k = {META['k']}:** best silhouette ({META['metrics']['silhouette_gower']:.3f}) among readable solutions (5-9 segments) and the most stable: "
        f"20 bootstrap refits agree with an adjusted Rand index of {META['metrics']['bootstrap_ari_mean']:.2f}. Two or three segments separate more cleanly "
        f"but are too coarse to route leads or target campaigns.  \n"
        f"- **Held-out check:** the segments differ on conversion, deal value and late payment, which the model never saw (all p < 0.001).")
    comp = seg.comparison.copy()
    ch = alt.Chart(comp).mark_line(point=True).encode(
        x=alt.X("k:O", title="k (number of segments)"), y=alt.Y("silhouette:Q", title="Silhouette (higher = better separated)"),
        color=alt.Color("model:N", scale=alt.Scale(range=[GREY, NAVY]), legend=alt.Legend(orient="bottom", title=None, labelLimit=400)),
        tooltip=["model", "k", "silhouette", "stability_mean_ari"])
    chosen = alt.Chart(comp[comp.chosen]).mark_point(size=250, color=ORANGE, filled=False, strokeWidth=3).encode(x="k:O", y="silhouette:Q")
    st.altair_chart((ch + chosen).properties(height=300), width="stretch")
    st.caption("The two silhouettes are not directly comparable: k-means is measured on numeric features only, k-prototypes on Gower distance over all features.")
    st.dataframe(comp.round(3).astype(object).where(comp.notna(), "-").astype(str).rename(columns={"smallest_segment_pct": "smallest segment %", "ari_kprototypes_vs_hierarchical": "ARI vs hierarchical",
                                      "stability_mean_ari": "bootstrap ARI"}), hide_index=True, width="stretch")
    with st.expander("Inputs and allowed values"):
        st.markdown("**Numeric** (money log-transformed, all scaled with the training mean and standard deviation): " + ", ".join(seg.num))
        for c, v in META["categories"].items():
            st.markdown(f"**{c}**: " + ", ".join(v))
