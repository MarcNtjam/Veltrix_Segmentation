# Veltrix Customer Segmentation dashboard: user guide

**Owner:** Veltrix DA team (Marc Ntjam). **Data:** CRM, web and payments data to 30 Sep 2026. **Refresh:** daily at 06:00 UK time through the on-premises data gateway; segments re-scored monthly by the DS team. **Model version:** shown in the header (for example "model seg-v1.0").

## What each page answers

| Page | Answers | Use it to decide |
|---|---|---|
| **Overview** | How is the business doing, and which segments matter most? 6 KPI cards against the year before, monthly leads, each segment's share of customers vs share of deal value, and the Segments at a glance table with priority tiers. | Where to focus this month; which segment needs attention |
| **Segment deep dive** | Who is each segment, where do they look, how do they arrive and browse, and how should we serve them? Pick a segment with the tiles at the top. | Messages, channels and stock for one segment; the recommended action panel says who handles it and how |
| **Pipeline and agents** | Does reply speed win deals, and is the pipeline routed well? Leads, won, open pipeline, answered within 1 hour; conversion by reply time; seniority; pipeline by stage; open leads by tier and desk; the campaign-test KPI. | Weekly chase list (Viewing/Offer), moving P1 leads to senior agents, reading the test |
| **Payments and lettings** | Where is late payment, and how much value do lettings bring? Payments due, late %, overdue now (£), late rent; late share by month and by segment; deal value by transaction type. | Who collections calls first; when to escalate |

## Filters

- **Period:** 12-month periods ending 30 September. The default is "Last 12 months (Oct 2025 – Sep 2026)". It applies to every page except the browsing visuals, which are all-time summaries.
- **Intent:** Buy or Rent.
- **Region:** the customer's UK region of residence, or "Overseas".
- **Segment tiles** (Segment deep dive only): select one segment. Selecting several shows combined numbers, and the action panel asks you to pick one.
- **Bookmark "Test segment"** (Overview): one click filters the report to the campaign-test segment.

## Definitions (also in the footnote on every page)

| KPI | Definition |
|---|---|
| Customers | People or companies, counted once after merging duplicate records (102,000 records → 100,573 customers) |
| Leads | Enquiries created in the period; one customer can have several |
| Conversion % | Won ÷ (Won + Lost) leads, by the date the lead closed; open leads excluded |
| Deal value | Agreed price for sales; monthly rent × tenancy months for lettings; by contract date. Not fee income |
| Median first reply | Median time from a lead's first inbound contact to our reply |
| Answered within 1 hour | Share of leads with a first reply under 60 minutes |
| Open pipeline | Leads at New, Contacted, Qualified, Viewing or Offer at the data cut-off |
| Late payments % | (Paid late + overdue) ÷ payments due, by due date; scheduled payments excluded |
| Overdue now | Amount still unpaid after its due date at the cut-off |
| Priority tier | P1/P2/P3 from the value of an average closed lead in the segment (P1: index 115+, P2: 60–114, P3: under 60) |
| Index vs average | Segment value ÷ all customers × 100 (100 = average) |

## Things to know

- **Numbers are reconciled to SQL.** The hidden Data check page compares every card with the SQL check tables (`clean.final_check`, `clean.segment_check`, `clean.crm_export_counts`). If a number looks wrong, ask the DA team to compare it there first.
- **The latest month's late payments look high** because they haven't been chased yet. Judge a month after about 60 days.
- **Browsing in the final months of data (Jul–Sep 2026) is inflated** by how the data was collected; it isn't a demand surge.
- **Correlation, not proof:** fast replies convert better partly because easier leads get answered first. The campaign test measures the real effect.

## Behind the report

- **Database:** PostgreSQL `veltrix`. Schemas: `raw` (as delivered, never edited), `clean` (cleaned tables, segments, checks), `feat` (customer features and outcomes), `dq` (data quality log), `eda` (analysis views).
- **Monthly routine (DA):**
    1. Refresh the data.
    2. Re-run Week 1 Day 4, then Week 2 Days 6–7 and Week 3 Days 11–12.
    3. Load the DS re-scoring, then switch the version with `UPDATE clean.segment_in_use SET model_version = '…'`.
    4. Run the Day 15 monitoring step and act on any ALERT.
    5. Refresh Power BI.
- **Monitoring:** `clean.monitoring_latest` holds the data quality checks plus an alert when any segment's size moves more than 20% from go-live.
- **Contact:** DA team via the project channel. Report bugs with the page, the visual and a screenshot.
