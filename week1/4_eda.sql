-- =====================================================================================
-- DAY 5 · Exploratory analysis: one view per chart, then the Day 5 business questions
-- Needs: Day 4 (clean.clean_*). Every view reads the clean tables, so SQL and Power BI agree.
-- Run in pgAdmin: Query Tool on veltrix. Run it all (F5), then query the views one by one.
-- Conversion = Won / (Won + Lost): open leads are left out.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS eda;

-- -------------------------------------------------------------------------------------
-- 1 · Monthly leads and sale completions (Overview line chart; stamp duty marker 1 Apr 2025)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW eda.monthly_trend AS
WITH l AS (SELECT date_trunc('month', created_date)::DATE AS month,
                  count(*) AS leads,
                  count(*) FILTER (WHERE intent = 'Buy')  AS sales_leads,
                  count(*) FILTER (WHERE intent = 'Rent') AS lettings_leads
           FROM clean.clean_leads GROUP BY 1),
     c AS (SELECT date_trunc('month', completion_or_move_in_date)::DATE AS month,
                  count(*) FILTER (WHERE deal_kind = 'Sale')    AS sale_completions,
                  count(*) FILTER (WHERE deal_kind = 'Letting') AS move_ins
           FROM clean.clean_transactions WHERE completion_or_move_in_date <= '2026-09-30' GROUP BY 1)
SELECT l.month, l.leads, l.sales_leads, l.lettings_leads,
       coalesce(c.sale_completions, 0) AS sale_completions, coalesce(c.move_ins, 0) AS move_ins
FROM l LEFT JOIN c USING (month) ORDER BY l.month;

-- -------------------------------------------------------------------------------------
-- 2 · Seasonality index (100 = normal for the trend). Shows the August dip and December slump.
-- Each month / its centred 12-month moving average, averaged by calendar month,
-- 2024 onward, leaving out the stamp-duty months Jan-May 2025.
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW eda.seasonality_index AS
WITH series AS (
    SELECT 'Sales leads' AS measure, date_trunc('month', created_date) AS m, count(*)::NUMERIC AS n
    FROM clean.clean_leads WHERE intent = 'Buy' GROUP BY 2
    UNION ALL
    SELECT 'Lettings leads', date_trunc('month', created_date), count(*) FROM clean.clean_leads WHERE intent = 'Rent' GROUP BY 2
    UNION ALL
    SELECT 'Sale completions', date_trunc('month', completion_or_move_in_date), count(*)
    FROM clean.clean_transactions WHERE deal_kind = 'Sale' AND completion_or_move_in_date <= '2026-09-30' GROUP BY 2
), cma AS (
    SELECT measure, m, n,
           avg(n) OVER w1 AS a1, count(n) OVER w1 AS c1,
           avg(n) OVER w2 AS a2, count(n) OVER w2 AS c2
    FROM series
    WINDOW w1 AS (PARTITION BY measure ORDER BY m ROWS BETWEEN 6 PRECEDING AND 5 FOLLOWING),
           w2 AS (PARTITION BY measure ORDER BY m ROWS BETWEEN 5 PRECEDING AND 6 FOLLOWING)
), ratio AS (
    SELECT measure, m, n / ((a1 + a2) / 2) AS r
    FROM cma
    WHERE c1 = 12 AND c2 = 12 AND m >= '2024-01-01'
      AND NOT (m BETWEEN '2025-01-01' AND '2025-05-01')
)
SELECT measure, EXTRACT(MONTH FROM m)::INT AS month_no, to_char(min(m), 'Mon') AS month,
       round(avg(r) * 100) AS seasonal_index
FROM ratio GROUP BY measure, 2 ORDER BY measure, 2;

-- -------------------------------------------------------------------------------------
-- 3 · Stamp duty window Dec 2024 - May 2025
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW eda.stamp_duty_window AS
SELECT to_char(month, 'Mon YYYY') AS month_label, month, leads, sale_completions
FROM eda.monthly_trend WHERE month BETWEEN '2024-12-01' AND '2025-05-01' ORDER BY month;

