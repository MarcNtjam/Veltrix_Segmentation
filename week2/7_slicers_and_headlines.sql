-- =====================================================================================
-- DAY 8 · What the wireframe and the slicers need: calendar, region, payments by customer,
--          and the numbers behind each page's one-line headline
-- Needs: Day 7. Run in pgAdmin on veltrix, ONE STEP AT A TIME.
-- =====================================================================================

-- =====================================================================================
-- STEP 1 · A calendar table for the Period slicer
-- One row per day, 1 Jan 2023 to 31 Dec 2028 (payments are scheduled up to Aug 2028).
-- period_12m groups days into 12-month periods ending 30 Sep, so "Last 12 months"
-- matches the KPI baselines exactly.
-- =====================================================================================
DROP TABLE IF EXISTS clean.calendar;
CREATE TABLE clean.calendar AS
SELECT d::DATE                                   AS date,
       date_trunc('month', d)::DATE              AS month_start,
       to_char(d, 'Mon YYYY')                    AS month_label,
       EXTRACT(YEAR FROM d)::INT                 AS year,
       EXTRACT(MONTH FROM d)::INT                AS month_no,
       'Q' || EXTRACT(QUARTER FROM d)::INT       AS quarter,
       CASE WHEN d >  DATE '2026-09-30' THEN 'After 30 Sep 2026 (scheduled only)'
            WHEN d >= DATE '2025-10-01' THEN 'Last 12 months (Oct 2025 - Sep 2026)'
            WHEN d >= DATE '2024-10-01' THEN 'Previous 12 months (Oct 2024 - Sep 2025)'
            WHEN d >= DATE '2023-10-01' THEN 'Oct 2023 - Sep 2024'
            ELSE 'Jan - Sep 2023' END            AS period_12m,
       CASE WHEN d >  DATE '2026-09-30' THEN 5
            WHEN d >= DATE '2025-10-01' THEN 1
            WHEN d >= DATE '2024-10-01' THEN 2
            WHEN d >= DATE '2023-10-01' THEN 3
            ELSE 4 END                           AS period_order,
       (d <= DATE '2026-09-30')                  AS is_in_data_window
FROM generate_series(DATE '2023-01-01', DATE '2028-12-31', INTERVAL '1 day') AS g(d);
ALTER TABLE clean.calendar ADD PRIMARY KEY (date);

SELECT period_12m, period_order, min(date), max(date), count(*) AS days
FROM clean.calendar GROUP BY 1, 2 ORDER BY 2;

-- =====================================================================================
-- STEP 2 · A Region field for the Region slicer: UK region of residence, or "Overseas"
-- =====================================================================================
ALTER TABLE clean.clean_customers ADD COLUMN IF NOT EXISTS region_label VARCHAR;
UPDATE clean.clean_customers
SET region_label = CASE WHEN is_overseas THEN 'Overseas'
                        ELSE coalesce(uk_region_of_residence, 'Unknown') END;

SELECT region_label, count(*) AS customers FROM clean.clean_customers GROUP BY 1 ORDER BY 2 DESC;

-- =====================================================================================
-- STEP 3 · Give payments their own customer_id
-- Why: with a Calendar table, Power BI cannot have two filter routes to payments
-- (Calendar -> payments AND Calendar -> transactions -> payments): "ambiguous paths".
-- With customer_id on payments, the model becomes a clean star:
--   Calendar -> leads / transactions / payments,  customers -> leads / transactions / payments.
-- The view keeps every old column and adds two at the end, so nothing in Power BI breaks.
-- =====================================================================================
CREATE OR REPLACE VIEW clean.clean_payments AS
SELECT p.*,
       CASE WHEN p.status IN ('Paid late', 'Overdue') THEN 1 ELSE 0 END AS is_late_or_overdue,
       t.customer_id,
       t.deal_kind
FROM raw.payments p
JOIN clean.clean_transactions t USING (transaction_id);

SELECT count(*) AS payments, count(customer_id) AS with_customer FROM clean.clean_payments;  -- 106,199 both

