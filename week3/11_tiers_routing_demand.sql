-- =====================================================================================
-- DAY 12 · Priority tiers, routing, recommended actions and the segment demand report
-- Needs: Day 11. Works on the segmentation in use (clean.segment_in_use).
-- Run in pgAdmin on veltrix, ONE STEP AT A TIME.
-- =====================================================================================

-- =====================================================================================
-- STEP 1 · Priority tiers (P1, P2, P3) per segment, from conversion AND revenue
-- Expected value of a lead = conversion x average deal value per won lead
--                          = deal value / closed leads.
-- Index it against all leads (100 = average lead), then:
--   P1  index >= 115   (worth more than the average lead: senior agents, reply within 1 hour)
--   P2  index 60-114   (standard handling, reply same day)
--   P3  index < 60     (low value per lead: automated nurture, self-serve, batch follow-up)
-- The thresholds are a proposal: agree them with the sales director before go-live.
-- =====================================================================================
DROP TABLE IF EXISTS clean.segment_tiers CASCADE;
CREATE TABLE clean.segment_tiers AS
WITH s AS (
    SELECT c.segment_name, c.customers, c.closed_leads, c.conversion_pct, c.deal_value_m,
           c.deal_value_m * 1e6 / nullif(c.closed_leads, 0) AS value_per_closed_lead
    FROM clean.segment_comparison c JOIN clean.segment_in_use u USING (model_version)
),
avg_lead AS (SELECT sum(deal_value_m) * 1e6 / sum(closed_leads) AS v FROM s),
desk AS (   -- the team that handles most of each segment's leads
    SELECT segment_name, team AS main_team, share
    FROM (SELECT d.segment_name, a.team, count(*) * 1.0 / sum(count(*)) OVER (PARTITION BY d.segment_name) AS share,
                 row_number() OVER (PARTITION BY d.segment_name ORDER BY count(*) DESC) AS rn
          FROM clean.dashboard_segments d JOIN clean.clean_leads l USING (customer_id)
          JOIN clean.clean_agents a USING (agent_id) GROUP BY 1, 2) x
    WHERE rn = 1
),
first_contact AS (   -- channel of the agent's first outbound contact, and how it converts, per segment
    SELECT segment_name, channel, conv
    FROM (SELECT d.segment_name, fo.channel, count(*) AS n,
                 avg(CASE WHEN l.converted THEN 1.0 ELSE 0 END) AS conv,
                 row_number() OVER (PARTITION BY d.segment_name
                                    ORDER BY avg(CASE WHEN l.converted THEN 1.0 ELSE 0 END) DESC) AS rn
          FROM clean.dashboard_segments d JOIN clean.clean_leads l USING (customer_id)
          JOIN (SELECT DISTINCT ON (lead_id) lead_id, channel FROM clean.clean_interactions
                WHERE direction = 'Outbound' ORDER BY lead_id, interaction_time) fo USING (lead_id)
          WHERE l.is_closed = 1
          GROUP BY 1, 2 HAVING count(*) >= 200) x
    WHERE rn = 1
)
SELECT s.segment_name,
       round(s.value_per_closed_lead::numeric, 0)                          AS value_per_closed_lead_gbp,
       round((100 * s.value_per_closed_lead / (SELECT v FROM avg_lead))::numeric, 0) AS value_per_lead_index,
       CASE WHEN 100 * s.value_per_closed_lead / (SELECT v FROM avg_lead) >= 115 THEN 'P1'
            WHEN 100 * s.value_per_closed_lead / (SELECT v FROM avg_lead) >= 60  THEN 'P2'
            ELSE 'P3' END                                                   AS priority_tier,
       CASE WHEN d.main_team IN ('Investor desk', 'International desk', 'Corporate lettings', 'New homes') THEN d.main_team
            WHEN d.main_team LIKE '%Lettings' THEN 'Regional lettings desks'
            ELSE 'Regional sales desks' END                                AS routed_desk,
       fc.channel                                                          AS best_first_contact,
       round(100 * fc.conv, 1)                                             AS first_contact_conversion_pct,
       s.conversion_pct, s.customers
FROM s
LEFT JOIN desk d USING (segment_name)
LEFT JOIN first_contact fc USING (segment_name);

SELECT * FROM clean.segment_tiers ORDER BY value_per_lead_index DESC;