-- -------------------------------------------------------------------------------------
-- 4 · Conversion by channel (clean lead source)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW eda.conversion_by_channel AS
SELECT lead_source AS channel, channel_group, count(*) AS closed_leads,
       sum(CASE WHEN converted THEN 1 ELSE 0 END) AS won,
       round(100.0 * avg(CASE WHEN converted THEN 1 ELSE 0 END), 2) AS conversion_pct
FROM clean.clean_leads WHERE is_closed = 1
GROUP BY 1, 2 ORDER BY conversion_pct DESC;

-- -------------------------------------------------------------------------------------
-- 5 · Conversion by time to first reply (Pipeline column chart, with lead counts)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW eda.conversion_by_reply_band AS
SELECT first_reply_band, count(*) AS closed_leads,
       sum(CASE WHEN converted THEN 1 ELSE 0 END) AS won,
       round(100.0 * avg(CASE WHEN converted THEN 1 ELSE 0 END), 2) AS conversion_pct
FROM clean.clean_leads WHERE is_closed = 1 AND first_reply_band <> 'Unknown'
GROUP BY 1 ORDER BY 1;

-- -------------------------------------------------------------------------------------
-- 6 · Agent seniority: median first reply and conversion (Pipeline bar chart)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW eda.agent_seniority AS
SELECT a.seniority, count(*) AS closed_leads,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY l.first_response_min) AS median_first_reply_min,
       round(100.0 * avg(CASE WHEN l.converted THEN 1 ELSE 0 END), 2) AS conversion_pct
FROM clean.clean_leads l JOIN clean.clean_agents a USING (agent_id)
WHERE l.is_closed = 1
GROUP BY 1 ORDER BY median_first_reply_min;

-- Seniority x reply band: needed for "skill or speed?"
CREATE OR REPLACE VIEW eda.seniority_by_reply_band AS
SELECT l.first_reply_band, a.seniority, count(*) AS closed_leads,
       round(100.0 * avg(CASE WHEN l.converted THEN 1 ELSE 0 END), 1) AS conversion_pct
FROM clean.clean_leads l JOIN clean.clean_agents a USING (agent_id)
WHERE l.is_closed = 1 AND l.first_reply_band <> 'Unknown'
GROUP BY 1, 2 ORDER BY 1, 2;

-- -------------------------------------------------------------------------------------
-- 7 · Overseas share, night-time browsing, device mix, virtual tours
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW eda.overseas_share AS
SELECT (SELECT round(100.0 * avg(CASE WHEN is_overseas THEN 1 ELSE 0 END), 2) FROM clean.clean_customers) AS pct_of_customers,
       round(100.0 * avg(CASE WHEN c.is_overseas THEN 1 ELSE 0 END), 2)                                   AS pct_of_sale_deals,
       round((100.0 * sum(CASE WHEN c.is_overseas THEN t.deal_value_gbp END) / sum(t.deal_value_gbp))::NUMERIC, 2) AS pct_of_sale_value
FROM clean.clean_transactions t JOIN clean.clean_customers c USING (customer_id)
WHERE t.deal_kind = 'Sale';

CREATE OR REPLACE VIEW eda.overseas_by_country AS
SELECT country_of_residence, country_iso2, count(*) AS customers
FROM clean.clean_customers WHERE is_overseas GROUP BY 1, 2 ORDER BY 3 DESC;

CREATE OR REPLACE VIEW eda.browsing_by_hour AS
SELECT CASE WHEN c.is_overseas THEN 'Overseas customers' ELSE 'UK customers' END AS customer_group,
       w.session_hour_uk AS hour_uk, count(*) AS sessions,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY c.is_overseas), 2) AS pct_of_group_sessions
FROM clean.clean_web_sessions w JOIN clean.clean_customers c USING (customer_id)
GROUP BY c.is_overseas, w.session_hour_uk ORDER BY 1, 2;

