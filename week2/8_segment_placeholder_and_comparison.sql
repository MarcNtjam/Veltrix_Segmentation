-- =====================================================================================
-- DAY 9 · Placeholder segment table + segment comparison views
-- Needs: Day 7 (feat.customer_features, feat.customer_outcomes) and Day 8.
-- Run in pgAdmin on veltrix, ONE STEP AT A TIME.
--
-- The dashboard reads ONE view, clean.dashboard_segments. Which segmentation it shows is
-- decided by ONE row in clean.segment_in_use. Today it points at a placeholder; on Day 10
-- you load the DS file and change that row: Power BI just refreshes, nothing is rebuilt.
--
-- PLACEHOLDERS: until the DS team sends its candidate labels, two simple rule-based
-- segmentations stand in so every visual can be built and tested. They use profile and
-- budget fields only (no outcomes). Replace them with the DS candidates as soon as they arrive
-- (STEP 3). Do not present placeholder results as findings.
-- =====================================================================================

-- =====================================================================================
-- STEP 1 · The segment table: one row per customer per segmentation (model_version)
-- =====================================================================================
DROP TABLE IF EXISTS clean.customer_segments CASCADE;
CREATE TABLE clean.customer_segments (
    customer_id    VARCHAR NOT NULL,
    model_version  VARCHAR NOT NULL,       -- 'placeholder-A', 'placeholder-B', later 'seg-v1.0'
    segment_id     INT     NOT NULL,
    segment_name   VARCHAR NOT NULL,
    PRIMARY KEY (customer_id, model_version)
);

-- =====================================================================================
-- STEP 2 · Two placeholder candidates (rules, not a model)
-- =====================================================================================
-- Candidate A: who they are (profile personas). First matching rule wins.
INSERT INTO clean.customer_segments (customer_id, model_version, segment_id, segment_name)
SELECT customer_id, 'placeholder-A',
       CASE WHEN is_overseas THEN 1
            WHEN primary_intent = 'Rent' AND (customer_type = 'Corporate' OR buyer_position = 'Corporate tenant') THEN 2
            WHEN primary_intent = 'Rent' THEN 3
            WHEN customer_type = 'Limited company (SPV)' OR buyer_position IN ('Portfolio landlord', 'Overseas investor') THEN 4
            WHEN buyer_position = 'First-time buyer' THEN 5
            ELSE 6 END,
       CASE WHEN is_overseas THEN 'Overseas buyers and tenants'
            WHEN primary_intent = 'Rent' AND (customer_type = 'Corporate' OR buyer_position = 'Corporate tenant') THEN 'Corporate and relocation tenants'
            WHEN primary_intent = 'Rent' THEN 'UK renters'
            WHEN customer_type = 'Limited company (SPV)' OR buyer_position IN ('Portfolio landlord', 'Overseas investor') THEN 'UK investors and landlords'
            WHEN buyer_position = 'First-time buyer' THEN 'First-time buyers'
            ELSE 'Home movers and downsizers' END
FROM clean.clean_customers;

-- Candidate B: what they can spend. Budget = stated budget, or the median price / rent they viewed.
INSERT INTO clean.customer_segments (customer_id, model_version, segment_id, segment_name)
SELECT customer_id, 'placeholder-B', seg_id,
       CASE seg_id WHEN 1 THEN 'Premium buyers (£600k+)' WHEN 2 THEN 'Mid-market buyers (£300k-600k)'
                   WHEN 3 THEN 'Entry-level buyers (under £300k)' WHEN 4 THEN 'Premium renters (£2,500+ pcm)'
                   WHEN 5 THEN 'Standard renters' ELSE 'Budget unknown' END
FROM (
    SELECT f.customer_id,
           CASE WHEN f.primary_intent = 'Buy' AND coalesce(f.stated_budget_gbp, f.median_viewed_price_gbp) >= 600000 THEN 1
                WHEN f.primary_intent = 'Buy' AND coalesce(f.stated_budget_gbp, f.median_viewed_price_gbp) >= 300000 THEN 2
                WHEN f.primary_intent = 'Buy' AND coalesce(f.stated_budget_gbp, f.median_viewed_price_gbp) IS NOT NULL THEN 3
                WHEN f.primary_intent = 'Rent' AND coalesce(f.stated_rent_budget_pcm_gbp, f.median_viewed_rent_pcm_gbp) >= 2500 THEN 4
                WHEN f.primary_intent = 'Rent' AND coalesce(f.stated_rent_budget_pcm_gbp, f.median_viewed_rent_pcm_gbp) IS NOT NULL THEN 5
                ELSE 6 END AS seg_id
    FROM feat.customer_features f
) x;

