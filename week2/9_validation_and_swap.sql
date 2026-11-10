-- =====================================================================================
-- DAY 10 · Do the segments differ in business terms? Then swap the dashboard to seg-v1.0
-- Needs: Day 9. Run in pgAdmin on veltrix, ONE STEP AT A TIME.
--
-- Three outcome tests per segmentation:
--   conversion    : won vs lost leads by segment        -> chi-square test (SQL, below)
--   late payment  : late/overdue vs on-time by segment  -> chi-square test (SQL, below)
--   revenue       : deal value per customer by segment  -> Kruskal-Wallis (day10_outcome_tests.py)
-- The SQL gives the chi-square statistic, its degrees of freedom, Cramér's V (effect size)
-- and a pass/fail against the 0.1% critical value. The Python script gives exact p-values.
-- =====================================================================================

-- =====================================================================================
-- STEP 1 · Load the DS file (customer_segments, model_version = seg-v1.0)
--   a) pgAdmin: right-click clean > Tables > ds_labels_staging > Import/Export Data > Import >
--      the DS CSV > Options: Header ON > OK. (Columns: customer_id, segment_id, segment_name.)
--      If the table was dropped, re-run Day 9 STEP 3 first.
--   b) Then run 1c and 1d.
-- =====================================================================================
-- 1a. Empty the staging table before importing (run this BEFORE the import)
TRUNCATE clean.ds_labels_staging;

-- 1c. Copy into the segment table as seg-v1.0 (re-runnable: removes an older seg-v1.0 first)
DELETE FROM clean.customer_segments WHERE model_version = 'seg-v1.0';
INSERT INTO clean.customer_segments (customer_id, model_version, segment_id, segment_name)
SELECT customer_id, 'seg-v1.0', segment_id, segment_name FROM clean.ds_labels_staging;

-- 1d. Check the file before switching. Expected: rows = 100,573, unknown_ids = 0, missing = 0
SELECT (SELECT count(*) FROM clean.customer_segments WHERE model_version = 'seg-v1.0') AS rows_loaded,
       (SELECT count(*) FROM clean.customer_segments s LEFT JOIN clean.clean_customers c USING (customer_id)
         WHERE s.model_version = 'seg-v1.0' AND c.customer_id IS NULL)                  AS unknown_ids,
       (SELECT count(*) FROM clean.clean_customers c
         LEFT JOIN clean.customer_segments s ON s.customer_id = c.customer_id AND s.model_version = 'seg-v1.0'
         WHERE s.customer_id IS NULL)                                                   AS customers_missing;

-- =====================================================================================
-- STEP 2 · Chi-square tests in SQL for every segmentation loaded (placeholders and seg-v1.0)
-- =====================================================================================
-- Critical values of chi-square at p = 0.001 (from statistics tables), df = segments - 1
DROP TABLE IF EXISTS clean.chi2_critical_001 CASCADE;   -- CASCADE: the outcome-test view below is rebuilt right after
CREATE TABLE clean.chi2_critical_001 (df INT PRIMARY KEY, critical_value NUMERIC);
INSERT INTO clean.chi2_critical_001 VALUES
 (1,10.83),(2,13.82),(3,16.27),(4,18.47),(5,20.52),(6,22.46),(7,24.32),(8,26.12),(9,27.88),(10,29.59),(11,31.26),(12,32.91);

CREATE OR REPLACE VIEW clean.segment_outcome_tests AS
WITH obs AS (   -- observed counts: one row per segment per outcome, "yes" and "no"
    SELECT cs.model_version, cs.segment_name, 'Conversion (won vs lost leads)' AS outcome,
           count(*) FILTER (WHERE l.converted)     AS yes,
           count(*) FILTER (WHERE NOT l.converted) AS no
    FROM clean.customer_segments cs JOIN clean.clean_leads l USING (customer_id)
    WHERE l.is_closed = 1 GROUP BY 1, 2
    UNION ALL
    SELECT cs.model_version, cs.segment_name, 'Late payment (late or overdue vs on time)',
           count(*) FILTER (WHERE p.is_late_or_overdue = 1),
           count(*) FILTER (WHERE p.is_late_or_overdue = 0)
    FROM clean.customer_segments cs JOIN clean.clean_payments p USING (customer_id)
    WHERE p.status <> 'Scheduled' GROUP BY 1, 2
), tot AS (
    SELECT model_version, outcome, sum(yes) AS yes_all, sum(no) AS no_all, sum(yes + no) AS n_all, count(*) AS k
    FROM obs GROUP BY 1, 2
), cells AS (   -- (observed - expected)^2 / expected, for the yes and the no cell
    SELECT o.model_version, o.outcome,
           power(o.yes - (o.yes + o.no) * t.yes_all::numeric / t.n_all, 2) / ((o.yes + o.no) * t.yes_all::numeric / t.n_all)
         + power(o.no  - (o.yes + o.no) * t.no_all::numeric  / t.n_all, 2) / ((o.yes + o.no) * t.no_all::numeric  / t.n_all) AS contrib,
           100.0 * o.yes / (o.yes + o.no) AS rate
    FROM obs o JOIN tot t USING (model_version, outcome)
)
SELECT c.model_version, c.outcome, t.k AS segments, t.n_all AS observations,
       round(min(c.rate), 1) AS lowest_rate_pct, round(max(c.rate), 1) AS highest_rate_pct,
       round(max(c.rate) - min(c.rate), 1) AS gap_pts,
       round(sum(c.contrib), 1) AS chi_square, t.k - 1 AS df,
       round(sqrt(sum(c.contrib) / t.n_all), 3) AS cramers_v,      -- 0.1 small, 0.3 medium, 0.5 large
       cv.critical_value AS critical_value_p001,
       CASE WHEN sum(c.contrib) > cv.critical_value THEN 'Differ (p < 0.001)' ELSE 'No clear difference' END AS verdict
