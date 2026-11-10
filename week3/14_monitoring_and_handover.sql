-- DAY 15 · Monitoring after handover: data quality checks + segment-size drift over 20%

-- =====================================================================================
-- STEP 1 · One-off set-up: the log table and the segment-size baseline at go-live
-- =====================================================================================
DROP TABLE IF EXISTS clean.monitoring_log CASCADE;
CREATE TABLE clean.monitoring_log (
    run_at       TIMESTAMP DEFAULT now(),
    check_group  VARCHAR,          -- Data quality / Segment drift / Freshness
    check_name   VARCHAR,
    value        NUMERIC,
    threshold    NUMERIC,
    status       VARCHAR           -- OK / ALERT
);

-- Segment sizes at go-live: drift is measured against this snapshot
DROP TABLE IF EXISTS clean.segment_size_baseline;
CREATE TABLE clean.segment_size_baseline AS
SELECT model_version, segment_name, count(*) AS customers, now() AS captured_at
FROM clean.dashboard_segments GROUP BY 1, 2;
SELECT * FROM clean.segment_size_baseline ORDER BY customers DESC;

-- =====================================================================================
-- STEP 2 · The monthly monitoring run (select from here to the end of STEP 2, then F5)
-- =====================================================================================
BEGIN;   -- one transaction, so every check of this run gets the same run_at time

-- 2a. Data quality: each check must be 0 (or under its threshold)
INSERT INTO clean.monitoring_log (check_group, check_name, value, threshold, status)
SELECT 'Data quality', check_name, value, threshold, CASE WHEN value > threshold THEN 'ALERT' ELSE 'OK' END
FROM (VALUES
  ('Duplicate customers (same e-mail hash) in clean_customers',
     (SELECT count(*) FROM (SELECT email_sha256 FROM clean.clean_customers GROUP BY 1 HAVING count(*) > 1) x)::numeric, 0),
  ('Leads whose customer is missing from clean_customers',
     (SELECT count(*) FROM clean.clean_leads l LEFT JOIN clean.clean_customers c USING (customer_id) WHERE c.customer_id IS NULL)::numeric, 0),
  ('Lead-source spellings not in the mapping table',
     (SELECT count(DISTINCT lead_source) FROM raw.leads WHERE lead_source NOT IN (SELECT raw_value FROM clean.lead_source_map))::numeric, 0),
  ('Country labels not in the mapping table',
     (SELECT count(DISTINCT country_of_residence) FROM raw.customers WHERE country_of_residence NOT IN (SELECT raw_value FROM clean.country_map))::numeric, 0),
  ('Purchase budgets under £5,000 left in clean_customers',
     (SELECT count(*) FROM clean.clean_customers WHERE stated_budget_gbp < 5000)::numeric, 0),
  ('Customers without a segment',
     (SELECT count(*) FROM clean.clean_customers c LEFT JOIN clean.dashboard_segments d USING (customer_id) WHERE d.customer_id IS NULL)::numeric, 0),
  ('Segments without a priority tier',
     (SELECT count(*) FROM clean.segment_dim d LEFT JOIN clean.segment_tiers t USING (segment_name) WHERE t.segment_name IS NULL)::numeric, 0),
  ('Payments with a negative amount',
     (SELECT count(*) FROM raw.payments WHERE amount_gbp < 0)::numeric, 4),       -- 4 known, explained by finance
  ('Inbound contacts with no reply time (%)',
     (SELECT round(100.0 * avg(CASE WHEN response_time_min IS NULL THEN 1 ELSE 0 END), 2) FROM raw.interactions WHERE direction = 'Inbound'), 3)
) AS q(check_name, value, threshold);

-- 2b. Freshness: days since the newest lead (alert if the feed has stopped for over 7 days)
INSERT INTO clean.monitoring_log (check_group, check_name, value, threshold, status)
SELECT 'Freshness', 'Days between the newest lead and the data cut-off (30 Sep 2026; use current_date in production)',
       DATE '2026-09-30' - max(created_day), 7,
       CASE WHEN DATE '2026-09-30' - max(created_day) > 7 THEN 'ALERT' ELSE 'OK' END
FROM clean.clean_leads;

-- 2c. Segment drift: alert when a segment's size moves more than 20% from the go-live baseline
INSERT INTO clean.monitoring_log (check_group, check_name, value, threshold, status)
SELECT 'Segment drift', 'Size change vs baseline: ' || coalesce(n.segment_name, b.segment_name),
       round(100.0 * abs(coalesce(n.customers, 0)::numeric / nullif(b.customers, 0) - 1), 1), 20,
       CASE WHEN b.customers IS NULL OR n.customers IS NULL
              OR abs(n.customers::numeric / b.customers - 1) > 0.20 THEN 'ALERT' ELSE 'OK' END
FROM (SELECT segment_name, count(*) AS customers FROM clean.dashboard_segments GROUP BY 1) n
FULL JOIN clean.segment_size_baseline b USING (segment_name);

COMMIT;
-- (end of STEP 2)

