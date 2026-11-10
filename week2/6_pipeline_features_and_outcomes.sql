-- =====================================================================================
-- DAY 7 · Pipeline features, the customer_features table and the outcome table
-- Needs: Day 6 (schema feat and its views).
-- Run in pgAdmin: Query Tool on veltrix. Run ONE STEP AT A TIME (highlight, F5).
--
-- Two separate tables, on purpose:
--   feat.customer_features  = what we know ABOUT a customer (profile, browsing, enquiry
--                             behaviour). DS clusters on these.
--   feat.customer_outcomes  = what HAPPENED (won, days to decision, payments on time).
--                             Never fed into the clustering; used afterwards to test
--                             whether the segments differ (Day 10) and on the dashboard.
-- Keeping outcomes out of the features is how we avoid leakage.
-- =====================================================================================

-- =====================================================================================
-- STEP 1 · Pipeline features per customer (enquiries, reply speed, contacts, viewings)
-- Only events up to each lead's decision date count (none fall after it in this data,
-- but the rule protects future monthly refreshes).
-- =====================================================================================
CREATE OR REPLACE VIEW feat.customer_pipeline_features AS
WITH lead_level AS (
    SELECT l.customer_id, l.lead_id, l.intent, l.lead_source, l.channel_group, l.campaign_id,
           l.created_day, l.first_response_min
    FROM clean.clean_leads l
),
contacts AS (
    SELECT l.customer_id,
           count(*) FILTER (WHERE i.direction = 'Inbound')  AS n_inbound_contacts,
           count(*) FILTER (WHERE i.direction = 'Outbound') AS n_outbound_contacts,
           count(DISTINCT i.channel)                        AS n_contact_channels
    FROM clean.clean_interactions i
    JOIN clean.clean_leads l USING (lead_id)
    WHERE l.closed_date IS NULL OR i.interaction_time::date <= l.closed_date
    GROUP BY 1
),
viewings AS (
    SELECT l.customer_id,
           count(*)                                               AS n_viewings,
           count(*) FILTER (WHERE v.visit_type = 'Virtual')       AS n_virtual_viewings,
           count(DISTINCT v.property_id)                          AS n_properties_viewed_in_person_or_virtual
    FROM clean.clean_site_visits v
    JOIN clean.clean_leads l USING (lead_id)
    WHERE l.closed_date IS NULL OR v.visit_date <= l.closed_date
    GROUP BY 1
),
campaigns AS (
    SELECT customer_id,
           count(*)                                                AS n_campaign_responses,
           count(*) FILTER (WHERE response_type IN ('Click', 'Form submit')) AS n_campaign_clicks_or_forms,
           count(*) FILTER (WHERE response_type IN ('Hide ad', 'Unsubscribe')) AS n_campaign_rejections
    FROM clean.clean_campaign_responses
    GROUP BY 1
)
SELECT c.customer_id,
       coalesce(ll.n_leads, 0)                      AS n_leads,                 -- total enquiries
       coalesce(ll.n_buy_leads, 0)                  AS n_buy_leads,
       coalesce(ll.n_rent_leads, 0)                 AS n_rent_leads,
       ll.first_lead_day,
       ll.n_channels_used,
       ll.main_channel,
       ll.main_channel_group,
       coalesce(ll.n_campaign_leads, 0)             AS n_campaign_leads,
       ll.median_first_response_min,
       ll.pct_leads_answered_within_1h,
       coalesce(ct.n_inbound_contacts, 0)           AS n_inbound_contacts,
       coalesce(ct.n_outbound_contacts, 0)          AS n_outbound_contacts,
       coalesce(vw.n_viewings, 0)                   AS n_viewings,
       coalesce(vw.n_virtual_viewings, 0)           AS n_virtual_viewings,
       coalesce(cp.n_campaign_responses, 0)         AS n_campaign_responses,
       coalesce(cp.n_campaign_clicks_or_forms, 0)   AS n_campaign_clicks_or_forms,
       coalesce(cp.n_campaign_rejections, 0)        AS n_campaign_rejections