-- Tier and handling rules, one row per tier (for the action panel and the CRM)
DROP TABLE IF EXISTS clean.tier_rules;
CREATE TABLE clean.tier_rules (priority_tier VARCHAR PRIMARY KEY, agent_level VARCHAR, reply_target VARCHAR, tag_colour VARCHAR);
INSERT INTO clean.tier_rules VALUES
 ('P1', 'Senior agent first', 'First reply within 1 hour, 7 days a week', '#E8702A'),
 ('P2', 'Mid or senior agent', 'First reply within 4 hours (working hours)', '#1F4E79'),
 ('P3', 'Any agent or automated nurture', 'Same day; automated reply immediately', '#9BA7B4');

-- =====================================================================================
-- STEP 2 · Recommended action per segment (feeds the action panel on Segment deep dive)
-- =====================================================================================
CREATE OR REPLACE VIEW clean.segment_actions AS
SELECT t.segment_name, p.segment_order, t.priority_tier, r.agent_level, r.reply_target, r.tag_colour,
       t.routed_desk, t.best_first_contact,
       p.customers || ' customers (' || p.pct_of_customers || '%), ' || p.pct_of_deal_value || '% of deal value' AS size_and_value,
       'Converts ' || p.conversion_pct || '%, decides in a median ' || p.median_days_to_decide || ' days' AS conversion_fact,
       'Arrives via ' || p.top_channel || '; looks most at ' || p.main_region_viewed
         || '; first reply today ' || p.median_first_reply_h || ' h' AS behaviour_fact,
       t.priority_tier || ': route to ' || t.routed_desk || ' (' || r.agent_level || '); first contact by '
         || coalesce(t.best_first_contact, 'Phone') || '; ' || r.reply_target || '.' AS recommended_action
FROM clean.segment_tiers t
JOIN clean.segment_profile p USING (segment_name)
JOIN clean.tier_rules r USING (priority_tier);

SELECT segment_name, priority_tier, recommended_action FROM clean.segment_actions ORDER BY segment_order;

-- =====================================================================================
-- STEP 3 · Open leads by priority tier, desk and agent level (Pipeline and agents table)
-- =====================================================================================
CREATE OR REPLACE VIEW clean.open_leads_by_tier AS
SELECT t.priority_tier, a.team AS desk, a.seniority AS agent_level,
       count(*) AS open_leads,
       count(*) FILTER (WHERE l.lead_stage IN ('Viewing', 'Offer')) AS at_viewing_or_offer
FROM clean.clean_leads l
JOIN clean.dashboard_segments d USING (customer_id)
JOIN clean.segment_tiers t USING (segment_name)
JOIN clean.clean_agents a USING (agent_id)
WHERE l.is_open = 1
GROUP BY 1, 2, 3;

SELECT priority_tier, sum(open_leads) AS open_leads,
       sum(open_leads) FILTER (WHERE agent_level = 'Senior') AS with_senior_agent,
       round(100.0 * sum(open_leads) FILTER (WHERE agent_level = 'Senior') / sum(open_leads), 1) AS pct_with_senior
FROM clean.open_leads_by_tier GROUP BY 1 ORDER BY 1;

-- =====================================================================================
-- STEP 4 · Segment demand report: region, property type, price band, payment structure
-- "Looked at" = property events by known customers; "Bought / rented" = completed deals.
-- One long table, so one Power BI matrix/bar can switch dimension with a slicer.
-- =====================================================================================
CREATE OR REPLACE VIEW clean.property_price_band AS
SELECT property_id,
       CASE WHEN listing_purpose = 'Rent' THEN
                CASE WHEN rent_pcm_gbp < 1000 THEN 'Rent: under £1,000 pcm'
                     WHEN rent_pcm_gbp < 2000 THEN 'Rent: £1,000-2,000 pcm'
                     ELSE 'Rent: £2,000+ pcm' END
            ELSE
                CASE WHEN asking_price_gbp < 200000 THEN 'Sale: under £200k'
                     WHEN asking_price_gbp < 350000 THEN 'Sale: £200k-350k'
                     WHEN asking_price_gbp < 600000 THEN 'Sale: £350k-600k'
                     ELSE 'Sale: £600k+' END
       END AS price_band
FROM clean.clean_properties;

