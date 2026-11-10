-- =====================================================================================
-- DAY 6 · Feature views from event data (web sessions and property views)
-- Needs: Week 1 Day 4 (clean.clean_customers, clean.clean_web_sessions).
-- Run in pgAdmin: Query Tool on veltrix. Run ONE STEP AT A TIME (highlight, F5).
--
-- Everything goes in a new schema "feat" (features). These are VIEWS: they store the
-- SQL, not the data, so they always reflect the clean tables. One row per customer who
-- has at least one known (logged-in) web session.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS feat;

-- =====================================================================================
-- STEP 1 · Session summary per customer: how much, when and on what device they browse
-- =====================================================================================
CREATE OR REPLACE VIEW feat.customer_session_summary AS
SELECT customer_id,
       count(*)                                                        AS n_sessions,
       min(session_day)                                                AS first_session_day,
       max(session_day)                                                AS last_session_day,
       count(DISTINCT session_day)                                     AS active_days,
       round(avg(pages_viewed), 1)                                     AS avg_pages_per_session,
       round(avg(duration_sec) / 60.0, 1)                              AS avg_session_minutes,
       sum(is_night_session)                                           AS night_sessions,         -- 00:00-05:59 UK time
       round(100.0 * avg(is_night_session), 1)                         AS pct_night_sessions,
       count(*) FILTER (WHERE EXTRACT(ISODOW FROM session_start) >= 6) AS weekend_sessions,
       count(*) FILTER (WHERE device = 'Mobile')                       AS mobile_sessions,
       count(*) FILTER (WHERE device = 'Desktop')                      AS desktop_sessions,
       count(*) FILTER (WHERE device = 'Tablet')                       AS tablet_sessions,
       mode() WITHIN GROUP (ORDER BY device)                           AS main_device,
       mode() WITHIN GROUP (ORDER BY traffic_source)                   AS main_traffic_source,
       count(*) FILTER (WHERE ip_country <> 'GB')                      AS non_uk_ip_sessions
FROM clean.clean_web_sessions
WHERE customer_id IS NOT NULL                -- anonymous sessions cannot be tied to a customer
GROUP BY customer_id;

-- Check: about 95,577 customers with at least one known session
SELECT count(*) AS customers_with_sessions, sum(n_sessions) AS known_sessions,
       round(avg(n_sessions), 1) AS avg_sessions_per_customer
FROM feat.customer_session_summary;

-- =====================================================================================
-- STEP 2 · Property-view summary per customer: what they look at
-- Joins every property event (15M rows) to its session, customer and listing: ~30-60 s.
-- =====================================================================================
CREATE OR REPLACE VIEW feat.customer_property_view_summary AS
SELECT w.customer_id,
       count(*)                                                         AS n_property_events,
       count(DISTINCT v.property_id)                                    AS n_distinct_properties,
       count(*) FILTER (WHERE v.event_type = 'View')                    AS n_views,
       count(*) FILTER (WHERE v.event_type = 'Save')                    AS n_saves,
       count(*) FILTER (WHERE v.event_type = 'Virtual tour')            AS n_virtual_tours,
       count(*) FILTER (WHERE v.event_type = 'Share')                   AS n_shares,
       count(*) FILTER (WHERE v.event_type = 'Floorplan download')      AS n_floorplans,
       count(*) FILTER (WHERE p.listing_purpose = 'Sale')               AS n_sale_listing_events,
       count(*) FILTER (WHERE p.listing_purpose = 'Rent')               AS n_rent_listing_events,
       count(*) FILTER (WHERE p.new_build)                              AS n_new_build_events,
       count(*) FILTER (WHERE p.development_status = 'Off-plan')        AS n_off_plan_events,
       count(*) FILTER (WHERE lo.region = 'London')                     AS n_london_events,
       count(DISTINCT lo.region)                                        AS n_regions_viewed,
       mode() WITHIN GROUP (ORDER BY lo.region)                         AS top_region_viewed,
       round(avg(p.bedrooms), 1)                                        AS avg_bedrooms_viewed
