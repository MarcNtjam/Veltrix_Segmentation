-- =====================================================================================
-- DAY 14 · CRM activation and the campaign test: exports, audiences, campaign targets,
--          test assignment and the weekly monitoring query
-- Needs: Day 12 (clean.segment_tiers). Run in pgAdmin on veltrix, ONE STEP AT A TIME.
-- Exports: run the SELECT, then the download button above the results (Save results to file).
-- =====================================================================================

-- =====================================================================================
-- STEP 1 · CRM export: every customer with segment_name and priority tier
-- =====================================================================================
CREATE OR REPLACE VIEW clean.crm_export AS
SELECT d.customer_id, d.segment_name, t.priority_tier, d.model_version,
       DATE '2026-09-30' AS data_to, current_date AS exported_on
FROM clean.dashboard_segments d
JOIN clean.segment_tiers t USING (segment_name);

-- The file for the CRM team (100,573 rows): save as crm_segments_<date>.csv
SELECT customer_id, segment_name, priority_tier, model_version FROM clean.crm_export ORDER BY customer_id;

-- Check against the dashboard: counts per segment and tier (Data check page must show the same)
CREATE OR REPLACE VIEW clean.crm_export_counts AS
SELECT segment_name, priority_tier, count(*) AS customers_in_export FROM clean.crm_export GROUP BY 1, 2;
SELECT * FROM clean.crm_export_counts ORDER BY priority_tier, customers_in_export DESC;
SELECT priority_tier, count(*) AS customers FROM clean.crm_export GROUP BY 1 ORDER BY 1;

-- Every LEAD carries a segment and a tier (through its customer). Expect 0 without.
SELECT count(*) AS leads, count(e.customer_id) AS leads_with_segment_and_tier
FROM clean.clean_leads l LEFT JOIN clean.crm_export e USING (customer_id);

-- =====================================================================================
-- STEP 2 · Consent-filtered audiences per segment, for 5 channels (e-mail, Meta, Google, TikTok, WeChat)
-- Only customers with consent_marketing = true. Ad platforms receive SHA-256 hashes only
-- (Meta and Google Customer Match accept SHA-256 of the lower-cased, trimmed e-mail / phone).
-- Confirm with the CRM team that the stored hashes were made from normalised values.
-- =====================================================================================
-- 2a. E-mail (sent from the CRM): customer IDs only; the CRM holds the addresses
CREATE OR REPLACE VIEW clean.audience_email AS
SELECT e.segment_name, e.priority_tier, c.customer_id
FROM clean.crm_export e JOIN clean.clean_customers c USING (customer_id)
WHERE c.consent_marketing;

-- 2b. Meta custom audience: hashed e-mail + hashed phone where we have one
CREATE OR REPLACE VIEW clean.audience_meta AS
SELECT e.segment_name, c.email_sha256 AS email, c.phone_sha256 AS phone, c.country_iso2 AS country
FROM clean.crm_export e JOIN clean.clean_customers c USING (customer_id)
WHERE c.consent_marketing;

-- 2c. Google Ads Customer Match: hashed e-mail
CREATE OR REPLACE VIEW clean.audience_google AS
SELECT e.segment_name, c.email_sha256 AS email, c.country_iso2 AS country
FROM clean.crm_export e JOIN clean.clean_customers c USING (customer_id)
WHERE c.consent_marketing;

-- One file per segment per channel, e.g. (change the segment name):
SELECT email, phone, country FROM clean.audience_meta WHERE segment_name = 'Home movers and downsizers';

-- 2d. TikTok custom audience: hashed e-mail + hashed phone (TikTok Ads Manager > Assets >
--     Audiences > Custom audience > Customer file, "SHA256" chosen as the hash type)
CREATE OR REPLACE VIEW clean.audience_tiktok AS
SELECT e.segment_name, e.priority_tier, c.email_sha256 AS email, c.phone_sha256 AS phone, c.country_iso2 AS country
FROM clean.crm_export e JOIN clean.clean_customers c USING (customer_id)
WHERE c.consent_marketing;