FROM clean.clean_customers c
LEFT JOIN (
    SELECT customer_id,
           count(*)                                        AS n_leads,
           count(*) FILTER (WHERE intent = 'Buy')          AS n_buy_leads,
           count(*) FILTER (WHERE intent = 'Rent')         AS n_rent_leads,
           min(created_day)                                AS first_lead_day,
           count(DISTINCT lead_source)                     AS n_channels_used,
           mode() WITHIN GROUP (ORDER BY lead_source)      AS main_channel,
           mode() WITHIN GROUP (ORDER BY channel_group)    AS main_channel_group,
           count(campaign_id)                              AS n_campaign_leads,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_min) AS median_first_response_min,
           round(100.0 * avg(CASE WHEN first_response_min < 60 THEN 1.0 ELSE 0 END)
                 FILTER (WHERE first_response_min IS NOT NULL), 1)          AS pct_leads_answered_within_1h
    FROM lead_level GROUP BY customer_id
) ll USING (customer_id)
LEFT JOIN contacts  ct USING (customer_id)
LEFT JOIN viewings  vw USING (customer_id)
LEFT JOIN campaigns cp USING (customer_id);

-- =====================================================================================
-- STEP 2 · customer_features: ONE row per customer (100,573) for the DS team
-- Profile + browsing (Day 6) + viewed prices (Day 6) + pipeline (step 1).
-- A TABLE so DS and Power BI read it in seconds. Re-run this step after any refresh.
-- =====================================================================================
DROP TABLE IF EXISTS feat.customer_features CASCADE;   -- CASCADE: also drops Day 9-10 views; re-run Days 9-10 after
CREATE TABLE feat.customer_features AS
SELECT c.customer_id,
       -- profile
       c.customer_type, c.primary_intent, c.buyer_position, c.finance_type, c.age_band, c.occupation_sector,
       c.country_of_residence, c.country_iso2, c.is_overseas, c.uk_region_of_residence,
       c.stated_budget_gbp, c.stated_rent_budget_pcm_gbp, c.budget_fixed, c.preferred_currency,
       c.first_contact_date, c.consent_marketing, c.was_merged,
       -- browsing (NULL = no known session)
       s.n_sessions, s.active_days, s.avg_pages_per_session, s.avg_session_minutes,
       s.pct_night_sessions, s.weekend_sessions, s.mobile_sessions, s.desktop_sessions, s.tablet_sessions,
       s.main_device, s.main_traffic_source, s.non_uk_ip_sessions,
       pv.n_property_events, pv.n_distinct_properties, pv.n_saves, pv.n_virtual_tours, pv.n_shares,
       pv.n_floorplans, pv.n_sale_listing_events, pv.n_rent_listing_events, pv.n_new_build_events,
       pv.n_off_plan_events, pv.n_london_events, pv.n_regions_viewed, pv.top_region_viewed,
       pv.avg_bedrooms_viewed,
       round(100.0 * pv.n_virtual_tours / nullif(pv.n_property_events, 0), 1)   AS pct_events_virtual_tour,
       round(100.0 * pv.n_new_build_events / nullif(pv.n_property_events, 0), 1) AS pct_events_new_build,
       -- prices viewed (for budget imputation)
       vp.median_viewed_price_gbp, vp.n_sale_price_views, vp.median_viewed_rent_pcm_gbp, vp.n_rent_price_views,
       -- pipeline
       pf.n_leads, pf.n_buy_leads, pf.n_rent_leads, pf.first_lead_day, pf.n_channels_used, pf.main_channel,
       pf.main_channel_group, pf.n_campaign_leads, pf.median_first_response_min, pf.pct_leads_answered_within_1h,
       pf.n_inbound_contacts, pf.n_outbound_contacts, pf.n_viewings, pf.n_virtual_viewings,
       pf.n_campaign_responses, pf.n_campaign_clicks_or_forms, pf.n_campaign_rejections
FROM clean.clean_customers c
LEFT JOIN feat.customer_session_summary       s  USING (customer_id)
LEFT JOIN feat.customer_property_view_summary pv USING (customer_id)
LEFT JOIN feat.customer_viewed_prices         vp USING (customer_id)
LEFT JOIN feat.customer_pipeline_features     pf USING (customer_id);
ALTER TABLE feat.customer_features ADD PRIMARY KEY (customer_id);

-- Check: 100,573 rows, one per customer; how complete are the feature groups?
SELECT count(*) AS customers,
       count(n_sessions)            AS with_browsing,
       count(median_viewed_price_gbp) AS with_viewed_price,
       count(*) FILTER (WHERE n_leads > 0) AS with_leads,
       count(median_first_response_min) AS with_reply_time