-- =====================================================================================
-- STEP 3 · What needs attention (Power BI Data check page loads this view)
-- =====================================================================================
CREATE OR REPLACE VIEW clean.monitoring_latest AS
SELECT * FROM clean.monitoring_log WHERE run_at = (SELECT max(run_at) FROM clean.monitoring_log);

SELECT check_group, check_name, value, threshold, status FROM clean.monitoring_latest ORDER BY status, check_group, check_name;
SELECT status, count(*) FROM clean.monitoring_latest GROUP BY 1;

-- Test the drift alert: pretend one segment grew by 25% (run, look, then ROLLBACK)
BEGIN;
UPDATE clean.segment_size_baseline SET customers = round(customers / 1.25)
WHERE segment_name = (SELECT segment_name FROM clean.segment_size_baseline ORDER BY customers DESC LIMIT 1);
SELECT b.segment_name, b.customers AS baseline, n.customers AS now,
       round(100.0 * (n.customers::numeric / b.customers - 1), 1) AS change_pct,
       CASE WHEN abs(n.customers::numeric / b.customers - 1) > 0.20 THEN 'ALERT' ELSE 'OK' END AS status
FROM clean.segment_size_baseline b
JOIN (SELECT segment_name, count(*) AS customers FROM clean.dashboard_segments GROUP BY 1) n USING (segment_name);
ROLLBACK;

-- =====================================================================================
-- DAY 15 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · Which segment is Veltrix's biggest opportunity, and what should the business do about it
--      in the next 90 days?
-- Sizing the reply-speed lever per segment (last 12 months): if the share of leads answered
-- within 1 hour rose to 50%, and those leads converted like today's fast-answered ones.
-- This is an UPPER BOUND: fast replies also go to easier leads (Day 5: speed explains about
-- half of the seniority gap), so present half of it as the realistic case.
WITH l AS (
    SELECT d.segment_name, l.first_response_min, l.converted, t.deal_value_gbp
    FROM clean.clean_leads l JOIN clean.dashboard_segments d USING (customer_id)
    LEFT JOIN clean.clean_transactions t USING (lead_id)
    WHERE l.is_closed = 1 AND l.closed_date BETWEEN DATE '2025-10-01' AND DATE '2026-09-30'
      AND l.first_response_min IS NOT NULL
), s AS (
    SELECT segment_name, count(*) AS closed_leads_12m,
           avg(CASE WHEN first_response_min < 60 THEN 1.0 ELSE 0 END) AS share_1h,
           avg(CASE WHEN converted THEN 1.0 ELSE 0 END) FILTER (WHERE first_response_min < 60)  AS conv_1h,
           avg(CASE WHEN converted THEN 1.0 ELSE 0 END) FILTER (WHERE first_response_min >= 60) AS conv_later,
           avg(deal_value_gbp) FILTER (WHERE converted) AS avg_deal_value
    FROM l GROUP BY 1
)
SELECT s.segment_name, t.priority_tier, s.closed_leads_12m,
       round(100 * s.share_1h, 1) AS pct_within_1h_now,
       round(100 * s.conv_1h, 1) AS conversion_if_within_1h, round(100 * s.conv_later, 1) AS conversion_if_later,
       round(s.closed_leads_12m * (0.50 - s.share_1h) * (s.conv_1h - s.conv_later)) AS extra_wins_per_year_upper,
       round((s.closed_leads_12m * (0.50 - s.share_1h) * (s.conv_1h - s.conv_later) * s.avg_deal_value / 1e6)::numeric, 1) AS extra_deal_value_m_per_year_upper,
       round((s.closed_leads_12m * (0.50 - s.share_1h) * (s.conv_1h - s.conv_later) * s.avg_deal_value / 1e6 / 4 / 2)::numeric, 1) AS realistic_deal_value_m_next_90_days
FROM s JOIN clean.segment_tiers t USING (segment_name)
ORDER BY extra_deal_value_m_per_year_upper DESC;

-- Q2 · What would we want to measure in the next version of this dashboard?
--   Data we do not have today (ask for it): agent capacity and rota (to size P1 cover), marketing
--   spend per segment and per lead source (portal fees are missing), commission/fee income
--   (deal value is not revenue), why leads are lost in more detail, and customer satisfaction.
--   Measures to add once the test runs: test vs control trend, segment movement month to month,
--   and P1 leads answered within 1 hour as a daily operational KPI.

-- OWN QUESTION A · Did the monitoring run find anything that needs action?
SELECT check_name, value, threshold FROM clean.monitoring_latest WHERE status = 'ALERT';

-- OWN QUESTION B · How much of the 12-month deal value comes from P1 segments?
SELECT t.priority_tier, round((sum(x.deal_value_gbp) / 1e6)::numeric, 1) AS deal_value_m_12m,
       round((100.0 * sum(x.deal_value_gbp) / sum(sum(x.deal_value_gbp)) OVER ())::numeric, 1) AS pct
FROM clean.clean_transactions x JOIN clean.dashboard_segments d USING (customer_id)
JOIN clean.segment_tiers t USING (segment_name)
WHERE x.contract_date BETWEEN DATE '2025-10-01' AND DATE '2026-09-30'
GROUP BY 1 ORDER BY 1;