FROM clean.clean_property_views v
JOIN clean.clean_web_sessions w USING (session_id)
JOIN clean.clean_properties p   USING (property_id)
JOIN clean.clean_locations lo   USING (location_id)
WHERE w.customer_id IS NOT NULL
GROUP BY w.customer_id;

-- =====================================================================================
-- STEP 3 · Median asking price and rent viewed per customer (for budget imputation)
-- A TABLE (not a view) because the medians over 15M rows take ~1 minute; DS reads it often.
-- Uses the clean (merged) customer_id, so a merged customer's history counts once.
-- =====================================================================================
DROP TABLE IF EXISTS feat.customer_viewed_prices CASCADE;
CREATE TABLE feat.customer_viewed_prices AS
SELECT w.customer_id,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY p.asking_price_gbp) AS median_viewed_price_gbp,
       count(p.asking_price_gbp)                                       AS n_sale_price_views,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY p.rent_pcm_gbp)     AS median_viewed_rent_pcm_gbp,
       count(p.rent_pcm_gbp)                                           AS n_rent_price_views
FROM clean.clean_web_sessions w
JOIN clean.clean_property_views v USING (session_id)
JOIN clean.clean_properties p     USING (property_id)
WHERE w.customer_id IS NOT NULL
GROUP BY w.customer_id;
ALTER TABLE feat.customer_viewed_prices ADD PRIMARY KEY (customer_id);

-- How useful is it for imputation? Buyers / renters with NO stated budget but 3+ priced views
SELECT c.primary_intent,
       count(*) FILTER (WHERE (c.primary_intent = 'Buy'  AND c.stated_budget_gbp IS NULL)
                           OR (c.primary_intent = 'Rent' AND c.stated_rent_budget_pcm_gbp IS NULL)) AS no_budget,
       count(*) FILTER (WHERE (c.primary_intent = 'Buy'  AND c.stated_budget_gbp IS NULL AND v.n_sale_price_views >= 3)
                           OR (c.primary_intent = 'Rent' AND c.stated_rent_budget_pcm_gbp IS NULL AND v.n_rent_price_views >= 3)) AS no_budget_but_imputable
FROM clean.clean_customers c LEFT JOIN feat.customer_viewed_prices v USING (customer_id)
GROUP BY 1;

-- =====================================================================================
-- STEP 4 · Region views per customer ("Where they look"): one row per customer x region
-- Power BI uses it for the top-5 regions chart; it filters by customer type through
-- the relationship to clean_customers.
-- =====================================================================================
CREATE OR REPLACE VIEW feat.customer_region_views AS
SELECT w.customer_id, lo.region, count(*) AS property_events
FROM clean.clean_property_views v
JOIN clean.clean_web_sessions w USING (session_id)
JOIN clean.clean_properties p   USING (property_id)
JOIN clean.clean_locations lo   USING (location_id)
WHERE w.customer_id IS NOT NULL
GROUP BY 1, 2;

-- Regions where deals close (to compare with where people look)
CREATE OR REPLACE VIEW feat.region_deals AS
SELECT lo.region, t.deal_kind, count(*) AS deals, sum(t.deal_value_gbp) AS deal_value_gbp
FROM clean.clean_transactions t
JOIN clean.clean_properties p USING (property_id)
JOIN clean.clean_locations lo USING (location_id)
GROUP BY 1, 2;

-- =====================================================================================
-- STEP 4b · A short "customer group" label for the device-mix chart (intent x residence)
-- =====================================================================================
ALTER TABLE clean.clean_customers ADD COLUMN IF NOT EXISTS customer_group VARCHAR;
UPDATE clean.clean_customers
SET customer_group = CASE primary_intent WHEN 'Buy' THEN 'Buyers' ELSE 'Renters' END
                     || CASE WHEN is_overseas THEN ' - overseas' ELSE ' - UK' END;