-- 2e. WeChat (Tencent Ads) audience: Chinese-speaking markets only, hashed phone where we have one.
--     Tencent Ads accepts hashed phone numbers in a customer file; confirm with the account
--     manager that SHA-256 is accepted (some accounts ask for MD5) before uploading.
CREATE OR REPLACE VIEW clean.audience_wechat AS
SELECT e.segment_name, e.priority_tier, c.phone_sha256 AS phone, c.email_sha256 AS email, c.country_iso2 AS country
FROM clean.crm_export e JOIN clean.clean_customers c USING (customer_id)
WHERE c.consent_marketing AND c.country_iso2 IN ('CN', 'HK', 'SG', 'MY');

-- One TikTok file per segment, e.g. (change the segment name):
SELECT email, phone FROM clean.audience_tiktok WHERE segment_name = 'First-time buyers';

-- 2f. Reach per segment on all 5 channels (consenting customers only)
CREATE OR REPLACE VIEW clean.audience_reach AS
SELECT segment_name, 'E-mail' AS channel, count(*) AS reachable FROM clean.audience_email GROUP BY 1
UNION ALL SELECT segment_name, 'Meta', count(*) FROM clean.audience_meta GROUP BY 1
UNION ALL SELECT segment_name, 'Google Ads', count(*) FROM clean.audience_google GROUP BY 1
UNION ALL SELECT segment_name, 'TikTok', count(*) FROM clean.audience_tiktok GROUP BY 1
UNION ALL SELECT segment_name, 'WeChat', count(*) FROM clean.audience_wechat GROUP BY 1;

SELECT segment_name,
       max(reachable) FILTER (WHERE channel = 'E-mail')     AS email,
       max(reachable) FILTER (WHERE channel = 'Meta')       AS meta,
       max(reachable) FILTER (WHERE channel = 'Google Ads') AS google_ads,
       max(reachable) FILTER (WHERE channel = 'TikTok')     AS tiktok,
       max(reachable) FILTER (WHERE channel = 'WeChat')     AS wechat
FROM clean.audience_reach GROUP BY 1 ORDER BY 2 DESC;

-- =====================================================================================
-- STEP 3 · Next month's campaigns with a target_segment
-- Copies the September 2026 campaigns to October 2026. target_segment = the segment that
-- brought the most deal value through that campaign channel so far (edit if marketing disagrees).
-- =====================================================================================
DROP TABLE IF EXISTS clean.campaign_plan;
CREATE TABLE clean.campaign_plan AS
WITH best AS (
    SELECT channel, segment_name
    FROM (SELECT c.channel, d.segment_name, sum(o.deal_value_gbp) AS value,
                 row_number() OVER (PARTITION BY c.channel ORDER BY sum(o.deal_value_gbp) DESC) AS rn
          FROM clean.clean_leads l JOIN clean.clean_campaigns c USING (campaign_id)
          JOIN clean.dashboard_segments d USING (customer_id)
          JOIN clean.clean_transactions o ON o.lead_id = l.lead_id
          GROUP BY 1, 2) x
    WHERE rn = 1
)
SELECT replace(c.campaign_id, '202609', '202610')               AS campaign_id,
       replace(c.campaign_name, 'Sep 2026', 'Oct 2026') AS campaign_name,
       c.channel, c.theme, c.objective, c.planned_audience,
       b.segment_name                                            AS target_segment,
       DATE '2026-10-01' AS start_date, DATE '2026-10-31' AS end_date,
       round(c.spend_gbp::numeric, 2)                            AS planned_spend_gbp
FROM clean.clean_campaigns c LEFT JOIN best b USING (channel)
WHERE c.start_date = DATE '2026-09-01';

SELECT campaign_id, channel, target_segment, planned_spend_gbp FROM clean.campaign_plan ORDER BY planned_spend_gbp DESC;

-- =====================================================================================
-- STEP 4 · The campaign test: settings, assignment and the weekly monitoring query
-- The DS team writes the 6-week test design; set its values in this one row.
-- Leads from the target segment are split 50/50 into Test and Control by their lead_id
-- (a fixed hash, so a lead never changes group).
-- =====================================================================================
DROP TABLE IF EXISTS clean.test_settings CASCADE;
CREATE TABLE clean.test_settings (
    test_name        VARCHAR,
    target_segment   VARCHAR,
    start_date       DATE,
    end_date         DATE,
    data_cutoff      DATE,      -- use current_date in production; 30 Sep 2026 for this data
    primary_kpi      VARCHAR,
    baseline_pct     NUMERIC,
    target_uplift_pts NUMERIC
);
-- A/A CHECK on past data: same dates as a 6-week test, no treatment applied. Both groups
-- should look alike: this proves the monitoring query works before the real test starts.
INSERT INTO clean.test_settings VALUES
 ('Senior 1-hour reply for P1 home movers (A/A check)', 'Home movers and downsizers',
  DATE '2026-08-03', DATE '2026-09-13', DATE '2026-09-30',
  'Viewing booked within 14 days of enquiry', 49.5, 9);

