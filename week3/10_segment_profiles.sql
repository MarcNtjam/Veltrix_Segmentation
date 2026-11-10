-- =====================================================================================
-- DAY 11 · Segment profiling: index-versus-average, channels, profile facts
-- Needs: Week 2 (Days 6-10). Works on whichever segmentation is in use
-- (clean.segment_in_use): placeholder-A until you switch to seg-v1.0, then the DS segments.
-- Run in pgAdmin on veltrix, ONE STEP AT A TIME.
-- =====================================================================================

-- =====================================================================================
-- STEP 1 · Helper columns the segment cards need
-- =====================================================================================
-- 1a. Price level per customer: stated budget, or the median price / rent they viewed
ALTER TABLE clean.clean_customers ADD COLUMN IF NOT EXISTS price_level_gbp DOUBLE PRECISION;
ALTER TABLE clean.clean_customers ADD COLUMN IF NOT EXISTS rent_level_pcm DOUBLE PRECISION;
UPDATE clean.clean_customers c
SET price_level_gbp = CASE WHEN c.primary_intent = 'Buy'  THEN coalesce(c.stated_budget_gbp, f.median_viewed_price_gbp) END,
    rent_level_pcm  = CASE WHEN c.primary_intent = 'Rent' THEN coalesce(c.stated_rent_budget_pcm_gbp, f.median_viewed_rent_pcm_gbp) END
FROM feat.customer_features f
WHERE f.customer_id = c.customer_id;

-- 1b. Days from lead created to decision (closed leads only)
ALTER TABLE clean.clean_leads ADD COLUMN IF NOT EXISTS days_to_decision INT;
UPDATE clean.clean_leads SET days_to_decision = CASE WHEN is_closed = 1 THEN closed_date - created_day END;

-- =====================================================================================
-- STEP 2 · A one-row-per-segment table for Power BI (the segment selector reads it)
-- =====================================================================================
CREATE OR REPLACE VIEW clean.segment_dim AS
SELECT segment_name, min(segment_order) AS segment_order, min(segment_id) AS segment_id, count(*) AS customers
FROM clean.dashboard_segments GROUP BY segment_name;

SELECT * FROM clean.segment_dim ORDER BY segment_order;