SELECT customer_group, count(*) FROM clean.clean_customers GROUP BY 1 ORDER BY 1;

-- =====================================================================================
-- STEP 5 · Check the views (screenshot for the Day 6 output)
-- =====================================================================================
SELECT 'customer_session_summary' AS view_name, count(*) AS customers FROM feat.customer_session_summary
UNION ALL SELECT 'customer_property_view_summary', count(*) FROM feat.customer_property_view_summary
UNION ALL SELECT 'customer_viewed_prices', count(*) FROM feat.customer_viewed_prices;

SELECT * FROM feat.customer_session_summary s
JOIN feat.customer_property_view_summary pv USING (customer_id)
JOIN feat.customer_viewed_prices pr USING (customer_id)
LIMIT 10;

-- =====================================================================================
-- STEP 6 · Compatibility view for the DS model: the column names the model code expects
-- The Phase 3 code reads budget_gbp, sessions_total, enquiries_total, preferred_region ...
-- This MATERIALIZED view (stored like a table, so it reads in a second) gives one row per
-- customer with exactly those names, plus a few extra signals and the inputs for budget
-- imputation. OUTCOMES (converted, deal value, late payment) are deliberately NOT here.
-- Takes 1-3 minutes (two passes over the 15M property events).
-- Refresh after the clean tables change:  REFRESH MATERIALIZED VIEW feat.customer_features_ds;
-- Export for DuckDB / pandas: notebooks/04_feature_engineering.ipynb writes it to Parquet.
-- =====================================================================================
-- 6a. Preferred property type: the type each customer looks at most
DROP MATERIALIZED VIEW IF EXISTS feat.customer_features_ds;
DROP MATERIALIZED VIEW IF EXISTS feat.customer_property_type_pref;
CREATE MATERIALIZED VIEW feat.customer_property_type_pref AS
SELECT w.customer_id, mode() WITHIN GROUP (ORDER BY p.property_type) AS preferred_property_type
FROM clean.clean_property_views v
JOIN clean.clean_web_sessions w USING (session_id)
JOIN clean.clean_properties p   USING (property_id)
WHERE w.customer_id IS NOT NULL
GROUP BY w.customer_id;
CREATE UNIQUE INDEX ON feat.customer_property_type_pref (customer_id);

-- 6b. The model input table (plan names first, then extra signals)
CREATE MATERIALIZED VIEW feat.customer_features_ds AS
WITH leads AS (
    SELECT customer_id, count(*) AS enquiries_total, max(created_day) AS last_lead_day,
           mode() WITHIN GROUP (ORDER BY lead_source) AS lead_source_primary,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_min) AS median_first_reply_min
    FROM clean.clean_leads GROUP BY customer_id
),
contacts AS (
    SELECT l.customer_id, max(i.interaction_time)::date AS last_contact_day,
           count(*) FILTER (WHERE i.direction = 'Inbound') AS inbound_contacts
    FROM clean.clean_interactions i JOIN clean.clean_leads l USING (lead_id)
    GROUP BY l.customer_id
)
SELECT c.customer_id,
       -- numeric features named as in the model code
       c.stated_budget_gbp::double precision                    AS budget_gbp,            -- typos fixed; blanks imputed in notebook 04
       c.stated_rent_budget_pcm_gbp::double precision           AS rent_budget_pcm_gbp,
       coalesce(s.n_sessions, 0)                                AS sessions_total,
       coalesce(s.pct_night_sessions, 0) / 100.0                AS night_session_share,   -- 0-1, sessions 00:00-05:59 UK
       coalesce(pv.n_distinct_properties, 0)                    AS properties_viewed,
       coalesce(pv.n_virtual_tours::numeric / nullif(pv.n_property_events, 0), 0) AS virtual_tour_share,
       coalesce(l.enquiries_total, 0)                           AS enquiries_total,
       DATE '2026-09-30' - greatest(s.last_session_day, l.last_lead_day, ct.last_contact_day, c.first_contact_date) AS days_since_last_activity,
       -- categorical features named as in the model code
       coalesce(pv.top_region_viewed, c.uk_region_of_residence, 'Unknown') AS preferred_region,
       coalesce(pt.preferred_property_type, 'Unknown')          AS preferred_property_type,
       coalesce(l.lead_source_primary, 'No lead')               AS lead_source_primary,
       coalesce(c.finance_type, 'Unknown')                      AS finance_type,
       c.customer_type,
       c.is_overseas,
       -- extra signals (optional model inputs, also used for profiling)
       c.primary_intent, coalesce(c.age_band, 'Unknown') AS age_band, c.buyer_position,
       coalesce(s.mobile_sessions::numeric / nullif(s.n_sessions, 0), 0)          AS mobile_share,
       coalesce(pv.n_new_build_events::numeric / nullif(pv.n_property_events, 0), 0) AS new_build_share,
       coalesce(pv.n_off_plan_events::numeric / nullif(pv.n_property_events, 0), 0)  AS off_plan_share,
       coalesce(pv.n_london_events::numeric / nullif(pv.n_property_events, 0), 0)    AS london_share,
       coalesce(pv.n_saves, 0)                                  AS saves_total,
       coalesce(pv.n_property_events, 0)                        AS property_events_total,
       coalesce(ct.inbound_contacts, 0)                         AS inbound_contacts_total,
       l.median_first_reply_min                                 AS median_agent_response_min,
       -- inputs for imputing budgets from what the customer looked at
       pr.median_viewed_price_gbp, pr.n_sale_price_views, pr.median_viewed_rent_pcm_gbp, pr.n_rent_price_views
