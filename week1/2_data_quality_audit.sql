-- =====================================================================================
-- DAY 3 · Data quality audit: SQL checks on keys, nulls, ranges, dates, orphans; profiling;
--         a data quality log you export to Excel
-- Run in pgAdmin: Query Tool on veltrix. Run step by step (highlight, F5).
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS dq;

-- -------------------------------------------------------------------------------------
-- STEP 1 · Helper for the budget checks: the median price / rent of the listings each
-- customer viewed online. A budget 10x what someone looks at is probably a typo.
-- (Joins 15M property views: about 1 minute.)
-- -------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dq.customer_viewed_prices;
CREATE TABLE dq.customer_viewed_prices AS
SELECT w.customer_id,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY p.asking_price_gbp) AS med_viewed_price,
       count(p.asking_price_gbp) AS n_sale_views,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY p.rent_pcm_gbp)     AS med_viewed_rent,
       count(p.rent_pcm_gbp) AS n_rent_views
FROM raw.web_sessions w
JOIN raw.property_views v USING (session_id)
JOIN raw.properties p USING (property_id)
WHERE w.customer_id IS NOT NULL
GROUP BY w.customer_id;

-- -------------------------------------------------------------------------------------
-- STEP 2 · The data quality log: one row per check
-- -------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dq.dq_log;
CREATE TABLE dq.dq_log (
    issue_id          VARCHAR PRIMARY KEY,
    check_type        VARCHAR,     -- Keys / Nulls / Labels / Range / Dates / Duplicates
    table_name        VARCHAR,
    column_name       VARCHAR,
    check_description VARCHAR,
    rows_affected     BIGINT,
    rows_checked      BIGINT,
    severity_if_found VARCHAR,     -- High / Medium / Low / Info
    proposed_fix      VARCHAR,
    dashboard_visual  VARCHAR      -- the visual this issue would distort
);