-- =====================================================================================
-- STEP 3 · Index versus average: every segment on 12 measures, all customers = 100
-- Read it as: 150 = 50% above the average customer, 50 = half the average.
-- =====================================================================================
CREATE OR REPLACE VIEW clean.segment_index AS
WITH seg AS (SELECT customer_id, segment_name FROM clean.dashboard_segments),
cust AS (   -- customer-level facts
    SELECT s.segment_name, c.customer_id, c.is_overseas, c.price_level_gbp, c.rent_level_pcm,
           f.n_sessions, f.pct_night_sessions, f.mobile_sessions, f.n_property_events, f.n_virtual_tours,
           f.n_new_build_events, f.n_leads, o.deal_value_gbp, o.payments_due, o.payments_late_or_overdue
    FROM seg s JOIN clean.clean_customers c USING (customer_id)
    JOIN feat.customer_features f USING (customer_id) JOIN feat.customer_outcomes o USING (customer_id)
),
lead AS (
    SELECT s.segment_name, l.is_closed, l.converted, l.days_to_decision, l.first_response_min
    FROM seg s JOIN clean.clean_leads l USING (customer_id)
),
by_seg AS (
    SELECT c.segment_name,
           avg(c.deal_value_gbp)                                                   AS deal_value_per_customer,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY c.price_level_gbp)          AS median_price_level,
           sum(c.payments_late_or_overdue)::numeric / nullif(sum(c.payments_due), 0) AS late_rate,
           avg(CASE WHEN c.is_overseas THEN 1.0 ELSE 0 END)                        AS overseas_share,
           sum(c.n_sessions * c.pct_night_sessions / 100.0) / nullif(sum(c.n_sessions), 0) AS night_share,
           sum(c.mobile_sessions)::numeric / nullif(sum(c.n_sessions), 0)          AS mobile_share,
           sum(c.n_virtual_tours)::numeric / nullif(sum(c.n_property_events), 0)   AS virtual_tour_share,
           sum(c.n_new_build_events)::numeric / nullif(sum(c.n_property_events), 0) AS new_build_share,
           avg(c.n_leads)                                                          AS leads_per_customer
    FROM cust c GROUP BY 1
),
lead_seg AS (
    SELECT segment_name,
           avg(CASE WHEN converted THEN 1.0 ELSE 0 END) FILTER (WHERE is_closed = 1) AS conversion,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_decision)           AS median_days_to_decide,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_min) / 60.0  AS median_first_reply_h
    FROM lead GROUP BY 1
),
overall AS (
    SELECT avg(c.deal_value_gbp) AS deal_value_per_customer,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY c.price_level_gbp) AS median_price_level,
           sum(c.payments_late_or_overdue)::numeric / nullif(sum(c.payments_due), 0) AS late_rate,
           avg(CASE WHEN c.is_overseas THEN 1.0 ELSE 0 END) AS overseas_share,
           sum(c.n_sessions * c.pct_night_sessions / 100.0) / nullif(sum(c.n_sessions), 0) AS night_share,
           sum(c.mobile_sessions)::numeric / nullif(sum(c.n_sessions), 0) AS mobile_share,
           sum(c.n_virtual_tours)::numeric / nullif(sum(c.n_property_events), 0) AS virtual_tour_share,
           sum(c.n_new_build_events)::numeric / nullif(sum(c.n_property_events), 0) AS new_build_share,
           avg(c.n_leads) AS leads_per_customer,
           (SELECT avg(CASE WHEN converted THEN 1.0 ELSE 0 END) FILTER (WHERE is_closed = 1) FROM lead) AS conversion,
           (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_decision) FROM lead) AS median_days_to_decide,
           (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_min) / 60.0 FROM lead) AS median_first_reply_h
    FROM cust c
),
long AS (
    SELECT s.segment_name, m.metric_order, m.metric, m.unit, m.seg_value, m.all_value
    FROM by_seg s JOIN lead_seg l USING (segment_name) CROSS JOIN overall o
    CROSS JOIN LATERAL (VALUES
        (1,  'Conversion',               '%',   100 * l.conversion,             100 * o.conversion),
        (2,  'Deal value per customer',  '£',   s.deal_value_per_customer,      o.deal_value_per_customer),
        (3,  'Price level (buyers)',     '£',   s.median_price_level,           o.median_price_level),
        (4,  'Days to decide',           'days', l.median_days_to_decide,       o.median_days_to_decide),
        (5,  'Late payments',            '%',   100 * s.late_rate,              100 * o.late_rate),
        (6,  'First reply time',         'h',   l.median_first_reply_h,         o.median_first_reply_h),
        (7,  'Leads per customer',       '#',   s.leads_per_customer,           o.leads_per_customer),
        (8,  'Living overseas',          '%',   100 * s.overseas_share,         100 * o.overseas_share),
        (9,  'Night browsing (00-06 UK)', '%',  100 * s.night_share,            100 * o.night_share),
        (10, 'Mobile sessions',          '%',   100 * s.mobile_share,           100 * o.mobile_share),
        (11, 'Virtual-tour share',       '%',   100 * s.virtual_tour_share,     100 * o.virtual_tour_share),
        (12, 'New-build view share',     '%',   100 * s.new_build_share,        100 * o.new_build_share)
    ) AS m(metric_order, metric, unit, seg_value, all_value)
)
SELECT segment_name, metric_order, metric, unit,
       round(seg_value::numeric, 2) AS segment_value,
       round(all_value::numeric, 2) AS all_customers_value,
       round((100 * seg_value / nullif(all_value, 0))::numeric, 0) AS index_vs_average
FROM long
WHERE seg_value IS NOT NULL;     -- e.g. no buyer price level for a renter-only segment

-- Every segment's index on every measure (the bar charts around 100)
SELECT segment_name, metric, segment_value, all_customers_value, index_vs_average
FROM clean.segment_index ORDER BY segment_name, metric_order;

-- =====================================================================================
-- STEP 4 · How they arrive: share of each segment's leads by channel (top 5 = rank <= 5)
-- =====================================================================================
CREATE OR REPLACE VIEW clean.segment_channels AS
SELECT s.segment_name, l.lead_source AS channel, l.channel_group,
       count(*) AS leads,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY s.segment_name), 1) AS pct_of_segment_leads,
       round(100.0 * avg(CASE WHEN l.converted THEN 1 ELSE 0 END) FILTER (WHERE l.is_closed = 1), 1) AS conversion_pct,
       rank() OVER (PARTITION BY s.segment_name ORDER BY count(*) DESC) AS channel_rank
