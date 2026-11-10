-- =====================================================================================
-- DAY 13 · Final semantic model support: one reconciliation table, segment movement,
--          and the table list for the star schema
-- Needs: Day 12. Run in pgAdmin on veltrix, ONE STEP AT A TIME.
-- No new visuals today: these give Power BI its last checks before publishing.
-- =====================================================================================

-- =====================================================================================
-- STEP 1 · Segment movement: how many customers changed segment between two versions
-- (seg-v1.0 vs the next monthly refresh, or a candidate vs another). Set the pair here.
-- =====================================================================================
DROP TABLE IF EXISTS clean.segment_movement_settings CASCADE;
CREATE TABLE clean.segment_movement_settings (from_version VARCHAR NOT NULL, to_version VARCHAR NOT NULL);
-- Until a second seg-v version exists, compare the two placeholders to test the method.
INSERT INTO clean.segment_movement_settings VALUES ('placeholder-A', 'placeholder-B');

CREATE OR REPLACE VIEW clean.segment_movement AS
SELECT f.segment_name AS from_segment, t.segment_name AS to_segment,
       (f.segment_name = t.segment_name) AS stayed,
       count(*) AS customers
FROM clean.segment_movement_settings s
JOIN clean.customer_segments f ON f.model_version = s.from_version
JOIN clean.customer_segments t ON t.model_version = s.to_version AND t.customer_id = f.customer_id
GROUP BY 1, 2, 3;

-- Share of customers whose segment name changed (with different segmentations every name
-- differs, so this is 100% for the placeholder pair; between seg-v1.0 and seg-v1.1 expect < 10%)
SELECT (SELECT from_version || ' -> ' || to_version FROM clean.segment_movement_settings) AS versions,
       sum(customers) AS customers_in_both,
       sum(customers) FILTER (WHERE NOT stayed) AS moved,
       round(100.0 * sum(customers) FILTER (WHERE NOT stayed) / sum(customers), 1) AS pct_moved
FROM clean.segment_movement;

-- Size change per segment between the two versions (feeds the drift alert on Day 15)
SELECT coalesce(a.segment_name, b.segment_name) AS segment_name, a.customers AS from_customers, b.customers AS to_customers,
       round(100.0 * (b.customers::numeric / nullif(a.customers, 0) - 1), 1) AS size_change_pct
FROM (SELECT segment_name, count(*) AS customers FROM clean.customer_segments
      WHERE model_version = (SELECT from_version FROM clean.segment_movement_settings) GROUP BY 1) a
FULL JOIN (SELECT segment_name, count(*) AS customers FROM clean.customer_segments
      WHERE model_version = (SELECT to_version FROM clean.segment_movement_settings) GROUP BY 1) b USING (segment_name)
ORDER BY 1;

-- =====================================================================================
-- STEP 2 · ONE final reconciliation table: every number the published report shows
-- Load it on the Data check page next to the matching measures. All-time unless noted.
-- =====================================================================================
DROP TABLE IF EXISTS clean.final_check;
CREATE TABLE clean.final_check AS
WITH w AS (SELECT DATE '2025-10-01' AS s, DATE '2026-09-30' AS e)
SELECT 'Overview' AS page, 1 AS check_order, 'Customers' AS measure, 'all time' AS filter_used,
       (SELECT count(*) FROM clean.clean_customers)::numeric AS sql_value
UNION ALL SELECT 'Overview', 2, 'Leads', 'Period = Last 12 months', (SELECT count(*) FROM clean.clean_leads, w WHERE created_day BETWEEN s AND e)
UNION ALL SELECT 'Overview', 3, 'Conversion % (by close date)', 'Period = Last 12 months',
       (SELECT round(100.0 * avg(CASE WHEN converted THEN 1 ELSE 0 END), 2) FROM clean.clean_leads, w WHERE is_closed = 1 AND closed_date BETWEEN s AND e)
UNION ALL SELECT 'Overview', 4, 'Deal value £m', 'Period = Last 12 months',
       (SELECT round((sum(deal_value_gbp) / 1e6)::numeric, 1) FROM clean.clean_transactions, w WHERE contract_date BETWEEN s AND e)