FROM feat.customer_features;

-- =====================================================================================
-- STEP 3 · The outcome table: ONE row per customer, separate from the features
-- Data window ends 30 Sep 2026. Payments not yet due ("Scheduled") are left out.
-- =====================================================================================
DROP TABLE IF EXISTS feat.customer_outcomes CASCADE;
CREATE TABLE feat.customer_outcomes AS
WITH lo AS (
    SELECT customer_id,
           count(*) FILTER (WHERE is_closed = 1)                              AS n_closed_leads,
           count(*) FILTER (WHERE converted)                                  AS n_won_leads,
           count(*) FILTER (WHERE is_open = 1)                                AS n_open_leads,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY closed_date - created_day)
                 FILTER (WHERE is_closed = 1)                                 AS median_days_to_decision,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY closed_date - created_day)
                 FILTER (WHERE converted)                                     AS median_days_to_win
    FROM clean.clean_leads GROUP BY 1
),
deals AS (
    SELECT customer_id, count(*) AS n_deals,
           count(*) FILTER (WHERE deal_kind = 'Sale')    AS n_sale_deals,
           count(*) FILTER (WHERE deal_kind = 'Letting') AS n_letting_deals,
           sum(deal_value_gbp)                           AS deal_value_gbp
    FROM clean.clean_transactions GROUP BY 1
),
pay AS (
    SELECT t.customer_id,
           count(*) FILTER (WHERE p.status <> 'Scheduled')                    AS payments_due,
           count(*) FILTER (WHERE p.status = 'Paid')                          AS payments_on_time,
           count(*) FILTER (WHERE p.status IN ('Paid late', 'Overdue'))       AS payments_late_or_overdue,
           sum(p.amount_gbp) FILTER (WHERE p.status = 'Overdue')              AS overdue_now_gbp
    FROM clean.clean_payments p JOIN clean.clean_transactions t USING (transaction_id)
    GROUP BY 1
)
SELECT c.customer_id,
       coalesce(lo.n_closed_leads, 0) AS n_closed_leads,
       coalesce(lo.n_won_leads, 0)    AS n_won_leads,
       coalesce(lo.n_open_leads, 0)   AS n_open_leads,
       CASE WHEN coalesce(lo.n_closed_leads, 0) = 0 THEN NULL
            WHEN lo.n_won_leads > 0 THEN 1 ELSE 0 END                         AS converted,          -- NULL = no decision yet
       round(lo.n_won_leads::numeric / nullif(lo.n_closed_leads, 0), 4)       AS conversion_rate,
       lo.median_days_to_decision,
       lo.median_days_to_win,
       coalesce(d.n_deals, 0)         AS n_deals,
       coalesce(d.n_sale_deals, 0)    AS n_sale_deals,
       coalesce(d.n_letting_deals, 0) AS n_letting_deals,
       coalesce(d.deal_value_gbp, 0)  AS deal_value_gbp,                      -- revenue proxy
       coalesce(p.payments_due, 0)    AS payments_due,
       coalesce(p.payments_on_time, 0) AS payments_on_time,
       coalesce(p.payments_late_or_overdue, 0) AS payments_late_or_overdue,
       round(p.payments_on_time::numeric / nullif(p.payments_due, 0), 4)      AS ontime_payment_rate, -- NULL = no payments due
       coalesce(p.overdue_now_gbp, 0) AS overdue_now_gbp
FROM clean.clean_customers c
LEFT JOIN lo    USING (customer_id)
LEFT JOIN deals d USING (customer_id)
LEFT JOIN pay   p USING (customer_id);
ALTER TABLE feat.customer_outcomes ADD PRIMARY KEY (customer_id);

-- Check: 100,573 rows; totals must equal the clean tables
SELECT count(*) AS customers, sum(n_won_leads) AS won_leads, sum(n_deals) AS deals,
       round((sum(deal_value_gbp) / 1e6)::numeric, 1) AS deal_value_m,
       sum(payments_due) AS payments_due, round(sum(overdue_now_gbp)::numeric, 0) AS overdue_now_gbp,
       count(converted) AS customers_with_a_decision,
       round(100.0 * avg(converted), 1) AS pct_customers_converted
FROM feat.customer_outcomes;