-- =====================================================================================
-- STEP 4 · Definitions for the chart tooltips (load this small table into Power BI)
-- =====================================================================================
DROP TABLE IF EXISTS clean.kpi_definitions;
CREATE TABLE clean.kpi_definitions (kpi VARCHAR PRIMARY KEY, definition VARCHAR, source VARCHAR);
INSERT INTO clean.kpi_definitions VALUES
 ('Customers', 'People or companies, counted once after merging duplicate records', 'clean_customers'),
 ('Leads', 'Enquiries created in the period; one customer can have several', 'clean_leads.created_day'),
 ('Conversion %', 'Won / (Won + Lost) leads, by the date the lead closed; open leads excluded', 'clean_leads.closed_date'),
 ('Deal value', 'Agreed price for sales; monthly rent x tenancy months for lettings; by contract date', 'clean_transactions.contract_date'),
 ('Median first reply', 'Median minutes from the first inbound contact to our reply, shown in hours', 'clean_leads.first_response_min'),
 ('Answered within 1 hour', 'Share of leads whose first reply came in under 60 minutes', 'clean_leads.first_response_min'),
 ('Open pipeline', 'Leads at New, Contacted, Qualified, Viewing or Offer on 30 Sep 2026', 'clean_leads.is_open'),
 ('Late payments %', '(Paid late + Overdue) / payments due; scheduled payments excluded; by due date', 'clean_payments.due_date'),
 ('Overdue now', 'Amount of payments still unpaid after their due date at 30 Sep 2026', 'clean_payments.status');
SELECT * FROM clean.kpi_definitions;

-- =====================================================================================
-- STEP 5 · Numbers for each page's one-line headline (phrase it as a finding)
-- =====================================================================================
-- Overview: conversion slipping while deal value grows
SELECT * FROM clean.powerbi_check ORDER BY card_order;
-- Pipeline: reply speed
SELECT * FROM eda.conversion_by_reply_band;
-- Payments: late rent vs sale
SELECT CASE WHEN payment_type = 'Monthly rent' THEN 'Monthly rent' ELSE 'Other payments' END AS grp,
       round(100.0 * avg(is_late_or_overdue), 1) AS late_pct
FROM clean.clean_payments WHERE status <> 'Scheduled' GROUP BY 1;
-- Segment deep dive (until segments exist): overseas night browsing and virtual tours
SELECT * FROM eda.night_share;

-- =====================================================================================
-- DAY 8 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · What single sentence should a manager remember from each page? (numbers above)
--   Overview: "Deal value is up 21% to £1,440m, but conversion slipped from 18.7% to 17.8%."
--   Pipeline: "Leads answered within an hour convert 4.2x as often, yet only 15.6% get that reply."
--   Payments: "Monthly rent is paid late 9.9% of the time, nearly 3x the rate on sale payments."
--   Segment deep dive: "Overseas customers do a quarter of their browsing between midnight and 6am UK time."

-- Q2 · Which slicers do users actually need, and which would add clutter?
-- A slicer is worth it when the groups are big enough to read and actually differ.
SELECT c.region_label, count(*) AS closed_leads,
       round(100.0 * avg(CASE WHEN l.converted THEN 1 ELSE 0 END), 1) AS conversion_pct,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY l.first_response_min) AS median_reply_min
FROM clean.clean_leads l JOIN clean.clean_customers c USING (customer_id)
WHERE l.is_closed = 1
GROUP BY 1 ORDER BY 3 DESC;
SELECT c.customer_type, count(*) AS closed_leads,
       round(100.0 * avg(CASE WHEN l.converted THEN 1 ELSE 0 END), 1) AS conversion_pct
FROM clean.clean_leads l JOIN clean.clean_customers c USING (customer_id)
WHERE l.is_closed = 1 GROUP BY 1 ORDER BY 2 DESC;

-- Q3 · Does the pipeline look different for buyers and renters?
SELECT intent, lead_stage, count(*) AS open_leads,
       round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY intent), 1) AS pct_of_intent_open
FROM clean.clean_leads WHERE is_open = 1
GROUP BY intent, lead_stage, stage_order ORDER BY intent, stage_order;
SELECT intent, count(*) FILTER (WHERE is_closed = 1) AS closed_leads,
       round(100.0 * avg(CASE WHEN converted THEN 1 ELSE 0 END) FILTER (WHERE is_closed = 1), 1) AS conversion_pct,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY closed_date - created_day) FILTER (WHERE converted) AS median_days_to_win,
       round(100.0 * avg(CASE WHEN first_response_min < 60 THEN 1 ELSE 0 END) FILTER (WHERE first_response_min IS NOT NULL), 1) AS pct_within_1h
FROM clean.clean_leads GROUP BY 1;

-- OWN QUESTION A · Which customer type has the lowest conversion? (answered by the Q2 query on customer_type)

-- OWN QUESTION B · Are open leads at the Offer stage being answered fast enough?
SELECT lead_stage, count(*) AS open_leads,
       round(100.0 * avg(CASE WHEN first_response_min < 60 THEN 1 ELSE 0 END) FILTER (WHERE first_response_min IS NOT NULL), 1) AS pct_within_1h,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_min) AS median_reply_min
FROM clean.clean_leads WHERE is_open = 1
GROUP BY lead_stage, stage_order ORDER BY stage_order;