UNION ALL SELECT 'Overview', 5, 'Median first reply (h)', 'Period = Last 12 months',
       (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_min) / 60.0)::numeric, 2) FROM clean.clean_leads, w WHERE created_day BETWEEN s AND e)
UNION ALL SELECT 'Overview', 6, 'Late payments %', 'Period = Last 12 months',
       (SELECT round(100.0 * avg(is_late_or_overdue), 2) FROM clean.clean_payments, w WHERE status <> 'Scheduled' AND due_date BETWEEN s AND e)
UNION ALL SELECT 'Pipeline', 7, 'Open pipeline', 'any period', (SELECT count(*) FROM clean.clean_leads WHERE is_open = 1)
UNION ALL SELECT 'Pipeline', 8, 'Won leads (by close date)', 'Period = Last 12 months',
       (SELECT count(*) FROM clean.clean_leads, w WHERE converted AND closed_date BETWEEN s AND e)
UNION ALL SELECT 'Pipeline', 9, 'Answered within 1 hour %', 'Period = Last 12 months',
       (SELECT round(100.0 * avg(CASE WHEN first_response_min < 60 THEN 1 ELSE 0 END), 1) FROM clean.clean_leads, w WHERE first_response_min IS NOT NULL AND created_day BETWEEN s AND e)
UNION ALL SELECT 'Pipeline', 10, 'P1 open leads', 'any period',
       (SELECT sum(open_leads) FROM clean.open_leads_by_tier WHERE priority_tier = 'P1')
UNION ALL SELECT 'Payments', 11, 'Payments due', 'Period = Last 12 months',
       (SELECT count(*) FROM clean.clean_payments, w WHERE status <> 'Scheduled' AND due_date BETWEEN s AND e)
UNION ALL SELECT 'Payments', 12, 'Overdue now £', 'any period', (SELECT round(sum(amount_gbp)::numeric, 0) FROM clean.clean_payments WHERE status = 'Overdue')
UNION ALL SELECT 'Payments', 13, 'Late rate on monthly rent %', 'Period = Last 12 months',
       (SELECT round(100.0 * avg(is_late_or_overdue), 2) FROM clean.clean_payments, w WHERE status <> 'Scheduled' AND payment_type = 'Monthly rent' AND due_date BETWEEN s AND e)
UNION ALL SELECT 'Segment deep dive', 14, 'Customers with a segment', 'all time', (SELECT count(*) FROM clean.dashboard_segments)
UNION ALL SELECT 'Segment deep dive', 15, 'Segments in use', (SELECT model_version FROM clean.segment_in_use), (SELECT count(*) FROM clean.segment_dim);
SELECT * FROM clean.final_check ORDER BY check_order;

-- =====================================================================================
-- STEP 3 · The star schema: which table Power BI should hold, and its grain
-- (documentation you can paste into the user guide; nothing is created)
-- =====================================================================================
SELECT * FROM (VALUES
 ('Fact', 'clean_leads',            'one row per lead',        'calendar (created_day active, closed_date inactive), clean_customers, clean_agents'),
 ('Fact', 'clean_transactions',     'one row per deal',        'calendar (contract_date), clean_customers'),
 ('Fact', 'clean_payments',         'one row per payment',     'calendar (due_date), clean_customers'),
 ('Fact', 'region_views',           'customer x region',       'clean_customers'),
 ('Dimension', 'clean_customers',   'one row per customer',    'segments (1:1, both directions), session_summary, property_view_summary (1:1)'),
 ('Dimension', 'segments',          'one row per customer',    'segment_dim (many-to-one)'),
 ('Dimension', 'segment_dim',       'one row per segment',     'segments, segment_index, segment_channels, segment_actions'),
 ('Dimension', 'calendar',          'one row per day',         'facts above'),
 ('Dimension', 'clean_agents',      'one row per agent',       'clean_leads'),
 ('Helper (hidden)', 'powerbi_check, powerbi_check_week2, final_check, segment_check, kpi_definitions, segment_in_use', 'check / text tables', 'none')
) AS t(role, table_name, grain, related_to);