CREATE OR REPLACE VIEW clean.test_assignment AS
SELECT l.lead_id, l.customer_id, l.created_day,
       CASE WHEN abs(hashtext(l.lead_id)) % 2 = 0 THEN 'Test' ELSE 'Control' END AS test_group
FROM clean.clean_leads l
JOIN clean.dashboard_segments d USING (customer_id)
JOIN clean.test_settings s ON d.segment_name = s.target_segment
WHERE l.created_day BETWEEN s.start_date AND s.end_date;

-- The weekly monitoring query (Power BI loads this view for the test KPI card)
CREATE OR REPLACE VIEW clean.test_kpi_weekly AS
SELECT date_trunc('week', a.created_day)::date AS week_starting,
       a.test_group,
       count(*) AS leads,
       -- primary KPI: a viewing within 14 days, only for leads old enough to have had 14 days
       count(*) FILTER (WHERE a.created_day <= s.data_cutoff - 14) AS leads_with_14_days,
       count(*) FILTER (WHERE a.created_day <= s.data_cutoff - 14 AND EXISTS (
            SELECT 1 FROM clean.clean_site_visits v
            WHERE v.lead_id = a.lead_id AND v.visit_date <= a.created_day + 14)) AS viewing_within_14_days,
       -- guardrail / process KPI: first reply within 1 hour
       count(*) FILTER (WHERE l.first_response_min < 60) AS answered_within_1h,
       count(*) FILTER (WHERE l.first_response_min IS NOT NULL) AS leads_with_reply
FROM clean.test_assignment a
JOIN clean.clean_leads l USING (lead_id)
CROSS JOIN clean.test_settings s
GROUP BY 1, 2;

SELECT week_starting, test_group, leads,
       round(100.0 * viewing_within_14_days / nullif(leads_with_14_days, 0), 1) AS viewing_14d_pct,
       round(100.0 * answered_within_1h / nullif(leads_with_reply, 0), 1) AS within_1h_pct
FROM clean.test_kpi_weekly ORDER BY week_starting, test_group;

-- Running total: Test vs Control on the primary KPI, with the uplift and the target
CREATE OR REPLACE VIEW clean.test_kpi_summary AS
SELECT s.test_name, s.target_segment, s.primary_kpi, s.baseline_pct, s.target_uplift_pts,
       sum(k.leads) FILTER (WHERE k.test_group = 'Test')    AS test_leads,
       sum(k.leads) FILTER (WHERE k.test_group = 'Control') AS control_leads,
       round(100.0 * sum(k.viewing_within_14_days) FILTER (WHERE k.test_group = 'Test')
                   / nullif(sum(k.leads_with_14_days) FILTER (WHERE k.test_group = 'Test'), 0), 1)    AS test_kpi_pct,
       round(100.0 * sum(k.viewing_within_14_days) FILTER (WHERE k.test_group = 'Control')
                   / nullif(sum(k.leads_with_14_days) FILTER (WHERE k.test_group = 'Control'), 0), 1) AS control_kpi_pct
FROM clean.test_kpi_weekly k CROSS JOIN clean.test_settings s
GROUP BY s.test_name, s.target_segment, s.primary_kpi, s.baseline_pct, s.target_uplift_pts;

SELECT *, round(test_kpi_pct - control_kpi_pct, 1) AS uplift_pts,
       CASE WHEN test_kpi_pct - control_kpi_pct >= target_uplift_pts THEN 'Target reached' ELSE 'Below target' END AS status
FROM clean.test_kpi_summary;

-- AFTER SWITCHING TO seg-v1.0 the segment names change: point the test at the P1 segment you chose, e.g.
-- UPDATE clean.test_settings SET target_segment = (SELECT segment_name FROM clean.segment_tiers ORDER BY value_per_lead_index DESC LIMIT 1);
-- WHEN THE REAL TEST STARTS: set the real dates, then refresh Power BI every Monday.
-- UPDATE clean.test_settings SET test_name = 'Senior 1-hour reply for P1 home movers',
--        start_date = DATE '2026-11-16', end_date = DATE '2026-12-27', data_cutoff = current_date;