FROM cells c JOIN tot t USING (model_version, outcome)
LEFT JOIN clean.chi2_critical_001 cv ON cv.df = t.k - 1
GROUP BY c.model_version, c.outcome, t.k, t.n_all, cv.critical_value;

SELECT * FROM clean.segment_outcome_tests ORDER BY model_version, outcome;

-- Revenue: the per-segment numbers (the test itself runs in day10_outcome_tests.py)
SELECT cs.model_version, cs.segment_name,
       count(*) AS customers_with_a_decision,
       round(avg(o.deal_value_gbp)::numeric, 0) AS mean_deal_value_per_customer,
       round((sum(o.deal_value_gbp) / 1e6)::numeric, 1) AS deal_value_m
FROM clean.customer_segments cs JOIN feat.customer_outcomes o USING (customer_id)
WHERE o.converted IS NOT NULL
GROUP BY 1, 2 ORDER BY 1, 4 DESC;

-- =====================================================================================
-- STEP 3 · Switch the dashboard to the chosen segmentation, then refresh Power BI
-- =====================================================================================
UPDATE clean.segment_in_use SET model_version = 'seg-v1.0';
SELECT segment_order, segment_name, model_version, count(*) AS customers
FROM clean.dashboard_segments GROUP BY 1, 2, 3 ORDER BY 1;

-- =====================================================================================
-- STEP 4 · Check table for the Data check page: every segment visual must match these
-- =====================================================================================
CREATE OR REPLACE VIEW clean.segment_check AS
SELECT c.model_version, c.segment_name, c.customers, c.conversion_pct, c.deal_value_m,
       c.late_payments_pct, c.median_first_reply_h
FROM clean.segment_comparison c JOIN clean.segment_in_use u USING (model_version);
SELECT * FROM clean.segment_check ORDER BY customers DESC;

-- =====================================================================================
-- DAY 10 BUSINESS QUESTIONS (run after the switch; the answers depend on the DS segments)
-- =====================================================================================
-- Q1 · Do the final segments really differ on conversion, revenue and late payment,
--      and is the gap big enough to act on?   -> the seg-v1.0 rows of STEP 2 + the Python output.
--      Big enough to act on: verdict "Differ" AND a gap of several points AND Cramér's V >= 0.1.
SELECT * FROM clean.segment_outcome_tests WHERE model_version = (SELECT model_version FROM clean.segment_in_use);

-- Q2 · Which segment has the most customers but the least deal value?
SELECT segment_name, customers, pct_of_customers, pct_of_deal_value,
       round(pct_of_deal_value / nullif(pct_of_customers, 0), 2) AS value_index
FROM clean.segment_comparison JOIN clean.segment_in_use USING (model_version)
ORDER BY value_index;

-- Q3 · Which segment converts best, and is it also the fastest to decide?
SELECT cs.segment_name,
       round(100.0 * count(*) FILTER (WHERE l.converted) / count(*), 1) AS conversion_pct,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY l.closed_date - l.created_day) AS median_days_to_decision,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY l.closed_date - l.created_day) FILTER (WHERE l.converted) AS median_days_to_win
FROM clean.dashboard_segments cs JOIN clean.clean_leads l USING (customer_id)
WHERE l.is_closed = 1
GROUP BY 1 ORDER BY 2 DESC;

-- OWN QUESTION A · Does every segment get the same reply speed? (if not, routing is the fix)
SELECT cs.segment_name,
       round(100.0 * avg(CASE WHEN l.first_response_min < 60 THEN 1 ELSE 0 END), 1) AS pct_within_1h,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY l.first_response_min) AS median_reply_min
FROM clean.dashboard_segments cs JOIN clean.clean_leads l USING (customer_id)
WHERE l.first_response_min IS NOT NULL
GROUP BY 1 ORDER BY 2;

-- OWN QUESTION B · How much overdue money sits in each segment right now?
SELECT cs.segment_name, count(*) FILTER (WHERE p.status = 'Overdue') AS overdue_payments,
       round(sum(p.amount_gbp) FILTER (WHERE p.status = 'Overdue')::numeric, 0) AS overdue_gbp
FROM clean.dashboard_segments cs JOIN clean.clean_payments p USING (customer_id)
GROUP BY 1 ORDER BY 3 DESC NULLS LAST;

-- Just UPDATE then run step 4
UPDATE clean.segment_in_use SET model_version = 'placeholder-A';
SELECT * FROM clean.segment_in_use;