SELECT model_version, segment_id, segment_name, count(*) AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY model_version), 1) AS pct_of_customers
FROM clean.customer_segments GROUP BY 1, 2, 3 ORDER BY 1, 2;

-- =====================================================================================
-- STEP 3 · WHEN THE DS TEAM SENDS ITS CANDIDATE LABELS (a CSV per candidate)
-- Expected columns: customer_id, segment_id, segment_name  (one row per customer).
--   a) Load it into this staging table with pgAdmin: right-click ds_labels_staging >
--      Import/Export Data > Import > the CSV > Options: Header ON.
--   b) Run the INSERT, changing 'ds-candidate-1' to the name of that candidate.
-- =====================================================================================
DROP TABLE IF EXISTS clean.ds_labels_staging;
CREATE TABLE clean.ds_labels_staging (customer_id VARCHAR, segment_id INT, segment_name VARCHAR);
-- (import the CSV here, then:)
-- INSERT INTO clean.customer_segments (customer_id, model_version, segment_id, segment_name)
-- SELECT customer_id, 'ds-candidate-1', segment_id, segment_name FROM clean.ds_labels_staging;
-- Check: every clean customer labelled once, and no unknown customer_id
-- SELECT (SELECT count(*) FROM clean.ds_labels_staging) AS rows_in_file,
--        (SELECT count(*) FROM clean.ds_labels_staging s LEFT JOIN clean.clean_customers c USING (customer_id) WHERE c.customer_id IS NULL) AS unknown_ids,
--        (SELECT count(*) FROM clean.clean_customers c LEFT JOIN clean.ds_labels_staging s USING (customer_id) WHERE s.customer_id IS NULL) AS customers_missing;

-- =====================================================================================
-- STEP 4 · The switch: which segmentation the dashboard shows
-- =====================================================================================
DROP TABLE IF EXISTS clean.segment_in_use CASCADE;
CREATE TABLE clean.segment_in_use (model_version VARCHAR NOT NULL);
INSERT INTO clean.segment_in_use VALUES ('placeholder-A');

-- The view Power BI loads. segment_order = by customer count (largest first), for consistent sorting.
CREATE OR REPLACE VIEW clean.dashboard_segments AS
WITH s AS (SELECT cs.* FROM clean.customer_segments cs
           JOIN clean.segment_in_use u ON u.model_version = cs.model_version)
SELECT s.customer_id, s.segment_id, s.segment_name, s.model_version,
       dense_rank() OVER (ORDER BY n.customers DESC, s.segment_name) AS segment_order
FROM s JOIN (SELECT segment_name, count(*) AS customers FROM s GROUP BY 1) n USING (segment_name);

SELECT segment_order, segment_name, count(*) AS customers
FROM clean.dashboard_segments GROUP BY 1, 2 ORDER BY 1;