-- =====================================================================================
-- DAY 14 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · Which segment should the first campaign test target, and why?
-- A good first target: high value per lead (P1), a clear lever (slow replies), and enough
-- leads per week to read a result in 6 weeks.
WITH l AS (
    SELECT d.segment_name, l.lead_id, l.created_day, l.first_response_min,
           EXISTS (SELECT 1 FROM clean.clean_site_visits v WHERE v.lead_id = l.lead_id
                   AND v.visit_date <= l.created_day + 14) AS viewing_14d
    FROM clean.clean_leads l JOIN clean.dashboard_segments d USING (customer_id)
    WHERE l.created_day BETWEEN DATE '2025-10-01' AND DATE '2026-09-30'
)
SELECT l.segment_name, t.priority_tier, t.value_per_lead_index,
       count(*) AS leads_last_12m, round(count(*) / 52.0) AS leads_per_week,
       round(count(*) / 52.0 * 6 / 2) AS leads_per_group_in_6_weeks,
       round(100.0 * avg(CASE WHEN viewing_14d THEN 1 ELSE 0 END), 1) AS viewing_14d_baseline_pct,
       round(100.0 * avg(CASE WHEN first_response_min < 60 THEN 1 ELSE 0 END) FILTER (WHERE first_response_min IS NOT NULL), 1) AS within_1h_pct,
       -- smallest uplift (points) a 6-week test can detect: 80% power, 5% significance
       round(2.8 * 100 * sqrt(2 * avg(CASE WHEN viewing_14d THEN 1.0 ELSE 0 END) * (1 - avg(CASE WHEN viewing_14d THEN 1.0 ELSE 0 END))
             / (count(*) / 52.0 * 6 / 2)), 1) AS min_detectable_uplift_pts
FROM l JOIN clean.segment_tiers t USING (segment_name)
GROUP BY l.segment_name, t.priority_tier, t.value_per_lead_index
ORDER BY t.value_per_lead_index DESC;

-- Q2 · Which KPI will show the test worked, and what change would count as a win?
--      Primary: viewing booked within 14 days (measurable inside 6 weeks; conversion takes ~49 days).
--      Win: Test beats Control by at least the minimum detectable uplift above (about 9 points for
--      home movers). Guardrail: answered within 1 hour must rise in Test, or the treatment did not happen.
SELECT * FROM clean.test_kpi_summary;

-- Q3 · How many consenting customers can each channel reach per segment?
SELECT segment_name,
       (SELECT count(*) FROM clean.crm_export x WHERE x.segment_name = e.segment_name) AS customers,
       count(*) AS consenting_email_reach,
       count(*) AS consenting_google_reach,
       (SELECT count(*) FROM clean.audience_meta m WHERE m.segment_name = e.segment_name) AS consenting_meta_reach,
       (SELECT count(phone) FROM clean.audience_meta m WHERE m.segment_name = e.segment_name) AS meta_with_phone,
       round(100.0 * count(*) / (SELECT count(*) FROM clean.crm_export x WHERE x.segment_name = e.segment_name), 1) AS pct_consenting
FROM clean.audience_email e GROUP BY segment_name ORDER BY 2 DESC;

-- OWN QUESTION A · How many P1 customers can we NOT reach by marketing (no consent)?
SELECT e.priority_tier, count(*) AS customers,
       count(*) FILTER (WHERE NOT c.consent_marketing) AS no_consent,
       round(100.0 * count(*) FILTER (WHERE NOT c.consent_marketing) / count(*), 1) AS pct_no_consent
FROM clean.crm_export e JOIN clean.clean_customers c USING (customer_id)
GROUP BY 1 ORDER BY 1;

-- OWN QUESTION B · Is next month's spend aimed at the most valuable segments?
SELECT p.target_segment, t.priority_tier, round(sum(p.planned_spend_gbp)::numeric, 0) AS planned_spend_gbp,
       round((100.0 * sum(p.planned_spend_gbp) / sum(sum(p.planned_spend_gbp)) OVER ())::numeric, 1) AS pct_of_spend
FROM clean.campaign_plan p LEFT JOIN clean.segment_tiers t ON t.segment_name = p.target_segment
GROUP BY 1, 2 ORDER BY 3 DESC;