DROP TABLE IF EXISTS clean.segment_demand CASCADE;
CREATE TABLE clean.segment_demand AS
WITH views AS (
    SELECT d.segment_name, lo.region, p.property_type, b.price_band, count(*) AS property_events
    FROM clean.clean_property_views v
    JOIN clean.clean_web_sessions w USING (session_id)
    JOIN clean.dashboard_segments d ON d.customer_id = w.customer_id
    JOIN clean.clean_properties p USING (property_id)
    JOIN clean.clean_locations lo USING (location_id)
    JOIN clean.property_price_band b USING (property_id)
    GROUP BY 1, 2, 3, 4
),
deals AS (
    SELECT d.segment_name, lo.region, p.property_type, b.price_band, t.finance_type AS payment_structure,
           count(*) AS deals, sum(t.deal_value_gbp) AS deal_value_gbp,
           count(*) FILTER (WHERE t.contract_date >= DATE '2025-10-01') AS deals_last_12m,
           count(*) FILTER (WHERE t.contract_date BETWEEN DATE '2024-10-01' AND DATE '2025-09-30') AS deals_prev_12m
    FROM clean.clean_transactions t
    JOIN clean.dashboard_segments d USING (customer_id)
    JOIN clean.clean_properties p USING (property_id)
    JOIN clean.clean_locations lo USING (location_id)
    JOIN clean.property_price_band b USING (property_id)
    GROUP BY 1, 2, 3, 4, 5
)
SELECT 'Region' AS dimension, segment_name, region AS value, sum(property_events) AS property_events,
       NULL::bigint AS deals, NULL::numeric AS deal_value_gbp, NULL::bigint AS deals_last_12m, NULL::bigint AS deals_prev_12m
FROM views GROUP BY 2, 3
UNION ALL SELECT 'Property type', segment_name, property_type, sum(property_events), NULL, NULL, NULL, NULL FROM views GROUP BY 2, 3
UNION ALL SELECT 'Price band', segment_name, price_band, sum(property_events), NULL, NULL, NULL, NULL FROM views GROUP BY 2, 3
UNION ALL SELECT 'Region', segment_name, region, NULL, sum(deals), sum(deal_value_gbp)::numeric, sum(deals_last_12m), sum(deals_prev_12m) FROM deals GROUP BY 2, 3
UNION ALL SELECT 'Property type', segment_name, property_type, NULL, sum(deals), sum(deal_value_gbp)::numeric, sum(deals_last_12m), sum(deals_prev_12m) FROM deals GROUP BY 2, 3
UNION ALL SELECT 'Price band', segment_name, price_band, NULL, sum(deals), sum(deal_value_gbp)::numeric, sum(deals_last_12m), sum(deals_prev_12m) FROM deals GROUP BY 2, 3
UNION ALL SELECT 'Payment structure', segment_name, payment_structure, NULL, sum(deals), sum(deal_value_gbp)::numeric, sum(deals_last_12m), sum(deals_prev_12m) FROM deals GROUP BY 2, 3;

-- The report in one table: per dimension value, share of what is looked at vs share of deals
CREATE OR REPLACE VIEW clean.demand_report AS
SELECT dimension, value,
       sum(property_events) AS property_events,
       sum(deals) AS deals,
       round((sum(deal_value_gbp) / 1e6)::numeric, 1) AS deal_value_m,
       round(100.0 * sum(property_events) / sum(sum(property_events)) OVER (PARTITION BY dimension), 1) AS pct_of_views,
       round(100.0 * sum(deals) / sum(sum(deals)) OVER (PARTITION BY dimension), 1) AS pct_of_deals,
       sum(deals_last_12m) AS deals_last_12m, sum(deals_prev_12m) AS deals_prev_12m,
       round(100.0 * (sum(deals_last_12m)::numeric / nullif(sum(deals_prev_12m), 0) - 1), 1) AS deals_growth_pct
FROM clean.segment_demand GROUP BY 1, 2;

SELECT * FROM clean.demand_report ORDER BY dimension, deals DESC NULLS LAST;