-- =====================================================================================
-- STEP 4 · Leakage check: no feature may be (or be computed from) an outcome
-- Every query below should return 0.
-- =====================================================================================
SELECT 'interactions after the lead was decided' AS check_name, count(*) AS rows
FROM clean.clean_interactions i JOIN clean.clean_leads l USING (lead_id)
WHERE l.closed_date IS NOT NULL AND i.interaction_time::date > l.closed_date
UNION ALL
SELECT 'viewings after the lead was decided', count(*)
FROM clean.clean_site_visits v JOIN clean.clean_leads l USING (lead_id)
WHERE l.closed_date IS NOT NULL AND v.visit_date > l.closed_date
UNION ALL
SELECT 'outcome columns inside customer_features', count(*)
FROM information_schema.columns
WHERE table_schema = 'feat' AND table_name = 'customer_features'
  AND column_name IN ('converted', 'lead_stage', 'lost_reason', 'closed_date', 'n_won_leads', 'n_deals',
                      'deal_value_gbp', 'ontime_payment_rate', 'payments_due', 'overdue_now_gbp');

-- =====================================================================================
-- STEP 5 · Helpers for the Day 7 visuals
-- =====================================================================================
-- 5a. Stage order, so Power BI can sort the pipeline bar New -> Offer (Sort by column)
ALTER TABLE clean.clean_leads ADD COLUMN IF NOT EXISTS stage_order INT;
UPDATE clean.clean_leads SET stage_order =
       CASE lead_stage WHEN 'New' THEN 1 WHEN 'Contacted' THEN 2 WHEN 'Qualified' THEN 3
                       WHEN 'Viewing' THEN 4 WHEN 'Offer' THEN 5 WHEN 'Won' THEN 6 WHEN 'Lost' THEN 7 END;

-- 5b. Days open at 30 Sep 2026 for open leads (how long they have been sitting)
ALTER TABLE clean.clean_leads ADD COLUMN IF NOT EXISTS days_open_at_cutoff INT;
UPDATE clean.clean_leads SET days_open_at_cutoff = CASE WHEN is_open = 1 THEN DATE '2026-09-30' - created_day END;

-- 5c. The values the Day 7 KPI cards must show (all time, and last 12 months)
DROP TABLE IF EXISTS clean.powerbi_check_week2;
CREATE TABLE clean.powerbi_check_week2 AS
WITH w AS (SELECT DATE '2025-10-01' AS s, DATE '2026-09-30' AS e)
SELECT 1 AS check_order, 'Pipeline' AS page, 'Leads' AS measure,
       (SELECT count(*) FROM clean.clean_leads)::numeric AS all_time,
       (SELECT count(*) FROM clean.clean_leads, w WHERE created_day BETWEEN s AND e)::numeric AS last_12_months
UNION ALL SELECT 2, 'Pipeline', 'Won leads',
       (SELECT count(*) FROM clean.clean_leads WHERE converted),
       (SELECT count(*) FROM clean.clean_leads, w WHERE converted AND closed_date BETWEEN s AND e)
UNION ALL SELECT 3, 'Pipeline', 'Open pipeline', (SELECT count(*) FROM clean.clean_leads WHERE is_open = 1), NULL
UNION ALL SELECT 4, 'Pipeline', 'Answered within 1 hour %',
       (SELECT round(100.0 * avg(CASE WHEN first_response_min < 60 THEN 1 ELSE 0 END), 1) FROM clean.clean_leads WHERE first_response_min IS NOT NULL),
       (SELECT round(100.0 * avg(CASE WHEN first_response_min < 60 THEN 1 ELSE 0 END), 1) FROM clean.clean_leads, w WHERE first_response_min IS NOT NULL AND created_day BETWEEN s AND e)
UNION ALL SELECT 5, 'Payments', 'Payments due',
       (SELECT count(*) FROM clean.clean_payments WHERE status <> 'Scheduled'),
       (SELECT count(*) FROM clean.clean_payments, w WHERE status <> 'Scheduled' AND due_date BETWEEN s AND e)
UNION ALL SELECT 6, 'Payments', 'Paid late or overdue %',
       (SELECT round(100.0 * avg(is_late_or_overdue), 2) FROM clean.clean_payments WHERE status <> 'Scheduled'),
       (SELECT round(100.0 * avg(is_late_or_overdue), 2) FROM clean.clean_payments, w WHERE status <> 'Scheduled' AND due_date BETWEEN s AND e)