FROM clean.clean_customers c
LEFT JOIN feat.customer_session_summary s        USING (customer_id)
LEFT JOIN feat.customer_property_view_summary pv USING (customer_id)
LEFT JOIN feat.customer_viewed_prices pr         USING (customer_id)
LEFT JOIN feat.customer_property_type_pref pt    USING (customer_id)
LEFT JOIN leads l                                USING (customer_id)
LEFT JOIN contacts ct                            USING (customer_id);
CREATE UNIQUE INDEX ON feat.customer_features_ds (customer_id);

-- Check: one row per customer (100,573), and how many have each feature
SELECT count(*) AS customers,
       count(budget_gbp) AS with_budget, count(rent_budget_pcm_gbp) AS with_rent_budget,
       count(*) FILTER (WHERE sessions_total > 0) AS with_sessions,
       count(*) FILTER (WHERE enquiries_total > 0) AS with_a_lead,
       count(*) FILTER (WHERE lead_source_primary = 'No lead') AS browsers_without_lead,
       round(avg(days_since_last_activity)) AS avg_days_since_last_activity
FROM feat.customer_features_ds;
SELECT * FROM feat.customer_features_ds LIMIT 10;

-- =====================================================================================
-- DAY 6 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · What share of browsing happens between midnight and 6am UK time, and who is doing it?
SELECT CASE WHEN w.customer_id IS NULL THEN 'Anonymous'
            WHEN c.is_overseas THEN 'Overseas customers' ELSE 'UK customers' END AS who,
       count(*) AS sessions,
       sum(w.is_night_session) AS night_sessions,
       round(100.0 * avg(w.is_night_session), 1) AS pct_night,
       round(100.0 * sum(w.is_night_session) / sum(sum(w.is_night_session)) OVER (), 1) AS pct_of_all_night_sessions
FROM clean.clean_web_sessions w LEFT JOIN clean.clean_customers c USING (customer_id)
GROUP BY 1
UNION ALL
SELECT 'All sessions', count(*), sum(is_night_session), round(100.0 * avg(is_night_session), 1), 100
FROM clean.clean_web_sessions
ORDER BY 2 DESC;

-- Which countries browse at night most?
SELECT c.country_of_residence, sum(s.n_sessions) AS sessions,
       round(100.0 * sum(s.night_sessions) / sum(s.n_sessions), 1) AS pct_night