-- =====================================================================================
-- STEP 5 · Window shoppers: flag them and move them to automated nurture
-- A window shopper browses but has never made an enquiry (no lead at all). Agents should
-- not chase them; an automated e-mail track should, until they enquire.
--   Window shopper = 3+ known web sessions AND no lead ever
--   nurture_track  = 'Active: weekly new-listings e-mail'  if they browsed in the last 90 days
--                    'Dormant: monthly digest'             if their last session is older
-- Customers with fewer than 3 sessions and no lead are 'Low engagement' (not mailed).
-- =====================================================================================
DROP TABLE IF EXISTS clean.window_shoppers CASCADE;
CREATE TABLE clean.window_shoppers AS
SELECT c.customer_id, d.segment_name, c.primary_intent, c.is_overseas, c.consent_marketing,
       s.n_sessions, coalesce(pv.n_property_events, 0) AS property_events, coalesce(pv.n_saves, 0) AS saves,
       pv.top_region_viewed, s.last_session_day,
       DATE '2026-09-30' - s.last_session_day AS days_since_last_session,
       CASE WHEN DATE '2026-09-30' - s.last_session_day <= 90 THEN 'Active: weekly new-listings e-mail'
            ELSE 'Dormant: monthly digest' END AS nurture_track
FROM clean.clean_customers c
JOIN feat.customer_session_summary s USING (customer_id)
LEFT JOIN feat.customer_property_view_summary pv USING (customer_id)
LEFT JOIN clean.dashboard_segments d USING (customer_id)
WHERE s.n_sessions >= 3
  AND NOT EXISTS (SELECT 1 FROM clean.clean_leads l WHERE l.customer_id = c.customer_id);
ALTER TABLE clean.window_shoppers ADD PRIMARY KEY (customer_id);

-- A flag on every customer (Power BI: relate on customer_id; CRM: import with the segment)
CREATE OR REPLACE VIEW clean.customer_engagement AS
SELECT c.customer_id,
       CASE WHEN EXISTS (SELECT 1 FROM clean.clean_leads l WHERE l.customer_id = c.customer_id) THEN 'Has enquired'
            WHEN w.customer_id IS NOT NULL THEN 'Window shopper'
            ELSE 'Low engagement' END AS engagement_status,
       (w.customer_id IS NOT NULL) AS is_window_shopper,
       w.nurture_track
FROM clean.clean_customers c LEFT JOIN clean.window_shoppers w USING (customer_id);

-- The nurture list for the CRM / e-mail tool: consenting window shoppers only
CREATE OR REPLACE VIEW clean.nurture_list AS
SELECT customer_id, segment_name, primary_intent, top_region_viewed, nurture_track, last_session_day
FROM clean.window_shoppers WHERE consent_marketing;

-- How big is it, and how much agent time does it free?
SELECT engagement_status, count(*) AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct_of_customers
FROM clean.customer_engagement GROUP BY 1 ORDER BY 2 DESC;
SELECT nurture_track, count(*) AS window_shoppers, count(*) FILTER (WHERE consent_marketing) AS can_be_mailed
FROM clean.window_shoppers GROUP BY 1 ORDER BY 1;
SELECT coalesce(segment_name, 'No segment') AS segment_name, count(*) AS window_shoppers,
       round(avg(n_sessions), 1) AS avg_sessions, round(avg(property_events)) AS avg_property_events
FROM clean.window_shoppers GROUP BY 1 ORDER BY 2 DESC;

-- =====================================================================================
-- STEP 6 · Routing rules as a table the CRM can import (one row per rule, checked in order)
-- Rule 1 catches window shoppers before any agent sees them; rules 2+ route enquiries by
-- segment to a desk and seniority, with the reply target of the segment's tier.
-- =====================================================================================
DROP TABLE IF EXISTS clean.routing_rules CASCADE;
CREATE TABLE clean.routing_rules AS
SELECT 1 AS rule_order,
       'Window shopper (no enquiry yet)'::varchar AS applies_to,
       'engagement_status = ''Window shopper'''::varchar AS crm_condition,
       NULL::varchar AS priority_tier,
       'Automated nurture (no agent)'::varchar AS route_to_desk,
       'None'::varchar AS agent_level,
       NULL::int AS first_reply_target_min,
       'E-mail nurture track; create a lead and re-route on first enquiry'::varchar AS action