UNION ALL SELECT 7, 'Payments', 'Overdue now £',
       (SELECT round(sum(amount_gbp)::numeric, 0) FROM clean.clean_payments WHERE status = 'Overdue'), NULL
UNION ALL SELECT 8, 'Payments', 'Late rate on monthly rent %',
       (SELECT round(100.0 * avg(is_late_or_overdue), 2) FROM clean.clean_payments WHERE status <> 'Scheduled' AND payment_type = 'Monthly rent'),
       (SELECT round(100.0 * avg(is_late_or_overdue), 2) FROM clean.clean_payments, w WHERE status <> 'Scheduled' AND payment_type = 'Monthly rent' AND due_date BETWEEN s AND e);
SELECT * FROM clean.powerbi_check_week2 ORDER BY check_order;

-- =====================================================================================
-- DAY 7 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · Where in the pipeline are leads stalling, and how many are at viewing or offer stage today?
SELECT lead_stage, count(*) AS open_leads,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY days_open_at_cutoff) AS median_days_open,
       count(*) FILTER (WHERE days_open_at_cutoff > 90) AS open_over_90_days
FROM clean.clean_leads WHERE is_open = 1
GROUP BY lead_stage, stage_order ORDER BY stage_order;

-- Q2 · How much money is overdue right now, and when were those payments due?
SELECT to_char(date_trunc('month', due_date), 'Mon YYYY') AS month_due, payment_type,
       count(*) AS overdue_payments, round(sum(amount_gbp)::numeric, 0) AS overdue_gbp
FROM clean.clean_payments WHERE status = 'Overdue'
GROUP BY date_trunc('month', due_date), payment_type ORDER BY date_trunc('month', due_date), overdue_gbp DESC;

-- Q3 · Lettings are a large share of deals; what share of deal value do they bring?
SELECT deal_kind, count(*) AS deals, round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_of_deals,
       round((sum(deal_value_gbp) / 1e6)::numeric, 1) AS deal_value_m,
       round((100.0 * sum(deal_value_gbp) / sum(sum(deal_value_gbp)) OVER ())::numeric, 1) AS pct_of_value
FROM clean.clean_transactions GROUP BY 1;
-- by transaction type (feeds the deal value chart with deal counts)
SELECT transaction_type, count(*) AS deals, round((sum(deal_value_gbp) / 1e6)::numeric, 1) AS deal_value_m
FROM clean.clean_transactions GROUP BY 1 ORDER BY 3 DESC;

-- Q4 · Is late payment higher on monthly rent than on sale payments?
SELECT CASE WHEN payment_type = 'Monthly rent' THEN 'Monthly rent'
            WHEN payment_type IN ('Security deposit', 'Holding deposit') THEN 'Letting deposits'
            ELSE 'Sale payments' END AS payment_group,
       count(*) AS payments_due, sum(is_late_or_overdue) AS late_or_overdue,
       round(100.0 * avg(is_late_or_overdue), 2) AS late_pct,
       round(avg(days_late) FILTER (WHERE status = 'Paid late'), 1) AS avg_days_late
FROM clean.clean_payments WHERE status <> 'Scheduled'
GROUP BY 1 ORDER BY 4 DESC;

-- OWN QUESTION A · Do customers who make more than one enquiry convert more often?
SELECT CASE WHEN n_leads = 1 THEN '1 enquiry' WHEN n_leads = 2 THEN '2 enquiries' ELSE '3+ enquiries' END AS enquiries,
       count(*) AS customers_with_a_decision,
       round(100.0 * avg(o.converted), 1) AS pct_customers_converted
FROM feat.customer_features f JOIN feat.customer_outcomes o USING (customer_id)
WHERE o.converted IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- OWN QUESTION B · How many viewings does it take to win a deal?
SELECT l.intent, count(*) AS won_leads,
       round(avg(coalesce(v.n, 0)), 2) AS avg_viewings_per_won_lead,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY coalesce(v.n, 0)) AS median_viewings
FROM clean.clean_leads l
LEFT JOIN (SELECT lead_id, count(*) AS n FROM clean.clean_site_visits GROUP BY 1) v USING (lead_id)
WHERE l.converted
GROUP BY 1;