CREATE OR REPLACE VIEW eda.night_share AS
SELECT customer_group, sum(pct_of_group_sessions) AS pct_sessions_00_to_06
FROM eda.browsing_by_hour WHERE hour_uk < 6 GROUP BY 1;

CREATE OR REPLACE VIEW eda.device_mix AS
SELECT c.primary_intent || CASE WHEN c.is_overseas THEN ' - overseas' ELSE ' - UK' END AS customer_group,
       w.device, count(*) AS sessions,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY c.primary_intent, c.is_overseas), 1) AS pct_of_group
FROM clean.clean_web_sessions w JOIN clean.clean_customers c USING (customer_id)
GROUP BY c.primary_intent, c.is_overseas, w.device ORDER BY 1, 2;

CREATE OR REPLACE VIEW eda.virtual_tour_share AS
SELECT CASE WHEN c.is_overseas THEN 'Overseas' ELSE 'UK' END AS customer_group, c.primary_intent,
       count(*) AS property_events,
       round(100.0 * avg(CASE WHEN v.event_type = 'Virtual tour' THEN 1 ELSE 0 END), 2) AS virtual_tour_pct
FROM clean.clean_property_views v
JOIN clean.clean_web_sessions w USING (session_id)
JOIN clean.clean_customers c ON c.customer_id = w.customer_id
GROUP BY 1, 2 ORDER BY 1, 2;

-- -------------------------------------------------------------------------------------
-- 8 · Late or overdue share by month due, last 12 months (Payments column chart)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW eda.late_share_by_month_due AS
SELECT date_trunc('month', due_date)::DATE AS month_due, count(*) AS payments_due,
       sum(is_late_or_overdue) AS late_or_overdue,
       sum(CASE WHEN status = 'Overdue' THEN 1 ELSE 0 END) AS still_overdue,
       round(100.0 * avg(is_late_or_overdue), 2) AS late_pct
FROM clean.clean_payments
WHERE due_date BETWEEN '2025-10-01' AND '2026-09-30' AND status <> 'Scheduled'
GROUP BY 1 ORDER BY 1;

-- -------------------------------------------------------------------------------------
-- 9 · Deal value by transaction type, and lost reasons
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW eda.deal_value_by_type AS
SELECT transaction_type, deal_kind, count(*) AS deals,
       round((sum(deal_value_gbp) / 1e6)::NUMERIC, 1) AS deal_value_gbp_m,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_of_deals,
       round((100.0 * sum(deal_value_gbp) / sum(sum(deal_value_gbp)) OVER ())::NUMERIC, 1) AS pct_of_value
FROM clean.clean_transactions GROUP BY 1, 2 ORDER BY deal_value_gbp_m DESC;

CREATE OR REPLACE VIEW eda.lost_reasons AS
SELECT intent, lost_reason, count(*) AS lost_leads,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY intent), 1) AS pct_of_intent_lost
FROM clean.clean_leads WHERE lead_stage = 'Lost'
GROUP BY 1, 2 ORDER BY 1, 3 DESC;

-- =====================================================================================
-- DAY 5 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · Did the stamp duty change pull demand forward? How much higher was March 2025 than February?
SELECT * FROM eda.stamp_duty_window;
SELECT f.leads AS leads_feb_2025, m.leads AS leads_mar_2025,
       round(100.0 * (m.leads::NUMERIC / f.leads - 1), 1) AS leads_mar_vs_feb_pct,
       f.sale_completions AS completions_feb, m.sale_completions AS completions_mar, a.sale_completions AS completions_apr,
       round(m.sale_completions::NUMERIC / f.sale_completions, 2) AS completions_mar_vs_feb_times,
       round(100.0 * (a.sale_completions::NUMERIC / m.sale_completions - 1), 1) AS completions_apr_vs_mar_pct
FROM eda.monthly_trend f, eda.monthly_trend m, eda.monthly_trend a
WHERE f.month = '2025-02-01' AND m.month = '2025-03-01' AND a.month = '2025-04-01';