UNION ALL
SELECT 1 + row_number() OVER (ORDER BY t.value_per_lead_index DESC),
       t.segment_name,
       'segment_name = ''' || t.segment_name || '''',
       t.priority_tier,
       t.routed_desk,
       r.agent_level,
       CASE t.priority_tier WHEN 'P1' THEN 60 WHEN 'P2' THEN 240 ELSE 480 END,
       'First contact by ' || coalesce(t.best_first_contact, 'Phone') || '; ' || r.reply_target
FROM clean.segment_tiers t JOIN clean.tier_rules r USING (priority_tier);

SELECT * FROM clean.routing_rules ORDER BY rule_order;
-- Export for the CRM team: run the SELECT above > download > routing_rules_<date>.csv

-- Check: every open lead hits exactly one rule (expect 0 without a rule)
SELECT count(*) AS open_leads,
       count(*) FILTER (WHERE r.applies_to IS NULL) AS open_leads_without_rule
FROM clean.clean_leads l
JOIN clean.dashboard_segments d USING (customer_id)
LEFT JOIN clean.routing_rules r ON r.applies_to = d.segment_name
WHERE l.is_open = 1;

-- =====================================================================================
-- DAY 12 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · Which segments should go to senior agents first, and how many open leads does that
--      put on each desk today?
SELECT segment_name, priority_tier, value_per_lead_index, routed_desk FROM clean.segment_tiers ORDER BY value_per_lead_index DESC;
SELECT desk, sum(open_leads) AS p1_open_leads, sum(at_viewing_or_offer) AS p1_at_viewing_or_offer,
       (SELECT count(*) FROM clean.clean_agents a WHERE a.team = o.desk AND a.seniority = 'Senior') AS senior_agents,
       round(sum(open_leads)::numeric / nullif((SELECT count(*) FROM clean.clean_agents a WHERE a.team = o.desk AND a.seniority = 'Senior'), 0), 1) AS p1_leads_per_senior
FROM clean.open_leads_by_tier o WHERE priority_tier = 'P1'
GROUP BY desk ORDER BY 2 DESC;

-- Q2 · Is late payment a rent problem or a segment problem?
-- If every segment pays RENT late at a similar rate, it is a rent problem.
SELECT d.segment_name,
       count(*) FILTER (WHERE p.payment_type = 'Monthly rent') AS rent_payments_due,
       round(100.0 * avg(p.is_late_or_overdue) FILTER (WHERE p.payment_type = 'Monthly rent'), 1) AS rent_late_pct,
       count(*) FILTER (WHERE p.payment_type <> 'Monthly rent') AS other_payments_due,
       round(100.0 * avg(p.is_late_or_overdue) FILTER (WHERE p.payment_type <> 'Monthly rent'), 1) AS other_late_pct
FROM clean.dashboard_segments d JOIN clean.clean_payments p USING (customer_id)
WHERE p.status <> 'Scheduled'
GROUP BY 1 ORDER BY 3 DESC NULLS LAST;
-- Rent split by tenancy type (company lets vs assured shorthold tenancies)
SELECT t.transaction_type, count(*) AS rent_payments_due, round(100.0 * avg(p.is_late_or_overdue), 1) AS rent_late_pct
FROM clean.clean_payments p JOIN clean.clean_transactions t USING (transaction_id)
WHERE p.status <> 'Scheduled' AND p.payment_type = 'Monthly rent'
GROUP BY 1;

-- Q3 · Which demand (region, property type, price band) should acquisition focus on next quarter?
-- Look for: growing deals AND more looking than buying (demand we could serve with more stock).
SELECT dimension, value, pct_of_views, pct_of_deals, round(pct_of_views - pct_of_deals, 1) AS views_minus_deals_pts,
       deals_last_12m, deals_prev_12m, deals_growth_pct
FROM clean.demand_report
WHERE dimension IN ('Region', 'Property type', 'Price band')
ORDER BY dimension, deals_growth_pct DESC NULLS LAST;

-- OWN QUESTION A · How much of today's open pipeline is P1, and is it with senior agents?
SELECT priority_tier, sum(open_leads) AS open_leads,
       round(100.0 * sum(open_leads) FILTER (WHERE agent_level = 'Senior') / sum(open_leads), 1) AS pct_with_senior,
       round(100.0 * sum(open_leads) FILTER (WHERE agent_level = 'Junior') / sum(open_leads), 1) AS pct_with_junior
FROM clean.open_leads_by_tier GROUP BY 1 ORDER BY 1;

-- OWN QUESTION B · How do segments pay for their homes (cash, mortgage, buy-to-let)?
SELECT segment_name, value AS payment_structure, deals,
       round(100.0 * deals / sum(deals) OVER (PARTITION BY segment_name), 1) AS pct_of_segment_deals
FROM clean.segment_demand WHERE dimension = 'Payment structure'
ORDER BY segment_name, deals DESC;