FROM clean.dashboard_segments s JOIN clean.clean_leads l USING (customer_id)
GROUP BY s.segment_name, l.lead_source, l.channel_group;

SELECT * FROM clean.segment_channels WHERE channel_rank <= 5 ORDER BY segment_name, channel_rank;

-- =====================================================================================
-- STEP 5 · Profile facts per segment (what DS shares + what the persona cards need)
-- =====================================================================================
CREATE OR REPLACE VIEW clean.segment_profile AS
WITH seg AS (SELECT * FROM clean.dashboard_segments)
SELECT d.segment_order, d.segment_name, d.customers,
       round(100.0 * d.customers / sum(d.customers) OVER (), 1)                               AS pct_of_customers,
       c.pct_of_deal_value, c.conversion_pct, c.late_payments_pct, c.median_first_reply_h,
       (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY cc.price_level_gbp)::numeric, -3)
          FROM seg s JOIN clean.clean_customers cc USING (customer_id) WHERE s.segment_name = d.segment_name) AS median_price_level_gbp,
       (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY cc.rent_level_pcm)::numeric, -1)
          FROM seg s JOIN clean.clean_customers cc USING (customer_id) WHERE s.segment_name = d.segment_name) AS median_rent_pcm,
       (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY l.days_to_decision)
          FROM seg s JOIN clean.clean_leads l USING (customer_id) WHERE s.segment_name = d.segment_name) AS median_days_to_decide,
       (SELECT mode() WITHIN GROUP (ORDER BY cc.region_label)
          FROM seg s JOIN clean.clean_customers cc USING (customer_id) WHERE s.segment_name = d.segment_name) AS main_home_region,
       (SELECT mode() WITHIN GROUP (ORDER BY f.top_region_viewed)
          FROM seg s JOIN feat.customer_features f USING (customer_id) WHERE s.segment_name = d.segment_name) AS main_region_viewed,
       (SELECT channel FROM clean.segment_channels sc WHERE sc.segment_name = d.segment_name AND sc.channel_rank = 1 LIMIT 1) AS top_channel,
       (SELECT round(100.0 * avg(CASE WHEN cc.is_overseas THEN 1 ELSE 0 END), 1)
          FROM seg s JOIN clean.clean_customers cc USING (customer_id) WHERE s.segment_name = d.segment_name) AS pct_overseas,
       (SELECT mode() WITHIN GROUP (ORDER BY f.main_device)
          FROM seg s JOIN feat.customer_features f USING (customer_id) WHERE s.segment_name = d.segment_name) AS main_device
FROM clean.segment_dim d
JOIN clean.segment_comparison c ON c.segment_name = d.segment_name
JOIN clean.segment_in_use u ON u.model_version = c.model_version;

SELECT * FROM clean.segment_profile ORDER BY segment_order;

-- =====================================================================================
-- STEP 6 · Provisional names: a one-line description drafted from the numbers
-- (edit the wording with DS; keep the numbers)
-- =====================================================================================
SELECT segment_name AS current_name,
       segment_name || ': ' || pct_of_customers || '% of customers, ' || pct_of_deal_value || '% of deal value; '
       || 'converts ' || conversion_pct || '%, decides in ' || median_days_to_decide || ' days, arrives mostly via '
       || top_channel || ', looks most at ' || main_region_viewed || '.' AS draft_one_liner
FROM clean.segment_profile ORDER BY segment_order;