FROM feat.customer_session_summary s JOIN clean.clean_customers c USING (customer_id)
GROUP BY 1 ORDER BY 3 DESC;

-- Q2 · Do the regions customers look at match the regions where deals close?
WITH looked AS (SELECT region, sum(property_events) AS events FROM feat.customer_region_views GROUP BY 1),
     closed AS (SELECT region, sum(deals) AS deals, sum(deal_value_gbp) AS value FROM feat.region_deals GROUP BY 1)
SELECT region,
       round(100.0 * events / sum(events) OVER (), 1) AS pct_of_views,
       round(100.0 * deals  / sum(deals)  OVER (), 1) AS pct_of_deals,
       round((100.0 * value / sum(value) OVER ())::numeric, 1) AS pct_of_deal_value,
       round(100.0 * deals / sum(deals) OVER (), 1) - round(100.0 * events / sum(events) OVER (), 1) AS deals_minus_views_pts
FROM looked JOIN closed USING (region)
ORDER BY pct_of_views DESC;

-- Q3 · How heavily are virtual tours used, and by whom?
SELECT CASE WHEN c.is_overseas THEN 'Overseas' ELSE 'UK' END AS residence, c.primary_intent,
       count(*) AS customers,
       sum(p.n_property_events) AS property_events,
       round(100.0 * sum(p.n_virtual_tours) / sum(p.n_property_events), 2) AS pct_events_virtual_tour,
       round(100.0 * avg(CASE WHEN p.n_virtual_tours > 0 THEN 1 ELSE 0 END), 1) AS pct_customers_ever_used
FROM feat.customer_property_view_summary p JOIN clean.clean_customers c USING (customer_id)
GROUP BY 1, 2 ORDER BY 5 DESC;

-- OWN QUESTION A · Do customers who browse more convert more? (sessions in quartiles)
WITH q AS (SELECT customer_id, n_sessions, ntile(4) OVER (ORDER BY n_sessions) AS browsing_quartile
           FROM feat.customer_session_summary)
SELECT q.browsing_quartile, min(q.n_sessions) AS min_sessions, max(q.n_sessions) AS max_sessions,
       count(*) AS closed_leads,
       round(100.0 * avg(CASE WHEN l.converted THEN 1 ELSE 0 END), 1) AS conversion_pct
FROM q JOIN clean.clean_leads l USING (customer_id)
WHERE l.is_closed = 1
GROUP BY 1 ORDER BY 1;

-- OWN QUESTION B · Which device does each group use most? (feeds the 100% stacked bar)
SELECT c.primary_intent || CASE WHEN c.is_overseas THEN ' - overseas' ELSE ' - UK' END AS customer_group,
       round(100.0 * sum(s.mobile_sessions)  / sum(s.n_sessions), 1) AS pct_mobile,
       round(100.0 * sum(s.desktop_sessions) / sum(s.n_sessions), 1) AS pct_desktop,
       round(100.0 * sum(s.tablet_sessions)  / sum(s.n_sessions), 1) AS pct_tablet
FROM feat.customer_session_summary s JOIN clean.clean_customers c USING (customer_id)
GROUP BY 1 ORDER BY 1;

-- Behaviour card values (Segment deep dive), all customers: check your Power BI cards against these
SELECT round(100.0 * (SELECT sum(night_sessions) FROM feat.customer_session_summary)
                   / (SELECT sum(n_sessions) FROM feat.customer_session_summary), 1)               AS pct_sessions_00_06,
       round(100.0 * sum(n_virtual_tours) / sum(n_property_events), 1)                             AS pct_events_virtual_tour,
       round(100.0 * sum(n_new_build_events) / sum(n_property_events), 1)                          AS pct_events_new_build,
       (SELECT round(100.0 * avg(CASE WHEN is_overseas THEN 1 ELSE 0 END), 1) FROM clean.clean_customers) AS pct_customers_overseas
FROM feat.customer_property_view_summary;