-- Q2 · Do leads answered within an hour convert more often than leads left for a day? By how much?
SELECT * FROM eda.conversion_by_reply_band;
SELECT round(max(conversion_pct) FILTER (WHERE first_reply_band = '1. Under 1 hour')
           / max(conversion_pct) FILTER (WHERE first_reply_band = '4. Over 24 hours'), 1) AS times_higher_under_1h_vs_over_24h
FROM eda.conversion_by_reply_band;

-- Q3 · Do senior agents convert better because they are more skilled or because they reply faster?
-- Method: give juniors the seniors' mix of reply speeds, keep juniors' own conversion in each band.
-- The share of the gap that closes = the part explained by speed.
SELECT * FROM eda.agent_seniority;
WITH r AS (SELECT * FROM eda.seniority_by_reply_band),
     mix AS (SELECT first_reply_band, closed_leads::NUMERIC / sum(closed_leads) OVER () AS senior_share FROM r WHERE seniority = 'Senior'),
     actual AS (SELECT seniority, sum(conversion_pct * closed_leads) / sum(closed_leads) AS conv FROM r GROUP BY 1)
SELECT round((SELECT conv FROM actual WHERE seniority = 'Senior'), 1) AS senior_conversion_pct,
       round((SELECT conv FROM actual WHERE seniority = 'Junior'), 1) AS junior_conversion_pct,
       round(sum(j.conversion_pct * m.senior_share), 1)               AS junior_at_senior_speed_pct,
       round(100 * (sum(j.conversion_pct * m.senior_share) - (SELECT conv FROM actual WHERE seniority = 'Junior'))
             / ((SELECT conv FROM actual WHERE seniority = 'Senior') - (SELECT conv FROM actual WHERE seniority = 'Junior')), 0) AS pct_of_gap_explained_by_speed
FROM mix m JOIN r j ON j.first_reply_band = m.first_reply_band AND j.seniority = 'Junior';

-- Q4 · Is late payment seasonal, or is the latest month just not yet chased?
-- (a) Late share by calendar month over all due payments: flat = not seasonal
SELECT EXTRACT(MONTH FROM due_date)::INT AS month_no, to_char(min(due_date), 'Mon') AS month,
       count(*) AS payments_due, round(100.0 * avg(is_late_or_overdue), 2) AS late_pct
FROM clean.clean_payments WHERE status <> 'Scheduled' AND due_date <= '2026-09-30'
GROUP BY 1 ORDER BY 1;
-- (b) Last 12 months: the latest months are mostly "Overdue" (not yet chased), older ones "Paid late"
SELECT * FROM eda.late_share_by_month_due;

-- Other EDA profiles for the summary
SELECT * FROM eda.seasonality_index;      -- August dip, December slump
SELECT * FROM eda.conversion_by_channel;  -- best and worst channels
SELECT * FROM eda.overseas_share;
SELECT * FROM eda.night_share;
SELECT * FROM eda.device_mix;
SELECT * FROM eda.virtual_tour_share;
SELECT * FROM eda.deal_value_by_type;

-- OWN QUESTION A · Why are leads lost, and how many losses are avoidable (no response)?
SELECT * FROM eda.lost_reasons;
SELECT count(*) FILTER (WHERE lost_reason = 'No response') AS lost_no_response,
       round(100.0 * count(*) FILTER (WHERE lost_reason = 'No response') / count(*), 1) AS pct_of_lost
FROM clean.clean_leads WHERE lead_stage = 'Lost';

-- OWN QUESTION B · Do overseas buyers convert as well as UK buyers?
SELECT CASE WHEN c.is_overseas THEN 'Overseas' ELSE 'UK' END AS customer_group,
       count(*) AS closed_buy_leads,
       round(100.0 * avg(CASE WHEN l.converted THEN 1 ELSE 0 END), 1) AS conversion_pct,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY l.first_response_min) AS median_first_reply_min
FROM clean.clean_leads l JOIN clean.clean_customers c USING (customer_id)
WHERE l.is_closed = 1 AND l.intent = 'Buy'
GROUP BY 1;