-- =====================================================================================
-- STEP 7 · Timing: which segments surged before the April 2025 stamp duty change?
-- Stamp duty thresholds fell back on 1 April 2025, so buyers rushed to complete by March.
-- For every segment: leads per month, indexed on that segment's OWN baseline
-- (average month Sep-Dec 2024, before the rush) so small and large segments compare fairly.
-- 100 = a normal month for that segment; 150 = 50% busier than normal.
-- =====================================================================================
CREATE OR REPLACE VIEW clean.segment_stamp_duty AS
WITH m AS (
    SELECT d.segment_name, date_trunc('month', l.created_day)::date AS month, count(*) AS leads
    FROM clean.clean_leads l JOIN clean.dashboard_segments d USING (customer_id)
    WHERE l.created_day BETWEEN DATE '2024-09-01' AND DATE '2025-09-30'
    GROUP BY 1, 2
),
c AS (   -- sale completions by month (the deadline that mattered)
    SELECT d.segment_name, date_trunc('month', t.completion_or_move_in_date)::date AS month, count(*) AS completions
    FROM clean.clean_transactions t JOIN clean.dashboard_segments d USING (customer_id)
    WHERE t.deal_kind = 'Sale' AND t.completion_or_move_in_date BETWEEN DATE '2024-09-01' AND DATE '2025-09-30'
    GROUP BY 1, 2
),
base AS (
    SELECT segment_name, avg(leads) AS base_leads
    FROM m WHERE month BETWEEN DATE '2024-09-01' AND DATE '2024-12-01' GROUP BY 1
),
cbase AS (
    SELECT segment_name, avg(completions) AS base_completions
    FROM c WHERE month BETWEEN DATE '2024-09-01' AND DATE '2024-12-01' GROUP BY 1
)
SELECT m.segment_name, m.month, m.leads,
       round(100 * m.leads / b.base_leads) AS leads_index,
       coalesce(c.completions, 0) AS sale_completions,
       round(100 * coalesce(c.completions, 0) / nullif(cb.base_completions, 0)) AS completions_index,
       (m.month = DATE '2025-03-01') AS is_rush_month
FROM m
JOIN base b USING (segment_name)
LEFT JOIN c USING (segment_name, month)
LEFT JOIN cbase cb USING (segment_name);

-- The line chart (Overview or Segment deep dive): one line per segment, x = month, y = leads_index
SELECT * FROM clean.segment_stamp_duty ORDER BY segment_name, month;

-- Who surged? March 2025 against each segment's own normal month, and the April drop
SELECT s.segment_name,
       max(s.leads_index)       FILTER (WHERE s.month = DATE '2025-03-01') AS march_leads_index,
       max(s.completions_index) FILTER (WHERE s.month = DATE '2025-03-01') AS march_completions_index,
       max(s.completions_index) FILTER (WHERE s.month = DATE '2025-04-01') AS april_completions_index,
       sum(s.sale_completions)  FILTER (WHERE s.month BETWEEN DATE '2025-01-01' AND DATE '2025-03-01') AS completions_jan_mar_2025
FROM clean.segment_stamp_duty s
GROUP BY 1 ORDER BY 2 DESC NULLS LAST;

-- And when do they browse? Share of each segment's sessions by hour of day (UK time)
CREATE OR REPLACE VIEW clean.segment_browsing_hours AS
SELECT d.segment_name, w.session_hour_uk, count(*) AS sessions,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY d.segment_name), 2) AS pct_of_segment_sessions
FROM clean.clean_web_sessions w JOIN clean.dashboard_segments d USING (customer_id)
GROUP BY 1, 2;

SELECT segment_name,
       round(sum(pct_of_segment_sessions) FILTER (WHERE session_hour_uk < 6), 1) AS pct_sessions_00_06_uk,
       (array_agg(session_hour_uk ORDER BY sessions DESC))[1] AS busiest_hour_uk
FROM clean.segment_browsing_hours GROUP BY 1 ORDER BY 2 DESC;

-- =====================================================================================
-- DAY 11 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · For each segment, where do they look, how do they arrive and how do they browse?
SELECT p.segment_name, p.main_region_viewed, p.top_channel, p.main_device,
       max(i.segment_value) FILTER (WHERE i.metric = 'Night browsing (00-06 UK)') AS pct_night,
       max(i.segment_value) FILTER (WHERE i.metric = 'Virtual-tour share')        AS pct_virtual_tour,
       max(i.segment_value) FILTER (WHERE i.metric = 'Mobile sessions')           AS pct_mobile
FROM clean.segment_profile p JOIN clean.segment_index i USING (segment_name)
GROUP BY p.segment_order, p.segment_name, p.main_region_viewed, p.top_channel, p.main_device
ORDER BY p.segment_order;

-- Q2 · Which channel brings in the most valuable segment, and is marketing spend going there?
-- Most valuable = highest deal value per customer. Spend: campaigns, by the channel of the campaign.
WITH best AS (SELECT segment_name FROM clean.segment_index
              WHERE metric = 'Deal value per customer' ORDER BY segment_value DESC LIMIT 1),