-- ---- 2a. KEYS: primary key unique and not null (one check per table) --------------------
INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-01', 'Keys', 'locations', 'location_id', 'Primary key duplicated or null', count(*) - count(DISTINCT location_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.locations;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-02', 'Keys', 'agents', 'agent_id', 'Primary key duplicated or null', count(*) - count(DISTINCT agent_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.agents;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-03', 'Keys', 'customers', 'customer_id', 'Primary key duplicated or null', count(*) - count(DISTINCT customer_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-04', 'Keys', 'campaigns', 'campaign_id', 'Primary key duplicated or null', count(*) - count(DISTINCT campaign_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.campaigns;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-05', 'Keys', 'leads', 'lead_id', 'Primary key duplicated or null', count(*) - count(DISTINCT lead_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.leads;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-06', 'Keys', 'interactions', 'interaction_id', 'Primary key duplicated or null', count(*) - count(DISTINCT interaction_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.interactions;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-07', 'Keys', 'properties', 'property_id', 'Primary key duplicated or null', count(*) - count(DISTINCT property_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.properties;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-08', 'Keys', 'site_visits', 'visit_id', 'Primary key duplicated or null', count(*) - count(DISTINCT visit_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.site_visits;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-09', 'Keys', 'transactions', 'transaction_id', 'Primary key duplicated or null', count(*) - count(DISTINCT transaction_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.transactions;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-10', 'Keys', 'payments', 'payment_id', 'Primary key duplicated or null', count(*) - count(DISTINCT payment_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.payments;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-11', 'Keys', 'campaign_responses', 'response_id', 'Primary key duplicated or null', count(*) - count(DISTINCT response_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.campaign_responses;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-12', 'Keys', 'web_sessions', 'session_id', 'Primary key duplicated or null', count(*) - count(DISTINCT session_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.web_sessions;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-13', 'Keys', 'property_views', 'view_id', 'Primary key duplicated or null', count(*) - count(DISTINCT view_id), count(*), 'High', 'Reject load', 'All pages'
FROM raw.property_views;

-- ---- 2b. KEYS: orphan foreign keys (child row pointing to a parent that does not exist) ---
INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-14', 'Keys', 'properties', 'location_id', 'Orphan: location_id not found in locations', count(*) FILTER (WHERE c.location_id IS NOT NULL AND p.location_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.properties c LEFT JOIN raw.locations p ON p.location_id = c.location_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-15', 'Keys', 'leads', 'customer_id', 'Orphan: customer_id not found in customers', count(*) FILTER (WHERE c.customer_id IS NOT NULL AND p.customer_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.leads c LEFT JOIN raw.customers p ON p.customer_id = c.customer_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-16', 'Keys', 'leads', 'agent_id', 'Orphan: agent_id not found in agents', count(*) FILTER (WHERE c.agent_id IS NOT NULL AND p.agent_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.leads c LEFT JOIN raw.agents p ON p.agent_id = c.agent_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-17', 'Keys', 'leads', 'campaign_id', 'Orphan: campaign_id not found in campaigns', count(*) FILTER (WHERE c.campaign_id IS NOT NULL AND p.campaign_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.leads c LEFT JOIN raw.campaigns p ON p.campaign_id = c.campaign_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-18', 'Keys', 'interactions', 'lead_id', 'Orphan: lead_id not found in leads', count(*) FILTER (WHERE c.lead_id IS NOT NULL AND p.lead_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.interactions c LEFT JOIN raw.leads p ON p.lead_id = c.lead_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-19', 'Keys', 'interactions', 'agent_id', 'Orphan: agent_id not found in agents', count(*) FILTER (WHERE c.agent_id IS NOT NULL AND p.agent_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.interactions c LEFT JOIN raw.agents p ON p.agent_id = c.agent_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-20', 'Keys', 'site_visits', 'lead_id', 'Orphan: lead_id not found in leads', count(*) FILTER (WHERE c.lead_id IS NOT NULL AND p.lead_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.site_visits c LEFT JOIN raw.leads p ON p.lead_id = c.lead_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-21', 'Keys', 'site_visits', 'property_id', 'Orphan: property_id not found in properties', count(*) FILTER (WHERE c.property_id IS NOT NULL AND p.property_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.site_visits c LEFT JOIN raw.properties p ON p.property_id = c.property_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-22', 'Keys', 'transactions', 'lead_id', 'Orphan: lead_id not found in leads', count(*) FILTER (WHERE c.lead_id IS NOT NULL AND p.lead_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.transactions c LEFT JOIN raw.leads p ON p.lead_id = c.lead_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-23', 'Keys', 'transactions', 'customer_id', 'Orphan: customer_id not found in customers', count(*) FILTER (WHERE c.customer_id IS NOT NULL AND p.customer_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.transactions c LEFT JOIN raw.customers p ON p.customer_id = c.customer_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-24', 'Keys', 'transactions', 'property_id', 'Orphan: property_id not found in properties', count(*) FILTER (WHERE c.property_id IS NOT NULL AND p.property_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.transactions c LEFT JOIN raw.properties p ON p.property_id = c.property_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-25', 'Keys', 'payments', 'transaction_id', 'Orphan: transaction_id not found in transactions', count(*) FILTER (WHERE c.transaction_id IS NOT NULL AND p.transaction_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.payments c LEFT JOIN raw.transactions p ON p.transaction_id = c.transaction_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-26', 'Keys', 'campaign_responses', 'campaign_id', 'Orphan: campaign_id not found in campaigns', count(*) FILTER (WHERE c.campaign_id IS NOT NULL AND p.campaign_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.campaign_responses c LEFT JOIN raw.campaigns p ON p.campaign_id = c.campaign_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-27', 'Keys', 'campaign_responses', 'customer_id', 'Orphan: customer_id not found in customers', count(*) FILTER (WHERE c.customer_id IS NOT NULL AND p.customer_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.campaign_responses c LEFT JOIN raw.customers p ON p.customer_id = c.customer_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-28', 'Keys', 'web_sessions', 'customer_id', 'Orphan: customer_id not found in customers', count(*) FILTER (WHERE c.customer_id IS NOT NULL AND p.customer_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.web_sessions c LEFT JOIN raw.customers p ON p.customer_id = c.customer_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-29', 'Keys', 'property_views', 'session_id', 'Orphan: session_id not found in web_sessions', count(*) FILTER (WHERE c.session_id IS NOT NULL AND p.session_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.property_views c LEFT JOIN raw.web_sessions p ON p.session_id = c.session_id;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-30', 'Keys', 'property_views', 'property_id', 'Orphan: property_id not found in properties', count(*) FILTER (WHERE c.property_id IS NOT NULL AND p.property_id IS NULL), count(*), 'High', 'Fix or remove orphan rows', 'All joins'
FROM raw.property_views c LEFT JOIN raw.properties p ON p.property_id = c.property_id;

-- ---- 2c. NULLS: blanks that are a problem (blanks that are expected by design are not flagged) ---
INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-31', 'Nulls', 'customers', 'stated_budget_gbp', 'Buyer with no purchase budget', count(*) FILTER (WHERE stated_budget_gbp IS NULL AND primary_intent = 'Buy'), count(*) FILTER (WHERE primary_intent = 'Buy'), 'High', 'Phase 2: estimate from prices viewed', 'Segment: median price level'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-32', 'Nulls', 'customers', 'stated_rent_budget_pcm_gbp', 'Renter with no rent budget', count(*) FILTER (WHERE stated_rent_budget_pcm_gbp IS NULL AND primary_intent = 'Rent'), count(*) FILTER (WHERE primary_intent = 'Rent'), 'High', 'Phase 2: estimate from rents viewed', 'Segment: median rent'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-33', 'Nulls', 'customers', 'age_band', 'age_band missing', count(*) FILTER (WHERE age_band IS NULL), count(*), 'Medium', 'Keep as Unknown', 'Segment profile'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-34', 'Nulls', 'customers', 'occupation_sector', 'occupation_sector missing', count(*) FILTER (WHERE occupation_sector IS NULL), count(*), 'Medium', 'Keep as Unknown', 'Segment profile'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-35', 'Nulls', 'customers', 'gender', 'gender blank AND a separate Not stated value', count(*) FILTER (WHERE gender IS NULL), count(*), 'Low', 'Recode blank to Not stated', 'Segment profile'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-36', 'Nulls', 'customers', 'uk_region_of_residence', 'UK resident with no region', count(*) FILTER (WHERE uk_region_of_residence IS NULL AND NOT is_overseas), count(*) FILTER (WHERE NOT is_overseas), 'Medium', 'Keep as Unknown; infer from browsing in Phase 2', 'Region filter'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-37', 'Nulls', 'customers', 'phone_sha256', 'No phone (limits duplicate matching)', count(*) FILTER (WHERE phone_sha256 IS NULL), count(*), 'Low', 'Match on email instead', 'Customer count'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-38', 'Nulls', 'interactions', 'response_time_min', 'Inbound contact with no reply time', count(*) FILTER (WHERE response_time_min IS NULL AND direction = 'Inbound'), count(*) FILTER (WHERE direction = 'Inbound'), 'Medium', 'Exclude from reply KPIs (Unknown band)', 'Pipeline: conversion by reply band'
FROM raw.interactions;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-39', 'Nulls', 'properties', 'size_sqm', 'size_sqm missing', count(*) FILTER (WHERE size_sqm IS NULL), count(*), 'Low', 'Phase 2 estimate', 'Demand report'
FROM raw.properties;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-40', 'Nulls', 'properties', 'epc_rating', 'epc_rating missing', count(*) FILTER (WHERE epc_rating IS NULL), count(*), 'Low', 'Keep as Unknown', 'Demand report'
FROM raw.properties;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-41', 'Nulls', 'transactions', 'finance_type', 'Tenancy with no finance_type', count(*) FILTER (WHERE finance_type IS NULL), count(*), 'Low', 'Set to Renting', 'Payments: deal value by type'
FROM raw.transactions;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-42', 'Nulls', 'web_sessions', 'customer_id', 'Anonymous session (expected)', count(*) FILTER (WHERE customer_id IS NULL), count(*), 'Info', 'Keep for traffic only', 'Segment: browsing'
FROM raw.web_sessions;

-- ---- 2d. LABELS: inconsistent categories ----------------------------------------------------
INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-43', 'Labels', 'leads', 'lead_source', 'Non-standard lead-source spelling (14 variants)', count(*) FILTER (WHERE lead_source NOT IN ('Rightmove','Zoopla','OnTheMarket','Veltrix website','Google Ads','Facebook','Instagram','TikTok','WeChat','Email newsletter','Referral','Branch walk-in','Overseas agent partner','Relocation partner')), count(*), 'High', 'CASE mapping table (Day 4)', 'Pipeline: conversion by channel'
FROM raw.leads;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-44', 'Labels', 'customers', 'country_of_residence', 'Non-standard country label (UK, U.K., England, HK, UAE, KSA...)', count(*) FILTER (WHERE country_of_residence NOT IN ('United Kingdom','Hong Kong','United Arab Emirates','China','United States','Singapore','Saudi Arabia','India','Nigeria','Canada','Malaysia','Qatar')), count(*), 'High', 'CASE mapping to ISO country (Day 4)', 'Overview: overseas share'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-45', 'Labels', 'web_sessions', 'ip_country', 'UK resident browsing from a non-UK IP (VPN noise)', count(*) FILTER (WHERE w.ip_country <> 'GB' AND NOT c.is_overseas), count(*) FILTER (WHERE NOT c.is_overseas), 'Medium', 'Use residence, never IP', 'Overview: overseas share'
FROM raw.web_sessions w JOIN raw.customers c USING (customer_id);

-- ---- 2e. RANGES and TYPOS ----------------------------------------------------------------------
INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-46', 'Range', 'customers', 'stated_budget_gbp', 'Purchase budget under 5,000 (typed in thousands)', count(*) FILTER (WHERE stated_budget_gbp < 5000), count(stated_budget_gbp), 'High', 'x1000 (Day 4)', 'Segment: median price level'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-47', 'Range', 'customers', 'stated_budget_gbp', 'Purchase budget 6x+ the prices the customer viewed (extra zero)', count(*) FILTER (WHERE c.stated_budget_gbp >= 6 * v.med_viewed_price AND v.n_sale_views >= 3), count(c.stated_budget_gbp), 'High', '/10 (Day 4)', 'Segment: median price; lead priority'
FROM raw.customers c LEFT JOIN dq.customer_viewed_prices v USING (customer_id);

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-48', 'Range', 'customers', 'stated_budget_gbp', 'Budget 3-6x viewed prices starting with a stray 1', count(*) FILTER (WHERE c.stated_budget_gbp BETWEEN 3 * v.med_viewed_price AND 6 * v.med_viewed_price AND v.n_sale_views >= 3 AND c.stated_budget_gbp::text LIKE '1%'), count(c.stated_budget_gbp), 'Medium', 'Drop the first digit (Day 4)', 'Segment: median price'
FROM raw.customers c LEFT JOIN dq.customer_viewed_prices v USING (customer_id);

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-49', 'Range', 'customers', 'stated_rent_budget_pcm_gbp', 'Rent budget 10,000+ a month (annual figure or extra zero)', count(*) FILTER (WHERE stated_rent_budget_pcm_gbp >= 10000), count(stated_rent_budget_pcm_gbp), 'High', '/12 or /10 (Day 4)', 'Segment: median rent'
FROM raw.customers;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-50', 'Range', 'payments', 'amount_gbp', 'Negative payment amount', count(*) FILTER (WHERE amount_gbp < 0), count(*), 'Medium', 'Ask finance', 'Payments: payments due'
FROM raw.payments;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-51', 'Range', 'transactions', 'discount_pct', 'Sold above asking (negative discount, plausible)', count(*) FILTER (WHERE discount_pct < 0), count(*), 'Info', 'Keep', 'Demand report'
FROM raw.transactions;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-52', 'Range', 'interactions', 'response_time_min', 'Reply time capped at 4,320 min (3 days)', count(*) FILTER (WHERE response_time_min = 4320), count(response_time_min), 'Low', 'Use bands and medians', 'Pipeline: median reply'
FROM raw.interactions;

-- ---- 2f. DATES and BUSINESS LOGIC ------------------------------------------------------------
INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-53', 'Dates', 'leads', 'closed_date', 'Lead closed before it was created', count(*) FILTER (WHERE closed_date < created_date::date), count(*), 'High', 'Investigate', 'Days to close'
FROM raw.leads;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-54', 'Dates', 'leads', 'converted', 'converted flag disagrees with stage Won', count(*) FILTER (WHERE converted <> (lead_stage = 'Won')), count(*), 'High', 'Use stage', 'Conversion %'
FROM raw.leads;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-55', 'Dates', 'leads', 'created_date', 'Lead before the customer first contact', count(*) FILTER (WHERE l.created_date::date < c.first_contact_date), count(*), 'High', 'Investigate', 'Customer history'
FROM raw.leads l JOIN raw.customers c USING (customer_id);

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-56', 'Dates', 'leads', 'agent_id', 'Lead handled before the agent was hired', count(*) FILTER (WHERE l.created_date::date < a.hire_date), count(*), 'High', 'Investigate', 'Agent seniority'
FROM raw.leads l JOIN raw.agents a USING (agent_id);

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-57', 'Dates', 'site_visits', 'visit_date', 'Viewing before the lead was created', count(*) FILTER (WHERE v.visit_date < l.created_date::date), count(*), 'High', 'Investigate', 'Pipeline'
FROM raw.site_visits v JOIN raw.leads l USING (lead_id);

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-58', 'Dates', 'transactions', 'contract_date', 'Contract before the lead was created', count(*) FILTER (WHERE t.contract_date < l.created_date::date), count(*), 'High', 'Investigate', 'Days to close'
FROM raw.transactions t JOIN raw.leads l USING (lead_id);

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-59', 'Dates', 'transactions', 'lead_id', 'Transaction on a lead that is not Won', count(*) FILTER (WHERE l.lead_stage <> 'Won'), count(*), 'High', 'Investigate', 'Deal value'
FROM raw.transactions t JOIN raw.leads l USING (lead_id);

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-60', 'Dates', 'payments', 'due_date', 'Payment due after 30 Sep 2026 (future schedule, expected)', count(*) FILTER (WHERE due_date > '2026-09-30'), count(*), 'Info', 'Exclude from late share', 'Payments: late share'
FROM raw.payments;

-- ---- 2g. DUPLICATES --------------------------------------------------------------------------
INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-61', 'Duplicates', 'customers', 'email_sha256', 'Records sharing an email hash with another record', count(*) FILTER (WHERE n > 1), count(*), 'High', 'Merge (Day 4)', 'Overview: customers card'
FROM (SELECT count(*) OVER (PARTITION BY email_sha256) AS n FROM raw.customers) x;

INSERT INTO dq.dq_log (issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked, severity_if_found, proposed_fix, dashboard_visual)
SELECT 'DQ-62', 'Duplicates', 'customers', 'phone_sha256', 'Records sharing a phone hash with another record', count(*) FILTER (WHERE n > 1 AND phone_sha256 IS NOT NULL), count(*), 'High', 'Merge (Day 4)', 'Overview: customers card'
FROM (SELECT phone_sha256, count(*) OVER (PARTITION BY phone_sha256) AS n FROM raw.customers) x;

-- -------------------------------------------------------------------------------------
-- STEP 3 · Add % affected and the final severity (Pass when nothing was found)
-- -------------------------------------------------------------------------------------
ALTER TABLE dq.dq_log ADD COLUMN pct_affected NUMERIC, ADD COLUMN severity VARCHAR;
UPDATE dq.dq_log SET pct_affected = round(100.0 * rows_affected / nullif(rows_checked, 0), 2),
                     severity = CASE WHEN rows_affected > 0 THEN severity_if_found ELSE 'Pass' END;

-- The log. Export: run it, then the download button above the results > CSV > open in Excel.
SELECT issue_id, check_type, table_name, column_name, check_description, rows_affected, rows_checked,
       pct_affected, severity, proposed_fix, dashboard_visual
FROM dq.dq_log ORDER BY issue_id;

-- Issues by table and severity (feeds the stacked bar chart on the Data check page)
SELECT table_name, severity, count(*) AS issues
FROM dq.dq_log WHERE severity IN ('High', 'Medium', 'Low')
GROUP BY 1, 2 ORDER BY 1, 2;


CREATE OR REPLACE VIEW dq.raw_lead_source_chart AS
SELECT lpad(row_number() OVER (ORDER BY count(*) DESC)::text, 2, '0') || '  ' || lead_source AS label,
       lead_source,
       count(*) AS leads,
       CASE WHEN lead_source IN ('Rightmove','Zoopla','OnTheMarket','Veltrix website','Google Ads','Facebook',
                                 'Instagram','TikTok','WeChat','Email newsletter','Referral','Branch walk-in',
                                 'Overseas agent partner','Relocation partner')
            THEN '#9BA7B4' ELSE '#E8702A' END AS bar_colour
FROM raw.leads
GROUP BY lead_source;

SELECT * FROM dq.raw_lead_source_chart ORDER BY leads DESC;   -- 28 rows

-- -------------------------------------------------------------------------------------
-- STEP 4 · PROFILE the categorical columns
-- -------------------------------------------------------------------------------------
-- Lead-source spellings (feeds the horizontal bar chart on the Data check page): 28 values for 14 channels
SELECT lead_source, count(*) AS leads FROM raw.leads GROUP BY 1 ORDER BY 2 DESC;

-- Country labels: 26 values for 12 countries
SELECT country_of_residence, is_overseas, count(*) AS customers FROM raw.customers GROUP BY 1, 2 ORDER BY 3 DESC;

-- Budget distribution: look at the extremes
SELECT percentile_cont(ARRAY[0.001, 0.01, 0.5, 0.99, 0.999]) WITHIN GROUP (ORDER BY stated_budget_gbp) AS budget_percentiles,
       min(stated_budget_gbp), max(stated_budget_gbp)
FROM raw.customers;

-- Suspicious budgets next to the prices the customer actually viewed
SELECT c.customer_id, c.stated_budget_gbp, v.med_viewed_price,
       round((c.stated_budget_gbp / v.med_viewed_price)::numeric, 1) AS budget_vs_viewed
FROM raw.customers c JOIN dq.customer_viewed_prices v USING (customer_id)
WHERE v.n_sale_views >= 3 AND (c.stated_budget_gbp < 5000 OR c.stated_budget_gbp >= 3 * v.med_viewed_price)
ORDER BY budget_vs_viewed DESC LIMIT 50;

-- =====================================================================================
-- DAY 3 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · How many customer records are duplicates, and how much would they overstate the count?
--      (Check: 1,103 email pairs + 726 phone pairs -> 1,427 duplicate records = +1.4%)
SELECT 'same email' AS matched_on, count(*) AS duplicate_pairs
FROM raw.customers a JOIN raw.customers b ON a.email_sha256 = b.email_sha256 AND a.customer_id < b.customer_id
UNION ALL
SELECT 'same phone', count(*)
FROM raw.customers a JOIN raw.customers b ON a.phone_sha256 = b.phone_sha256 AND a.customer_id < b.customer_id;
-- The exact count of records to merge (1,427) and the overstatement are computed on Day 4.

-- Q2 · Which data problem, if left unfixed, would most mislead the sales team?
-- Candidate: budget typos create fake VIP buyers. How many "£2m+" buyers are really typos?
-- A typo = 6x+ the prices they viewed, or 3-6x with a stray leading 1 whose rest fits what they viewed.
-- (Check: 74 customers state £2m+; 58 of them are typos -> 78%. For £5m+: 18 of 20 -> 90%)
WITH t AS (
    SELECT c.stated_budget_gbp AS b,
           (v.n_sale_views >= 3 AND (c.stated_budget_gbp >= 6 * v.med_viewed_price
             OR (c.stated_budget_gbp >= 3 * v.med_viewed_price AND c.stated_budget_gbp::text LIKE '1%'
                 AND (c.stated_budget_gbp - power(10, length(c.stated_budget_gbp::text) - 1)) / v.med_viewed_price BETWEEN 0.6 AND 1.6))) AS is_typo
    FROM raw.customers c LEFT JOIN dq.customer_viewed_prices v USING (customer_id)
    WHERE c.stated_budget_gbp >= 2000000)
SELECT count(*) AS stated_2m_plus, count(*) FILTER (WHERE is_typo) AS typos_2m_plus,
       round(100.0 * count(*) FILTER (WHERE is_typo) / count(*), 0) AS pct_typos_2m_plus,
       count(*) FILTER (WHERE b >= 5000000) AS stated_5m_plus, count(*) FILTER (WHERE b >= 5000000 AND is_typo) AS typos_5m_plus
FROM t;

-- Q3 · Are budget outliers large enough to distort a median price per segment?
-- Segments arrive on Day 9-10, so use buyer_position as a stand-in segment.
-- Compare median and mean with and without the suspicious budgets.
SELECT c.buyer_position,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY c.stated_budget_gbp)::int AS median_all,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY c.stated_budget_gbp) FILTER (WHERE NOT coalesce(c.stated_budget_gbp >= 6 * v.med_viewed_price OR c.stated_budget_gbp < 5000, false))::int AS median_without_outliers,
       avg(c.stated_budget_gbp)::int AS mean_all,
       avg(c.stated_budget_gbp) FILTER (WHERE NOT coalesce(c.stated_budget_gbp >= 6 * v.med_viewed_price OR c.stated_budget_gbp < 5000, false))::int AS mean_without_outliers,
       max(c.stated_budget_gbp) AS max_budget
FROM raw.customers c LEFT JOIN dq.customer_viewed_prices v USING (customer_id)
WHERE c.stated_budget_gbp IS NOT NULL
GROUP BY 1 ORDER BY 2 DESC;
-- Expected: medians barely move; means move a few %; max up to £11.65m -> always use the median.

-- OWN QUESTION A · Which lead sources arrive without a budget most often?
SELECT l.lead_source, count(*) AS leads,
       round(100.0 * avg(CASE WHEN c.stated_budget_gbp IS NULL AND c.stated_rent_budget_pcm_gbp IS NULL THEN 1 ELSE 0 END), 1) AS pct_no_budget
FROM raw.leads l JOIN raw.customers c USING (customer_id)
GROUP BY 1 ORDER BY 3 DESC;

-- OWN QUESTION B · Would the raw spellings change conclusions about channels?
-- (Look at 'Google' vs 'google ads' vs 'Google Ads': same channel, different conversion)
SELECT lead_source, count(*) FILTER (WHERE lead_stage IN ('Won','Lost')) AS closed,
       round(100.0 * avg(CASE WHEN converted THEN 1 ELSE 0 END) FILTER (WHERE lead_stage IN ('Won','Lost')), 1) AS conversion_pct
FROM raw.leads WHERE lead_source ILIKE '%google%' OR lead_source ILIKE '%zoopla%'
GROUP BY 1 ORDER BY 1;