-- =====================================================================================
-- STEP 5 · Segment comparison: the numbers behind every Day 9 visual
-- One view for ANY segmentation, so the same query compares the candidates.
-- Conversion = won / closed leads; deal value all time; late % on payments due.
-- =====================================================================================
CREATE OR REPLACE VIEW clean.segment_comparison AS
WITH base AS (
    SELECT cs.model_version, cs.segment_name, o.*, f.median_first_response_min
    FROM clean.customer_segments cs
    JOIN feat.customer_outcomes o USING (customer_id)
    JOIN feat.customer_features f USING (customer_id)
), leads AS (
    SELECT cs.model_version, cs.segment_name, count(*) AS leads,
           percentile_cont(0.5) WITHIN GROUP (ORDER BY l.first_response_min) / 60.0 AS median_first_reply_h
    FROM clean.customer_segments cs JOIN clean.clean_leads l USING (customer_id)
    GROUP BY 1, 2
)
SELECT b.model_version, b.segment_name,
       count(*)                                                             AS customers,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY b.model_version), 1) AS pct_of_customers,
       max(l.leads)                                                         AS leads,
       sum(b.n_closed_leads)                                                AS closed_leads,
       round(100.0 * sum(b.n_won_leads) / nullif(sum(b.n_closed_leads), 0), 1) AS conversion_pct,
       round((sum(b.deal_value_gbp) / 1e6)::numeric, 1)                     AS deal_value_m,
       round((100.0 * sum(b.deal_value_gbp) / sum(sum(b.deal_value_gbp)) OVER (PARTITION BY b.model_version))::numeric, 1) AS pct_of_deal_value,
       round(max(l.median_first_reply_h)::numeric, 1)                       AS median_first_reply_h,
       round(100.0 * sum(b.payments_late_or_overdue) / nullif(sum(b.payments_due), 0), 1) AS late_payments_pct,
       round(sum(b.payments_due)::numeric, 0)                               AS payments_due
FROM base b LEFT JOIN leads l USING (model_version, segment_name)
GROUP BY b.model_version, b.segment_name;

-- Segments at a glance (the segmentation in use)
SELECT c.* FROM clean.segment_comparison c JOIN clean.segment_in_use u USING (model_version)
ORDER BY customers DESC;

-- =====================================================================================
-- DAY 9 BUSINESS QUESTIONS  (answer them with the DS candidates once loaded;
-- the placeholder numbers below only test the method)
-- =====================================================================================

-- Q1 · Which groups bring more deal value than their share of customers, and which bring less?
--      value index = share of deal value / share of customers (above 1 = punches above its weight)
SELECT model_version, segment_name, pct_of_customers, pct_of_deal_value,
       round(pct_of_deal_value / nullif(pct_of_customers, 0), 2) AS value_index
FROM clean.segment_comparison ORDER BY model_version, value_index DESC;

-- Q2 · Is late payment concentrated in one group, or spread evenly?
--      share of all late payments vs share of payments due, per segment
SELECT cs.model_version, cs.segment_name,
       sum(o.payments_due) AS payments_due,
       round(100.0 * sum(o.payments_late_or_overdue) / nullif(sum(o.payments_due), 0), 1) AS late_pct,
       round(100.0 * sum(o.payments_late_or_overdue) / sum(sum(o.payments_late_or_overdue)) OVER (PARTITION BY cs.model_version), 1) AS pct_of_all_late,
       round(100.0 * sum(o.payments_due) / sum(sum(o.payments_due)) OVER (PARTITION BY cs.model_version), 1) AS pct_of_all_due
FROM clean.customer_segments cs JOIN feat.customer_outcomes o USING (customer_id)
GROUP BY 1, 2 ORDER BY 1, 4 DESC;

-- Q3 · Which candidate gives the clearest business story?
--      Clear = segments big enough to act on, and different on the outcomes that matter.
SELECT model_version,
       count(*)                                         AS n_segments,
       min(pct_of_customers)                            AS smallest_segment_pct,
       max(pct_of_customers)                            AS largest_segment_pct,
       max(conversion_pct) - min(conversion_pct)        AS conversion_spread_pts,
       max(late_payments_pct) - min(late_payments_pct)  AS late_spread_pts,
       round(max(pct_of_deal_value / nullif(pct_of_customers, 0)) - min(pct_of_deal_value / nullif(pct_of_customers, 0)), 2) AS value_index_spread
FROM clean.segment_comparison GROUP BY 1 ORDER BY 1;

-- OWN QUESTION A · Which segment waits longest for a first reply?
SELECT model_version, segment_name, median_first_reply_h, conversion_pct
FROM clean.segment_comparison ORDER BY model_version, median_first_reply_h DESC;

-- OWN QUESTION B · Which segment has the most open leads right now (where sales effort should go)?
SELECT cs.model_version, cs.segment_name, count(*) AS open_leads,
       count(*) FILTER (WHERE l.lead_stage IN ('Viewing', 'Offer')) AS at_viewing_or_offer
FROM clean.customer_segments cs JOIN clean.clean_leads l USING (customer_id)
WHERE l.is_open = 1 GROUP BY 1, 2 ORDER BY 1, 3 DESC;