camp_leads AS (
    SELECT c.channel AS campaign_channel,
           count(*) AS campaign_leads,
           count(*) FILTER (WHERE s.segment_name = (SELECT segment_name FROM best)) AS best_segment_leads
    FROM clean.clean_leads l JOIN clean.clean_campaigns c USING (campaign_id)
    JOIN clean.dashboard_segments s USING (customer_id)
    GROUP BY 1
),
spend AS (SELECT channel AS campaign_channel, sum(spend_gbp)::numeric AS spend FROM clean.clean_campaigns GROUP BY 1)
SELECT (SELECT segment_name FROM best) AS most_valuable_segment, campaign_channel,
       round(100.0 * spend / sum(spend) OVER (), 1) AS pct_of_spend,
       round(100.0 * best_segment_leads / sum(best_segment_leads) OVER (), 1) AS pct_of_best_segment_campaign_leads,
       round(100.0 * best_segment_leads / campaign_leads, 1) AS best_segment_pct_of_channel_leads,
       round((spend / nullif(best_segment_leads, 0))::numeric, 0) AS spend_per_best_segment_lead_gbp
FROM camp_leads JOIN spend USING (campaign_channel)
ORDER BY pct_of_spend DESC;
-- and across ALL channels (not only campaigns): where does the most valuable segment come from?
SELECT sc.* FROM clean.segment_channels sc
WHERE sc.segment_name = (SELECT segment_name FROM clean.segment_index WHERE metric = 'Deal value per customer' ORDER BY segment_value DESC LIMIT 1)
ORDER BY channel_rank;

-- Q3 · Which segment takes longest to decide, and what should agents do differently for them?
-- What they ask about (inbound topics), compared with everyone: index > 100 = asked about more often.
WITH slow AS (SELECT segment_name FROM clean.segment_profile ORDER BY median_days_to_decide DESC LIMIT 1),
t AS (
    SELECT i.topic, (s.segment_name = (SELECT segment_name FROM slow)) AS is_slow, count(*) AS n
    FROM clean.clean_interactions i JOIN clean.clean_leads l USING (lead_id)
    JOIN clean.dashboard_segments s USING (customer_id)
    WHERE i.direction = 'Inbound' GROUP BY 1, 2
)
SELECT (SELECT segment_name FROM slow) AS slowest_segment, topic,
       round(100.0 * sum(n) FILTER (WHERE is_slow) / sum(sum(n) FILTER (WHERE is_slow)) OVER (), 1) AS pct_of_slow_segment_topics,
       round(100.0 * sum(n) / sum(sum(n)) OVER (), 1) AS pct_of_all_topics,
       round(100 * (sum(n) FILTER (WHERE is_slow) / sum(sum(n) FILTER (WHERE is_slow)) OVER ())
                 / (sum(n) / sum(sum(n)) OVER ())) AS topic_index
FROM t GROUP BY topic ORDER BY topic_index DESC NULLS LAST;
SELECT segment_name, median_days_to_decide, conversion_pct FROM clean.segment_profile ORDER BY median_days_to_decide DESC;

-- OWN QUESTION A · Which segment is furthest above average on deal value, and furthest below on conversion?
SELECT metric, segment_name, index_vs_average
FROM (SELECT *, rank() OVER (PARTITION BY metric ORDER BY index_vs_average DESC) AS hi,
                rank() OVER (PARTITION BY metric ORDER BY index_vs_average) AS lo
      FROM clean.segment_index WHERE metric IN ('Deal value per customer', 'Conversion')) x
WHERE hi = 1 OR lo = 1 ORDER BY metric, index_vs_average DESC;

-- OWN QUESTION B · Does each segment's best-converting channel differ from its biggest channel?
SELECT segment_name,
       max(channel) FILTER (WHERE channel_rank = 1) AS biggest_channel,
       (SELECT sc2.channel FROM clean.segment_channels sc2
         WHERE sc2.segment_name = sc.segment_name AND sc2.leads >= 200
         ORDER BY sc2.conversion_pct DESC LIMIT 1) AS best_converting_channel_200plus_leads
FROM clean.segment_channels sc GROUP BY segment_name ORDER BY 1;

-- Just checking
SELECT * FROM clean.segment_in_use;
SELECT count(*) FROM clean.dashboard_segments;
