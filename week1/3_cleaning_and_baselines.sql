-- =====================================================================================
-- DAY 4 · Cleaning and customer deduplication, then the 12-month baselines
-- Needs: Day 2 (raw tables) and Day 3 (dq.customer_viewed_prices).
-- Run in pgAdmin: Query Tool on veltrix. Run ONE STEP AT A TIME (highlight, F5).
--
-- The raw.* tables are never edited. Everything cleaned goes into schema clean:
--   mapping tables  -> clean.lead_source_map, clean.country_map, clean.budget_fixes,
--                      clean.customer_merge_map, clean.dedupe_review_queue (look-alikes, STEP 11)
--   project lead    -> restricted.duplicate_key + dedupe scoring and the 95% gate (STEP 12)
--   cleaned tables  -> clean.clean_customers, clean_leads, clean_transactions,
--                      clean_web_sessions, clean_campaign_responses (copies, then UPDATE)
--   pass-through    -> clean.clean_* views for the 8 tables that need no fixing
-- Power BI reads clean.clean_* from today on.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS clean;

-- =====================================================================================
-- STEP 1 · CASE mapping table: 28 lead-source spellings -> 14 channels (+ channel group)
-- =====================================================================================
DROP TABLE IF EXISTS clean.lead_source_map;
CREATE TABLE clean.lead_source_map AS
SELECT raw_value,
       CASE
         WHEN raw_value IN ('Rightmove', 'Right Move', 'RightMove', 'rightmove')     THEN 'Rightmove'
         WHEN raw_value IN ('Zoopla', 'zoopla', 'Zoopla.co.uk')                      THEN 'Zoopla'
         WHEN raw_value IN ('OnTheMarket', 'On The Market', 'OTM')                   THEN 'OnTheMarket'
         WHEN raw_value IN ('Veltrix website', 'veltrix.co.uk', 'Website')           THEN 'Veltrix website'
         WHEN raw_value IN ('Google Ads', 'google ads', 'Google')                    THEN 'Google Ads'
         WHEN raw_value IN ('Facebook', 'FB')                                        THEN 'Facebook'
         WHEN raw_value IN ('Instagram', 'Insta')                                    THEN 'Instagram'
         WHEN raw_value IN ('Branch walk-in', 'Walk-in')                             THEN 'Branch walk-in'
         ELSE raw_value      -- TikTok, WeChat, Email newsletter, Referral, Overseas agent partner, Relocation partner
       END AS channel
FROM (SELECT DISTINCT lead_source AS raw_value FROM raw.leads) s;

ALTER TABLE clean.lead_source_map ADD PRIMARY KEY (raw_value), ADD COLUMN channel_group VARCHAR;
UPDATE clean.lead_source_map SET channel_group =
       CASE WHEN channel IN ('Rightmove', 'Zoopla', 'OnTheMarket')                      THEN 'Property portal'
            WHEN channel = 'Veltrix website'                                             THEN 'Website'
            WHEN channel = 'Google Ads'                                                  THEN 'Paid search'
            WHEN channel IN ('Facebook', 'Instagram', 'TikTok', 'WeChat')                THEN 'Paid social'
            WHEN channel = 'Email newsletter'                                            THEN 'Email'
            WHEN channel = 'Referral'                                                    THEN 'Referral'
            WHEN channel = 'Branch walk-in'                                              THEN 'Branch'
            WHEN channel IN ('Overseas agent partner', 'Relocation partner')             THEN 'Partner'
            ELSE 'CHECK ME' END;

-- Check: 28 rows, 14 channels, and no 'CHECK ME'
SELECT channel, channel_group, string_agg(raw_value, ' | ') AS spellings, count(*) AS n_spellings
FROM clean.lead_source_map GROUP BY 1, 2 ORDER BY 1;

-- =====================================================================================
-- STEP 2 · CASE mapping table: 26 country labels -> 12 countries with ISO codes
-- =====================================================================================
DROP TABLE IF EXISTS clean.country_map;
CREATE TABLE clean.country_map AS
SELECT raw_value,
       CASE
         WHEN raw_value IN ('United Kingdom', 'UK', 'U.K.', 'England', 'Great Britain') THEN 'United Kingdom'
         WHEN raw_value IN ('Hong Kong', 'HK', 'Hong Kong SAR')                        THEN 'Hong Kong'
         WHEN raw_value IN ('United Arab Emirates', 'UAE', 'U.A.E.')                   THEN 'United Arab Emirates'
         WHEN raw_value IN ('China', 'Mainland China', 'PRC')                          THEN 'China'
         WHEN raw_value IN ('United States', 'USA', 'US')                              THEN 'United States'
         WHEN raw_value IN ('Singapore', 'SG')                                         THEN 'Singapore'
         WHEN raw_value IN ('Saudi Arabia', 'KSA')                                     THEN 'Saudi Arabia'
         ELSE raw_value      -- India, Nigeria, Canada, Malaysia, Qatar
       END AS country
FROM (SELECT DISTINCT country_of_residence AS raw_value FROM raw.customers) s;

ALTER TABLE clean.country_map ADD PRIMARY KEY (raw_value), ADD COLUMN iso2 CHAR(2);
UPDATE clean.country_map SET iso2 =
       CASE country WHEN 'United Kingdom' THEN 'GB' WHEN 'Hong Kong' THEN 'HK' WHEN 'United Arab Emirates' THEN 'AE'
                    WHEN 'China' THEN 'CN' WHEN 'United States' THEN 'US' WHEN 'Singapore' THEN 'SG'
                    WHEN 'Saudi Arabia' THEN 'SA' WHEN 'India' THEN 'IN' WHEN 'Nigeria' THEN 'NG'
                    WHEN 'Canada' THEN 'CA' WHEN 'Malaysia' THEN 'MY' WHEN 'Qatar' THEN 'QA' END;

-- Check: 26 rows, 12 countries, no blank iso2
SELECT country, iso2, string_agg(raw_value, ' | ') AS labels, count(*) AS n_labels
FROM clean.country_map GROUP BY 1, 2 ORDER BY 1;

-- =====================================================================================
-- STEP 3 · Budget typo fixes (one row per corrected value, with the rule used)
-- Reference = median price / rent of the listings the customer viewed (dq.customer_viewed_prices, Day 3)
--   purchase budget < £5,000                         -> x1000  (typed in £k)
--   purchase budget >= 6x viewed prices (3+ views)   -> /10    (extra zero)
--   3-6x viewed, starts with 1, rest fits viewed     -> drop the first digit
--   rent >= 6x viewed (or >= £10k with no reference) -> /12 if a round annual figure, else /10
-- =====================================================================================
DROP TABLE IF EXISTS clean.budget_fixes;
CREATE TABLE clean.budget_fixes AS
WITH b AS (
    SELECT c.customer_id, c.stated_budget_gbp AS v, r.med_viewed_price AS ref, coalesce(r.n_sale_views, 0) AS n,
           c.stated_budget_gbp / nullif(r.med_viewed_price, 0) AS ratio,
           c.stated_budget_gbp - power(10, length(c.stated_budget_gbp::VARCHAR) - 1) AS stripped
    FROM raw.customers c LEFT JOIN dq.customer_viewed_prices r USING (customer_id)
    WHERE c.stated_budget_gbp IS NOT NULL
), sale AS (
    SELECT customer_id, 'stated_budget_gbp'::VARCHAR AS field, v AS raw_value, ref AS reference_value,
           CASE WHEN v < 5000                                                 THEN v * 1000.0
                WHEN n >= 3 AND ratio >= 6                                    THEN v / 10.0
                WHEN n >= 3 AND ratio BETWEEN 3 AND 6 AND v::VARCHAR LIKE '1%'
                     AND stripped / ref BETWEEN 0.6 AND 1.6                   THEN stripped END AS clean_value,
           CASE WHEN v < 5000                                                 THEN 'entered in thousands (x1000)'
                WHEN n >= 3 AND ratio >= 6                                    THEN 'extra zero (/10)'
                WHEN n >= 3 AND ratio BETWEEN 3 AND 6 AND v::VARCHAR LIKE '1%'
                     AND stripped / ref BETWEEN 0.6 AND 1.6                   THEN 'stray leading 1 (drop first digit)' END AS fix_rule
    FROM b
), r AS (
    SELECT c.customer_id, c.stated_rent_budget_pcm_gbp AS v, x.med_viewed_rent AS ref, coalesce(x.n_rent_views, 0) AS n,
           c.stated_rent_budget_pcm_gbp / nullif(x.med_viewed_rent, 0) AS ratio
    FROM raw.customers c LEFT JOIN dq.customer_viewed_prices x USING (customer_id)
    WHERE c.stated_rent_budget_pcm_gbp IS NOT NULL
), rent AS (
    SELECT customer_id, 'stated_rent_budget_pcm_gbp'::VARCHAR AS field, v AS raw_value, ref AS reference_value,
           CASE WHEN ((n >= 3 AND ratio >= 6) OR (n < 3 AND v >= 10000)) AND v % 12 = 0 AND (v / 12) % 25 = 0 THEN v / 12.0
                WHEN (n >= 3 AND ratio >= 6) OR (n < 3 AND v >= 10000)                  THEN v / 10.0 END AS clean_value,
           CASE WHEN ((n >= 3 AND ratio >= 6) OR (n < 3 AND v >= 10000)) AND v % 12 = 0 AND (v / 12) % 25 = 0 THEN 'annual figure (/12)'
                WHEN (n >= 3 AND ratio >= 6) OR (n < 3 AND v >= 10000)                  THEN 'extra zero (/10)' END AS fix_rule
    FROM r
)
SELECT customer_id, field, raw_value, reference_value, round(clean_value::NUMERIC)::BIGINT AS clean_value, fix_rule
FROM (SELECT * FROM sale UNION ALL SELECT * FROM rent) AS all_fixes
WHERE clean_value IS NOT NULL;

-- Check: 236 fixes (77 extra zero, 66 in £k, 43 stray 1; rent: 32 annual, 18 extra zero)
SELECT field, fix_rule, count(*) AS n FROM clean.budget_fixes GROUP BY 1, 2 ORDER BY 1, 3 DESC;

-- =====================================================================================
-- STEP 4 · Find duplicate customers with a SELF-JOIN
-- Two records are the same person if they share an email hash OR a phone hash.
-- The OLDEST record (created_at) survives as the master; the newer one is the duplicate.
-- =====================================================================================
DROP TABLE IF EXISTS clean.duplicate_pairs;
CREATE TABLE clean.duplicate_pairs AS
SELECT a.customer_id AS keep_id, a.created_at AS keep_created, b.customer_id AS duplicate_id, 'same email' AS matched_on
FROM raw.customers a
JOIN raw.customers b
  ON a.email_sha256 = b.email_sha256
 AND (a.created_at < b.created_at OR (a.created_at = b.created_at AND a.customer_id < b.customer_id))
UNION ALL
SELECT a.customer_id, a.created_at, b.customer_id, 'same phone'
FROM raw.customers a
JOIN raw.customers b
  ON a.phone_sha256 = b.phone_sha256
 AND (a.created_at < b.created_at OR (a.created_at = b.created_at AND a.customer_id < b.customer_id))
WHERE a.phone_sha256 IS NOT NULL;

-- Check: 1,103 email pairs and 726 phone pairs (some records match on both)
SELECT matched_on, count(*) AS pairs, count(DISTINCT duplicate_id) AS duplicate_records FROM clean.duplicate_pairs GROUP BY 1;

-- =====================================================================================
-- STEP 5 · The merge map: one row per raw customer record -> its surviving master
-- Start with everyone as their own master, then UPDATE the duplicates.
-- =====================================================================================
DROP TABLE IF EXISTS clean.customer_merge_map;
CREATE TABLE clean.customer_merge_map AS
SELECT customer_id, customer_id AS master_customer_id, 'own record'::VARCHAR AS matched_on
FROM raw.customers;
ALTER TABLE clean.customer_merge_map ADD PRIMARY KEY (customer_id);

-- 5a. Point each duplicate at the oldest record it matched     (expect UPDATE 1427)
UPDATE clean.customer_merge_map m
SET master_customer_id = p.keep_id, matched_on = p.matched_on
FROM (SELECT DISTINCT ON (duplicate_id) duplicate_id, keep_id, matched_on
      FROM clean.duplicate_pairs ORDER BY duplicate_id, keep_created, keep_id) p
WHERE m.customer_id = p.duplicate_id;

-- 5b. Chains: if A -> B and B -> C, point A straight at C.
--     Run until it says UPDATE 0 (on this data it is already 0 the first time).
UPDATE clean.customer_merge_map m
SET master_customer_id = m2.master_customer_id
FROM clean.customer_merge_map m2
WHERE m.master_customer_id = m2.customer_id AND m2.master_customer_id <> m2.customer_id;

ALTER TABLE clean.customer_merge_map ADD COLUMN is_master BOOLEAN;
UPDATE clean.customer_merge_map SET is_master = (customer_id = master_customer_id);

-- Check: 102,000 records -> 100,573 masters, 1,427 merged
SELECT count(*) AS raw_records, count(*) FILTER (WHERE is_master) AS customers_after_merge,
       count(*) FILTER (WHERE NOT is_master) AS records_merged
FROM clean.customer_merge_map;

-- =====================================================================================
-- STEP 6 · clean_customers: copy, standardise, fix, fill blanks, then keep masters only
-- =====================================================================================
DROP TABLE IF EXISTS clean.clean_customers CASCADE;
CREATE TABLE clean.clean_customers AS SELECT * FROM raw.customers;

-- 6a. Standard country + ISO code (keep the raw label for audit)
ALTER TABLE clean.clean_customers ADD COLUMN country_of_residence_raw VARCHAR, ADD COLUMN country_iso2 CHAR(2);
UPDATE clean.clean_customers c
SET country_of_residence_raw = c.country_of_residence,
    country_of_residence     = m.country,
    country_iso2             = m.iso2
FROM clean.country_map m WHERE m.raw_value = c.country_of_residence;

-- 6b. Budget typos
ALTER TABLE clean.clean_customers ADD COLUMN budget_fixed INT DEFAULT 0;
UPDATE clean.clean_customers c SET stated_budget_gbp = f.clean_value, budget_fixed = 1
FROM clean.budget_fixes f WHERE f.customer_id = c.customer_id AND f.field = 'stated_budget_gbp';
UPDATE clean.clean_customers c SET stated_rent_budget_pcm_gbp = f.clean_value, budget_fixed = 1
FROM clean.budget_fixes f WHERE f.customer_id = c.customer_id AND f.field = 'stated_rent_budget_pcm_gbp';

-- 6c. One label for "no answer" on gender
UPDATE clean.clean_customers SET gender = 'Not stated' WHERE gender IS NULL;

-- 6d. Fill blanks on the master from its duplicates; keep the earliest first contact
ALTER TABLE clean.clean_customers ADD COLUMN n_source_records INT, ADD COLUMN was_merged INT;
UPDATE clean.clean_customers c
SET age_band                   = coalesce(c.age_band, g.age_band),
    occupation_sector          = coalesce(c.occupation_sector, g.occupation_sector),
    uk_region_of_residence     = coalesce(c.uk_region_of_residence, g.uk_region),
    stated_budget_gbp          = coalesce(c.stated_budget_gbp, g.budget),
    stated_rent_budget_pcm_gbp = coalesce(c.stated_rent_budget_pcm_gbp, g.rent_budget),
    first_contact_date         = g.first_contact_date,
    consent_marketing          = g.consent_marketing,
    budget_fixed               = g.budget_fixed,
    n_source_records           = g.n_records,
    was_merged                 = CASE WHEN g.n_records > 1 THEN 1 ELSE 0 END
FROM (SELECT m.master_customer_id, count(*) AS n_records,
             min(x.age_band) AS age_band, min(x.occupation_sector) AS occupation_sector,
             min(x.uk_region_of_residence) AS uk_region, min(x.stated_budget_gbp) AS budget,
             min(x.stated_rent_budget_pcm_gbp) AS rent_budget, min(x.first_contact_date) AS first_contact_date,
             bool_and(x.consent_marketing) AS consent_marketing, max(x.budget_fixed) AS budget_fixed
      FROM clean.clean_customers x JOIN clean.customer_merge_map m USING (customer_id)
      GROUP BY m.master_customer_id) g
WHERE c.customer_id = g.master_customer_id;

-- 6e. Remove the merged duplicates (their history is re-pointed in step 7)  (expect DELETE 1427)
DELETE FROM clean.clean_customers c
USING clean.customer_merge_map m
WHERE m.customer_id = c.customer_id AND NOT m.is_master;

ALTER TABLE clean.clean_customers ADD PRIMARY KEY (customer_id);
SELECT count(*) AS clean_customers, sum(was_merged) AS customers_with_merged_records FROM clean.clean_customers;

-- =====================================================================================
-- STEP 7 · Re-point leads, sessions, responses and transactions to the surviving customer_id
-- Copy each table, keep the original id in source_customer_id, then UPDATE via the merge map.
-- =====================================================================================

-- 7a. Leads (+ clean channel, open/closed flags, first reply time and band)
DROP TABLE IF EXISTS clean.clean_leads CASCADE;
CREATE TABLE clean.clean_leads AS SELECT * FROM raw.leads;
ALTER TABLE clean.clean_leads ADD PRIMARY KEY (lead_id),
      ADD COLUMN source_customer_id VARCHAR, ADD COLUMN lead_source_raw VARCHAR, ADD COLUMN channel_group VARCHAR;
UPDATE clean.clean_leads SET source_customer_id = customer_id, lead_source_raw = lead_source;

UPDATE clean.clean_leads l SET customer_id = m.master_customer_id        -- expect UPDATE 1407
FROM clean.customer_merge_map m
WHERE m.customer_id = l.customer_id AND NOT m.is_master;

UPDATE clean.clean_leads l SET lead_source = s.channel, channel_group = s.channel_group
FROM clean.lead_source_map s WHERE s.raw_value = l.lead_source_raw;

ALTER TABLE clean.clean_leads
      ADD COLUMN created_day DATE, ADD COLUMN is_open INT, ADD COLUMN is_closed INT,
      ADD COLUMN first_response_min DOUBLE PRECISION, ADD COLUMN first_reply_band VARCHAR;
UPDATE clean.clean_leads
SET created_day = created_date::DATE,
    is_open     = CASE WHEN lead_stage IN ('New', 'Contacted', 'Qualified', 'Viewing', 'Offer') THEN 1 ELSE 0 END,
    is_closed   = CASE WHEN lead_stage IN ('Won', 'Lost') THEN 1 ELSE 0 END;

-- First reply = response time on the lead's FIRST inbound contact
UPDATE clean.clean_leads l SET first_response_min = r.first_response_min
FROM (SELECT i.lead_id, min(i.response_time_min) AS first_response_min
      FROM raw.interactions i
      JOIN (SELECT lead_id, min(interaction_time) AS t FROM raw.interactions
            WHERE direction = 'Inbound' GROUP BY lead_id) f
        ON f.lead_id = i.lead_id AND f.t = i.interaction_time
      WHERE i.direction = 'Inbound'
      GROUP BY i.lead_id) r
WHERE r.lead_id = l.lead_id;

UPDATE clean.clean_leads SET first_reply_band =
       CASE WHEN first_response_min IS NULL  THEN 'Unknown'
            WHEN first_response_min <  60    THEN '1. Under 1 hour'
            WHEN first_response_min <  240   THEN '2. 1-4 hours'
            WHEN first_response_min <= 1440  THEN '3. 4-24 hours'
            ELSE '4. Over 24 hours' END;

-- 7b. Web sessions (anonymous sessions stay NULL) + night / anonymous flags
DROP TABLE IF EXISTS clean.clean_web_sessions CASCADE;
CREATE TABLE clean.clean_web_sessions AS SELECT * FROM raw.web_sessions;
ALTER TABLE clean.clean_web_sessions ADD PRIMARY KEY (session_id), ADD COLUMN source_customer_id VARCHAR;
UPDATE clean.clean_web_sessions SET source_customer_id = customer_id;
UPDATE clean.clean_web_sessions w SET customer_id = m.master_customer_id
FROM clean.customer_merge_map m
WHERE m.customer_id = w.customer_id AND NOT m.is_master;
ALTER TABLE clean.clean_web_sessions
      ADD COLUMN session_day DATE, ADD COLUMN session_hour_uk INT,
      ADD COLUMN is_night_session INT, ADD COLUMN is_anonymous INT;
UPDATE clean.clean_web_sessions
SET session_day      = session_start::DATE,
    session_hour_uk  = EXTRACT(HOUR FROM session_start),
    is_night_session = CASE WHEN EXTRACT(HOUR FROM session_start) < 6 THEN 1 ELSE 0 END,
    is_anonymous     = CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END;

-- 7c. Campaign responses
DROP TABLE IF EXISTS clean.clean_campaign_responses CASCADE;
CREATE TABLE clean.clean_campaign_responses AS SELECT * FROM raw.campaign_responses;
ALTER TABLE clean.clean_campaign_responses ADD PRIMARY KEY (response_id), ADD COLUMN source_customer_id VARCHAR;
UPDATE clean.clean_campaign_responses SET source_customer_id = customer_id;
UPDATE clean.clean_campaign_responses r SET customer_id = m.master_customer_id
FROM clean.customer_merge_map m
WHERE m.customer_id = r.customer_id AND NOT m.is_master;

-- 7d. Transactions (+ deal kind and deal value as defined in the KPI dictionary)
DROP TABLE IF EXISTS clean.clean_transactions CASCADE;
CREATE TABLE clean.clean_transactions AS SELECT * FROM raw.transactions;
ALTER TABLE clean.clean_transactions ADD PRIMARY KEY (transaction_id), ADD COLUMN source_customer_id VARCHAR;
UPDATE clean.clean_transactions SET source_customer_id = customer_id;
UPDATE clean.clean_transactions t SET customer_id = m.master_customer_id
FROM clean.customer_merge_map m
WHERE m.customer_id = t.customer_id AND NOT m.is_master;
ALTER TABLE clean.clean_transactions ADD COLUMN deal_kind VARCHAR, ADD COLUMN deal_value_gbp DOUBLE PRECISION;
UPDATE clean.clean_transactions
SET deal_kind      = CASE WHEN transaction_type IN ('Assured shorthold tenancy', 'Company let') THEN 'Letting' ELSE 'Sale' END,
    finance_type   = coalesce(finance_type, CASE WHEN transaction_type = 'Assured shorthold tenancy' THEN 'Renting' END),
    -- deal value = agreed price for sales, monthly rent x tenancy months for lettings
    deal_value_gbp = coalesce(agreed_price_gbp, agreed_rent_pcm_gbp * tenancy_months);

-- 7e. The 8 tables that need no fixing: views with the clean_ name so Power BI sees one set
CREATE OR REPLACE VIEW clean.clean_payments AS
SELECT p.*, CASE WHEN p.status IN ('Paid late', 'Overdue') THEN 1 ELSE 0 END AS is_late_or_overdue FROM raw.payments p;
CREATE OR REPLACE VIEW clean.clean_interactions   AS SELECT * FROM raw.interactions;
CREATE OR REPLACE VIEW clean.clean_site_visits    AS SELECT * FROM raw.site_visits;
CREATE OR REPLACE VIEW clean.clean_properties     AS SELECT * FROM raw.properties;
CREATE OR REPLACE VIEW clean.clean_agents         AS SELECT * FROM raw.agents;
CREATE OR REPLACE VIEW clean.clean_locations      AS SELECT * FROM raw.locations;
CREATE OR REPLACE VIEW clean.clean_campaigns      AS SELECT * FROM raw.campaigns;
CREATE OR REPLACE VIEW clean.clean_property_views AS SELECT * FROM raw.property_views;

-- 7f. Foreign keys on the cleaned tables: if any re-pointing failed, these would error
ALTER TABLE clean.clean_leads              ADD CONSTRAINT fk_cl_customer FOREIGN KEY (customer_id) REFERENCES clean.clean_customers (customer_id);
ALTER TABLE clean.clean_transactions       ADD CONSTRAINT fk_ct_customer FOREIGN KEY (customer_id) REFERENCES clean.clean_customers (customer_id);
ALTER TABLE clean.clean_transactions       ADD CONSTRAINT fk_ct_lead     FOREIGN KEY (lead_id)     REFERENCES clean.clean_leads (lead_id);
ALTER TABLE clean.clean_web_sessions       ADD CONSTRAINT fk_cw_customer FOREIGN KEY (customer_id) REFERENCES clean.clean_customers (customer_id);
ALTER TABLE clean.clean_campaign_responses ADD CONSTRAINT fk_cr_customer FOREIGN KEY (customer_id) REFERENCES clean.clean_customers (customer_id);
CREATE INDEX ON clean.clean_leads (customer_id);
CREATE INDEX ON clean.clean_leads (agent_id);
CREATE INDEX ON clean.clean_web_sessions (customer_id);
CREATE INDEX ON clean.clean_transactions (customer_id);
ANALYZE clean.clean_customers; ANALYZE clean.clean_leads; ANALYZE clean.clean_web_sessions;
ANALYZE clean.clean_transactions; ANALYZE clean.clean_campaign_responses;

-- Row counts of the cleaned database (screenshot this for the Day 4 output)
SELECT 'clean_customers' AS table_name, count(*) AS rows FROM clean.clean_customers UNION ALL
SELECT 'clean_leads', count(*) FROM clean.clean_leads UNION ALL
SELECT 'clean_transactions', count(*) FROM clean.clean_transactions UNION ALL
SELECT 'clean_web_sessions', count(*) FROM clean.clean_web_sessions UNION ALL
SELECT 'clean_campaign_responses', count(*) FROM clean.clean_campaign_responses UNION ALL
SELECT 'clean_payments', count(*) FROM clean.clean_payments;

-- =====================================================================================
-- STEP 8 · Re-run the Day 3 checks on the cleaned tables (raw vs clean side by side)
-- Every "clean" number should be 0, except the expected blanks.
-- =====================================================================================
DROP TABLE IF EXISTS dq.recheck_after_cleaning;
CREATE TABLE dq.recheck_after_cleaning AS
SELECT 'Customer records sharing an email hash' AS check_name,
       (SELECT count(*) FROM (SELECT count(*) OVER (PARTITION BY email_sha256) n FROM raw.customers) x WHERE n > 1)   AS raw_rows,
       (SELECT count(*) FROM (SELECT count(*) OVER (PARTITION BY email_sha256) n FROM clean.clean_customers) x WHERE n > 1) AS clean_rows
UNION ALL SELECT 'Customer records sharing a phone hash',
       (SELECT count(*) FROM (SELECT phone_sha256, count(*) OVER (PARTITION BY phone_sha256) n FROM raw.customers) x WHERE n > 1 AND phone_sha256 IS NOT NULL),
       (SELECT count(*) FROM (SELECT phone_sha256, count(*) OVER (PARTITION BY phone_sha256) n FROM clean.clean_customers) x WHERE n > 1 AND phone_sha256 IS NOT NULL)
UNION ALL SELECT 'Leads pointing at a merged (non-surviving) customer',
       (SELECT count(*) FROM raw.leads l JOIN clean.customer_merge_map m USING (customer_id) WHERE NOT m.is_master),
       (SELECT count(*) FROM clean.clean_leads l LEFT JOIN clean.clean_customers c USING (customer_id) WHERE c.customer_id IS NULL)
UNION ALL SELECT 'Sessions pointing at a merged customer',
       (SELECT count(*) FROM raw.web_sessions w JOIN clean.customer_merge_map m USING (customer_id) WHERE NOT m.is_master),
       (SELECT count(*) FROM clean.clean_web_sessions w LEFT JOIN clean.clean_customers c USING (customer_id) WHERE w.customer_id IS NOT NULL AND c.customer_id IS NULL)
UNION ALL SELECT 'Campaign responses pointing at a merged customer',
       (SELECT count(*) FROM raw.campaign_responses r JOIN clean.customer_merge_map m USING (customer_id) WHERE NOT m.is_master),
       (SELECT count(*) FROM clean.clean_campaign_responses r LEFT JOIN clean.clean_customers c USING (customer_id) WHERE c.customer_id IS NULL)
UNION ALL SELECT 'Transactions pointing at a merged customer',
       (SELECT count(*) FROM raw.transactions t JOIN clean.customer_merge_map m USING (customer_id) WHERE NOT m.is_master),
       (SELECT count(*) FROM clean.clean_transactions t LEFT JOIN clean.clean_customers c USING (customer_id) WHERE c.customer_id IS NULL)
UNION ALL SELECT 'Leads with a non-standard lead source',
       (SELECT count(*) FROM raw.leads l JOIN clean.lead_source_map s ON s.raw_value = l.lead_source WHERE s.raw_value <> s.channel),
       (SELECT count(*) FROM clean.clean_leads WHERE lead_source NOT IN (SELECT DISTINCT channel FROM clean.lead_source_map) OR channel_group IS NULL)
UNION ALL SELECT 'Customers with a non-standard country label',
       (SELECT count(*) FROM raw.customers c JOIN clean.country_map m ON m.raw_value = c.country_of_residence WHERE m.raw_value <> m.country),
       (SELECT count(*) FROM clean.clean_customers WHERE country_iso2 IS NULL OR country_of_residence NOT IN (SELECT DISTINCT country FROM clean.country_map))
UNION ALL SELECT 'Purchase budget under £5,000',
       (SELECT count(*) FROM raw.customers WHERE stated_budget_gbp < 5000),
       (SELECT count(*) FROM clean.clean_customers WHERE stated_budget_gbp < 5000)
UNION ALL SELECT 'Purchase budget 6x+ the prices viewed',
       (SELECT count(*) FROM raw.customers c JOIN dq.customer_viewed_prices v USING (customer_id) WHERE v.n_sale_views >= 3 AND c.stated_budget_gbp >= 6 * v.med_viewed_price),
       (SELECT count(*) FROM clean.clean_customers c JOIN dq.customer_viewed_prices v USING (customer_id) WHERE v.n_sale_views >= 3 AND c.stated_budget_gbp >= 6 * v.med_viewed_price)
UNION ALL SELECT 'Rent budget £10,000+ a month',
       (SELECT count(*) FROM raw.customers WHERE stated_rent_budget_pcm_gbp >= 10000),
       (SELECT count(*) FROM clean.clean_customers WHERE stated_rent_budget_pcm_gbp >= 10000)
UNION ALL SELECT 'Gender left blank',
       (SELECT count(*) FROM raw.customers WHERE gender IS NULL),
       (SELECT count(*) FROM clean.clean_customers WHERE gender IS NULL);
SELECT * FROM dq.recheck_after_cleaning;

-- =====================================================================================
-- STEP 9 · 12-month baselines (1 Oct 2025 - 30 Sep 2026): the "before" numbers for the project
-- =====================================================================================
DROP TABLE IF EXISTS clean.kpi_baselines;
CREATE TABLE clean.kpi_baselines AS
WITH closed  AS (SELECT * FROM clean.clean_leads WHERE is_closed = 1 AND closed_date BETWEEN '2025-10-01' AND '2026-09-30'),
     created AS (SELECT * FROM clean.clean_leads WHERE created_day BETWEEN '2025-10-01' AND '2026-09-30'),
     spend   AS (SELECT sum(spend_gbp) AS s FROM raw.campaigns WHERE start_date BETWEEN '2025-10-01' AND '2026-09-30'),
     camp    AS (SELECT count(*) AS n FROM created WHERE campaign_id IS NOT NULL)
SELECT 1 AS kpi_order, 'Lead-to-sale conversion (buy leads), %' AS kpi,
       round(100.0 * (SELECT avg(CASE WHEN converted THEN 1 ELSE 0 END) FROM closed WHERE intent = 'Buy'), 2) AS value,
       'Won / (Won + Lost), buy leads closed in the 12 months' AS definition
UNION ALL SELECT 2, 'Lead-to-deal conversion (all leads), %',
       round(100.0 * (SELECT avg(CASE WHEN converted THEN 1 ELSE 0 END) FROM closed), 2),
       'Won / (Won + Lost), all leads closed in the 12 months'
UNION ALL SELECT 3, 'Median first reply, hours',
       round(((SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_min) FROM created) / 60.0)::NUMERIC, 2),
       'Reply time on the first inbound contact, leads created in the 12 months'
UNION ALL SELECT 4, 'Leads answered within 1 hour, %',
       round(100.0 * (SELECT avg(CASE WHEN first_response_min < 60 THEN 1 ELSE 0 END) FROM created WHERE first_response_min IS NOT NULL), 2),
       'Share of leads with a first reply under 60 minutes'
UNION ALL SELECT 5, 'Median days to close (won leads)',
       (SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY closed_date - created_day) FROM closed WHERE converted)::NUMERIC,
       'Lead created to lead closed, won leads'
UNION ALL SELECT 6, 'Cost per campaign lead, £',
       round(((SELECT s FROM spend) / (SELECT n FROM camp))::NUMERIC, 2),
       'Spend of campaigns starting in the 12 months / leads with a campaign_id'
UNION ALL SELECT 7, 'Campaign spend, £', round((SELECT s FROM spend)::NUMERIC, 2), 'Campaigns starting in the 12 months'
UNION ALL SELECT 8, 'Campaign-attributed leads', (SELECT n FROM camp), 'Leads created in the 12 months with a campaign_id';
SELECT * FROM clean.kpi_baselines ORDER BY kpi_order;

-- =====================================================================================
-- STEP 10 · The numbers the 6 Overview KPI cards must show (Power BI reconciliation)
-- Load this table into Power BI too and put it next to your measures on the Data check page.
-- =====================================================================================
DROP TABLE IF EXISTS clean.powerbi_check;
CREATE TABLE clean.powerbi_check AS
WITH w AS (SELECT DATE '2025-10-01' AS s, DATE '2026-09-30' AS e)
SELECT 1 AS card_order, 'Customers' AS measure, (SELECT count(*) FROM clean.clean_customers)::NUMERIC AS sql_value,
       'all time, after merging duplicates' AS filter_used
UNION ALL SELECT 2, 'Leads (12 months)', (SELECT count(*) FROM clean.clean_leads, w WHERE created_day BETWEEN s AND e), 'created_day Oct 2025 - Sep 2026'
UNION ALL SELECT 3, 'Conversion % (12 months)',
       (SELECT round(100.0 * avg(CASE WHEN converted THEN 1 ELSE 0 END), 2) FROM clean.clean_leads, w WHERE is_closed = 1 AND closed_date BETWEEN s AND e), 'closed_date Oct 2025 - Sep 2026'
UNION ALL SELECT 4, 'Deal value £m (12 months)',
       (SELECT round((sum(deal_value_gbp) / 1e6)::NUMERIC, 1) FROM clean.clean_transactions, w WHERE contract_date BETWEEN s AND e), 'contract_date Oct 2025 - Sep 2026'
UNION ALL SELECT 5, 'Median first reply h (12 months)',
       (SELECT round((percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_min) / 60.0)::NUMERIC, 2) FROM clean.clean_leads, w WHERE created_day BETWEEN s AND e), 'created_day Oct 2025 - Sep 2026'
UNION ALL SELECT 6, 'Late payments % (12 months)',
       (SELECT round(100.0 * avg(is_late_or_overdue), 2) FROM clean.clean_payments, w WHERE status <> 'Scheduled' AND due_date BETWEEN s AND e), 'due_date Oct 2025 - Sep 2026, excl. Scheduled'
UNION ALL SELECT 7, 'Open pipeline (leads)', (SELECT count(*) FROM clean.clean_leads WHERE is_open = 1), 'at 30 Sep 2026'
UNION ALL SELECT 8, 'Leads (all time)', (SELECT count(*) FROM clean.clean_leads), 'no filter'
UNION ALL SELECT 9, 'Conversion % (all time)',
       (SELECT round(100.0 * avg(CASE WHEN converted THEN 1 ELSE 0 END), 2) FROM clean.clean_leads WHERE is_closed = 1), 'no filter';
SELECT * FROM clean.powerbi_check ORDER BY card_order;

-- =====================================================================================
-- STEP 11 · Profile look-alikes: queue them for MANUAL REVIEW (they are NOT merged here)
-- About 45% of true duplicates share neither the email nor the phone hash, so STEP 4-5
-- cannot find them. They can only be found from their answers, which differ slightly.
-- Method: Fellegi-Sunter match weights (standard record linkage, no labels needed)
--   * candidate pairs: same customer type, intent, country and UK region, and the newer
--     record has exactly one lead (a re-enquiry that created a new record)
--   * each field adds log2(m/u) when the two records agree and log2((1-m)/(1-u)) when they
--     disagree; u = chance two random customers agree (from the data), m = 0.85
--   * so agreeing on a rare value (an exact budget) counts far more than on a common one
-- The top 1,000 pairs go into clean.dedupe_review_queue; reviewers work from rank 1.
-- Runtime: the self-join scores ~90M candidate pairs: allow 5-15 minutes on a laptop.
-- =====================================================================================
-- 11a. One row per surviving customer, with the fields we compare (fixed budgets, clean country)
DROP TABLE IF EXISTS clean.lookalike_base;
CREATE TABLE clean.lookalike_base AS
SELECT c.customer_id, c.customer_type, c.primary_intent, cm.country AS country_clean,
       c.uk_region_of_residence AS region, c.buyer_position, c.finance_type, c.age_band,
       c.occupation_sector AS occupation, nullif(c.gender, 'Not stated') AS gender,
       coalesce(bs.clean_value, c.stated_budget_gbp)          AS budget,
       coalesce(br.clean_value, c.stated_rent_budget_pcm_gbp) AS rent,
       c.preferred_currency AS currency, c.first_contact_date, c.created_at,
       coalesce(lc.n_leads, 0) AS n_leads
FROM raw.customers c
JOIN clean.country_map cm         ON cm.raw_value = c.country_of_residence
JOIN clean.customer_merge_map mm  ON mm.customer_id = c.customer_id
LEFT JOIN clean.budget_fixes bs   ON bs.customer_id = c.customer_id AND bs.field = 'stated_budget_gbp'
LEFT JOIN clean.budget_fixes br   ON br.customer_id = c.customer_id AND br.field = 'stated_rent_budget_pcm_gbp'
LEFT JOIN (SELECT m2.master_customer_id AS customer_id, count(*) AS n_leads
           FROM raw.leads l JOIN clean.customer_merge_map m2 USING (customer_id) GROUP BY 1) lc
       ON lc.customer_id = c.customer_id
WHERE mm.is_master;
CREATE INDEX ON clean.lookalike_base (customer_type, primary_intent, country_clean, region);
ANALYZE clean.lookalike_base;

-- 11b. Match weights per field, computed from how common each value is (no answer key)
DROP TABLE IF EXISTS clean.lookalike_weights;
CREATE TABLE clean.lookalike_weights AS
WITH f AS (   -- u = probability two random customers share a value = sum of squared shares
    SELECT 'region' AS field, sum(p * p) AS u FROM (SELECT count(*)::numeric / sum(count(*)) OVER () AS p FROM clean.lookalike_base WHERE region IS NOT NULL GROUP BY region) s
    UNION ALL SELECT 'buyer_position', sum(p * p) FROM (SELECT count(*)::numeric / sum(count(*)) OVER () AS p FROM clean.lookalike_base WHERE buyer_position IS NOT NULL GROUP BY buyer_position) s
    UNION ALL SELECT 'finance_type', sum(p * p) FROM (SELECT count(*)::numeric / sum(count(*)) OVER () AS p FROM clean.lookalike_base WHERE finance_type IS NOT NULL GROUP BY finance_type) s
    UNION ALL SELECT 'age_band', sum(p * p) FROM (SELECT count(*)::numeric / sum(count(*)) OVER () AS p FROM clean.lookalike_base WHERE age_band IS NOT NULL GROUP BY age_band) s
    UNION ALL SELECT 'occupation', sum(p * p) FROM (SELECT count(*)::numeric / sum(count(*)) OVER () AS p FROM clean.lookalike_base WHERE occupation IS NOT NULL GROUP BY occupation) s
    UNION ALL SELECT 'gender', sum(p * p) FROM (SELECT count(*)::numeric / sum(count(*)) OVER () AS p FROM clean.lookalike_base WHERE gender IS NOT NULL GROUP BY gender) s
    UNION ALL SELECT 'budget', sum(p * p) FROM (SELECT count(*)::numeric / sum(count(*)) OVER () AS p FROM clean.lookalike_base WHERE budget IS NOT NULL GROUP BY budget) s
    UNION ALL SELECT 'rent', sum(p * p) FROM (SELECT count(*)::numeric / sum(count(*)) OVER () AS p FROM clean.lookalike_base WHERE rent IS NOT NULL GROUP BY rent) s
    UNION ALL SELECT 'currency', sum(p * p) FROM (SELECT count(*)::numeric / sum(count(*)) OVER () AS p FROM clean.lookalike_base WHERE currency IS NOT NULL GROUP BY currency) s
)
SELECT field, round(u, 6) AS u,
       round(ln(0.85 / u) / ln(2.0), 3)       AS agree_weight,
       round(ln(0.15 / (1 - u)) / ln(2.0), 3) AS disagree_weight
FROM f;
SELECT * FROM clean.lookalike_weights ORDER BY agree_weight DESC;   -- budget and rent weigh most

-- 11c. Score every candidate pair; keep the 1,000 strongest for review
DROP TABLE IF EXISTS clean.dedupe_review_queue CASCADE;
CREATE TABLE clean.dedupe_review_queue AS
WITH w AS (SELECT field, agree_weight AS aw, disagree_weight AS dw FROM clean.lookalike_weights),
pairs AS (
    SELECT a.customer_id AS customer_id_a, b.customer_id AS customer_id_b,
           a.customer_type, a.primary_intent, a.country_clean, a.region,
           abs(a.first_contact_date - b.first_contact_date) AS days_apart,
           -- region always agrees (it is a blocking field), so it is not scored
             CASE WHEN a.buyer_position IS NULL OR b.buyer_position IS NULL THEN 0 WHEN a.buyer_position = b.buyer_position
                  THEN (SELECT aw FROM w WHERE field = 'buyer_position') ELSE (SELECT dw FROM w WHERE field = 'buyer_position') END
           + CASE WHEN a.finance_type IS NULL OR b.finance_type IS NULL THEN 0 WHEN a.finance_type = b.finance_type
                  THEN (SELECT aw FROM w WHERE field = 'finance_type') ELSE (SELECT dw FROM w WHERE field = 'finance_type') END
           + CASE WHEN a.age_band IS NULL OR b.age_band IS NULL THEN 0 WHEN a.age_band = b.age_band
                  THEN (SELECT aw FROM w WHERE field = 'age_band') ELSE (SELECT dw FROM w WHERE field = 'age_band') END
           + CASE WHEN a.occupation IS NULL OR b.occupation IS NULL THEN 0 WHEN a.occupation = b.occupation
                  THEN (SELECT aw FROM w WHERE field = 'occupation') ELSE (SELECT dw FROM w WHERE field = 'occupation') END
           + CASE WHEN a.gender IS NULL OR b.gender IS NULL THEN 0 WHEN a.gender = b.gender
                  THEN (SELECT aw FROM w WHERE field = 'gender') ELSE (SELECT dw FROM w WHERE field = 'gender') END
           + CASE WHEN a.budget IS NULL OR b.budget IS NULL THEN 0 WHEN a.budget = b.budget
                  THEN (SELECT aw FROM w WHERE field = 'budget') ELSE (SELECT dw FROM w WHERE field = 'budget') END
           + CASE WHEN a.rent IS NULL OR b.rent IS NULL THEN 0 WHEN a.rent = b.rent
                  THEN (SELECT aw FROM w WHERE field = 'rent') ELSE (SELECT dw FROM w WHERE field = 'rent') END
           + CASE WHEN a.currency IS NULL OR b.currency IS NULL THEN 0 WHEN a.currency = b.currency
                  THEN (SELECT aw FROM w WHERE field = 'currency') ELSE (SELECT dw FROM w WHERE field = 'currency') END
           + CASE WHEN abs(a.first_contact_date - b.first_contact_date) <= 30 THEN 2 ELSE 0 END AS match_weight
    FROM clean.lookalike_base a
    JOIN clean.lookalike_base b
      ON  a.customer_type = b.customer_type AND a.primary_intent = b.primary_intent
      AND a.country_clean = b.country_clean AND coalesce(a.region, '?') = coalesce(b.region, '?')
      AND (b.created_at > a.created_at OR (b.created_at = a.created_at AND b.customer_id > a.customer_id))
      AND b.n_leads = 1
)
SELECT row_number() OVER (ORDER BY match_weight DESC, customer_id_a, customer_id_b)::int AS queue_rank,
       customer_id_a, customer_id_b, customer_type, primary_intent, country_clean, region,
       days_apart, round(match_weight, 2) AS match_weight, 'pending'::varchar AS review_decision
FROM pairs
WHERE match_weight >= 15
ORDER BY match_weight DESC, customer_id_a, customer_id_b
LIMIT 1000;
ALTER TABLE clean.dedupe_review_queue ADD PRIMARY KEY (queue_rank);

-- Check: 1,000 pairs queued, all 'pending'
SELECT count(*) AS pairs_queued, min(match_weight) AS lowest_weight, max(match_weight) AS highest_weight,
       count(*) FILTER (WHERE review_decision = 'pending') AS pending
FROM clean.dedupe_review_queue;

-- 11d. The reviewer's screen: both profiles side by side, strongest pairs first
SELECT q.queue_rank, q.match_weight, q.days_apart,
       a.customer_id AS id_a, b.customer_id AS id_b,
       a.buyer_position AS position_a, b.buyer_position AS position_b,
       a.age_band AS age_a, b.age_band AS age_b,
       a.occupation_sector AS occupation_a, b.occupation_sector AS occupation_b,
       a.stated_budget_gbp AS budget_a, b.stated_budget_gbp AS budget_b,
       a.stated_rent_budget_pcm_gbp AS rent_a, b.stated_rent_budget_pcm_gbp AS rent_b
FROM clean.dedupe_review_queue q
JOIN raw.customers a ON a.customer_id = q.customer_id_a
JOIN raw.customers b ON b.customer_id = q.customer_id_b
ORDER BY q.queue_rank LIMIT 25;

-- 11e. Reviewers record their decisions (examples, do not run as they are):
-- UPDATE clean.dedupe_review_queue SET review_decision = 'accept' WHERE queue_rank IN (1, 4, 7);
-- UPDATE clean.dedupe_review_queue SET review_decision = 'reject' WHERE queue_rank IN (2, 3);
-- Accepted pairs are merged only AFTER review, then STEP 6 onward is re-run:
-- UPDATE clean.customer_merge_map m SET master_customer_id = q.customer_id_a, matched_on = 'manual review', is_master = false
-- FROM clean.dedupe_review_queue q WHERE q.review_decision = 'accept' AND m.customer_id = q.customer_id_b;

-- =====================================================================================
-- STEP 12 · Score the de-duplication against duplicate_of        *** PROJECT LEAD ONLY ***
-- Run once the merge rules (STEP 4-5) and the queue (STEP 11) are frozen.
-- Load ONLY customer_id and duplicate_of from the answer key, never true_persona, so the
-- segmentation stays blind until Phase 4 ends. Do not share this table with the team.
-- =====================================================================================
-- 12a. Make the two-column file (once, in Anaconda Prompt, at D:\Amdari\Project_veltrix\Marc):
--   python -c "import pandas as pd; pd.read_parquet(r'restricted\answer_key\veltrix_medium\_answer_key_customer_persona.parquet', columns=['customer_id','duplicate_of']).to_csv(r'restricted\answer_key\veltrix_medium\duplicate_of.csv', index=False)"
-- 12b. Create the table, then load the CSV: pgAdmin > restricted > Tables > duplicate_key >
--      right-click > Import/Export Data > Import > the CSV, Header ON (same as the Day 2 loads)
CREATE SCHEMA IF NOT EXISTS restricted;
DROP TABLE IF EXISTS restricted.duplicate_key;
CREATE TABLE restricted.duplicate_key (customer_id VARCHAR PRIMARY KEY, duplicate_of VARCHAR);
-- (import the CSV now, then continue)
SELECT count(*) AS rows_loaded, count(duplicate_of) AS true_duplicates FROM restricted.duplicate_key;  -- 102,000 and 2,000

-- 12c. Who is really who: every record -> its true original
DROP TABLE IF EXISTS restricted.dedupe_truth;
CREATE TABLE restricted.dedupe_truth AS
SELECT m.customer_id, m.master_customer_id, m.is_master, m.matched_on,
       coalesce(k.duplicate_of, k.customer_id) AS true_root,
       coalesce(km.duplicate_of, km.customer_id) AS master_true_root
FROM clean.customer_merge_map m
JOIN restricted.duplicate_key k  ON k.customer_id  = m.customer_id
JOIN restricted.duplicate_key km ON km.customer_id = m.master_customer_id;

-- 12d. Auto-merge quality: precision (merges that were right) and recall (duplicates found)
--      Expected: 2,000 true duplicates, 1,427 merged, 0 false merges -> precision 100%, recall 71.4%
SELECT (SELECT count(*) FROM restricted.duplicate_key WHERE duplicate_of IS NOT NULL)            AS true_duplicates,
       count(*) FILTER (WHERE NOT is_master)                                                      AS records_merged,
       count(*) FILTER (WHERE NOT is_master AND true_root = master_true_root)                     AS correct_merges,
       count(*) FILTER (WHERE NOT is_master AND true_root <> master_true_root)                    AS false_merges,
       round(100.0 * count(*) FILTER (WHERE NOT is_master AND true_root = master_true_root)
             / nullif(count(*) FILTER (WHERE NOT is_master), 0), 1)                               AS precision_pct,
       round(100.0 * count(*) FILTER (WHERE NOT is_master AND true_root = master_true_root)
             / nullif((SELECT count(*) FROM restricted.duplicate_key WHERE duplicate_of IS NOT NULL), 0), 1) AS recall_pct
FROM restricted.dedupe_truth;

-- 12e. By match rule (same email / same phone)
SELECT matched_on, count(*) AS records_merged,
       count(*) FILTER (WHERE true_root = master_true_root) AS same_person_as_master
FROM restricted.dedupe_truth WHERE NOT is_master GROUP BY 1 ORDER BY 2 DESC;

-- 12f. Review-queue precision by rank band: how deep is it worth reviewing?
--      Expected: 24 true pairs in the top 100 (24%), much lower further down -> review the top 100 first
SELECT CASE WHEN q.queue_rank <= 100 THEN '0001-0100' WHEN q.queue_rank <= 250 THEN '0101-0250'
            WHEN q.queue_rank <= 500 THEN '0251-0500' ELSE '0501-1000' END AS rank_band,
       count(*) AS pairs,
       count(*) FILTER (WHERE ta.true_root = tb.true_root) AS true_duplicate_pairs,
       round(100.0 * count(*) FILTER (WHERE ta.true_root = tb.true_root) / count(*), 1) AS precision_pct
FROM clean.dedupe_review_queue q
JOIN restricted.dedupe_truth ta ON ta.customer_id = q.customer_id_a
JOIN restricted.dedupe_truth tb ON tb.customer_id = q.customer_id_b
GROUP BY 1 ORDER BY 1;

-- 12g. THE PHASE 1 GATE: 95% of active leads matched to one customer ID
-- A lead is matched when its customer ends up on the same master as that person's true original.
-- Expected: active leads 96.8% before -> 99.2% after de-duplication = PASS
WITH l AS (
    SELECT r.lead_id,
           CASE WHEN r.lead_stage IN ('New', 'Contacted', 'Qualified', 'Viewing', 'Offer') THEN 'Active (open pipeline)' ELSE 'Closed' END AS lead_group,
           t.master_customer_id AS assigned_master,
           mo.master_customer_id AS master_of_true_original,
           (t.true_root <> t.customer_id) AS raised_on_duplicate
    FROM raw.leads r
    JOIN restricted.dedupe_truth t ON t.customer_id = r.customer_id
    JOIN clean.customer_merge_map mo ON mo.customer_id = t.true_root
)
SELECT coalesce(lead_group, 'All leads') AS leads, count(*) AS n,
       count(*) FILTER (WHERE raised_on_duplicate) AS raised_on_duplicate_record,
       round(100.0 * avg(CASE WHEN raised_on_duplicate THEN 0 ELSE 1 END), 2) AS matched_before_dedupe_pct,
       round(100.0 * avg(CASE WHEN assigned_master = master_of_true_original THEN 1 ELSE 0 END), 2) AS matched_after_dedupe_pct,
       CASE WHEN avg(CASE WHEN assigned_master = master_of_true_original THEN 1 ELSE 0 END) >= 0.95 THEN 'PASS' ELSE 'FAIL' END AS gate_95pct
FROM l GROUP BY ROLLUP (lead_group) ORDER BY lead_group NULLS LAST;

-- =====================================================================================
-- DAY 4 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · What are the 12-month baselines for conversion, first-reply time, days to close and cost per lead?
SELECT kpi, value FROM clean.kpi_baselines ORDER BY kpi_order;

-- Q2 · What share of replies happen within one hour, and how far is that from the target (all P1 leads)?
--      Overall and by agent seniority.
SELECT coalesce(a.seniority, 'All agents') AS seniority,
       count(*) AS leads_with_a_reply,
       round(100.0 * avg(CASE WHEN l.first_response_min < 60 THEN 1 ELSE 0 END), 1) AS pct_within_1h,
       100 - round(100.0 * avg(CASE WHEN l.first_response_min < 60 THEN 1 ELSE 0 END), 1) AS points_short_of_100pct_target
FROM clean.clean_leads l JOIN raw.agents a USING (agent_id)
WHERE l.first_response_min IS NOT NULL AND l.created_day BETWEEN '2025-10-01' AND '2026-09-30'
GROUP BY ROLLUP (a.seniority) ORDER BY 3 DESC;

-- Q3 · How much did deduplication change the customer count?
SELECT (SELECT count(*) FROM raw.customers)         AS records_before,
       (SELECT count(*) FROM clean.clean_customers) AS customers_after,
       (SELECT count(*) FROM raw.customers) - (SELECT count(*) FROM clean.clean_customers) AS merged,
       round(100.0 * ((SELECT count(*) FROM clean.clean_customers)::NUMERIC / (SELECT count(*) FROM raw.customers) - 1), 2) AS change_pct,
       (SELECT count(*) FROM clean.clean_leads WHERE customer_id <> source_customer_id) AS leads_repointed;
SELECT matched_on, count(*) AS records_merged FROM clean.customer_merge_map WHERE NOT is_master GROUP BY 1;

-- OWN QUESTION A · Are evening and overnight enquiries answered within an hour as often as daytime ones?
SELECT CASE WHEN EXTRACT(HOUR FROM created_date) < 8  THEN '1. Overnight 00-08'
            WHEN EXTRACT(HOUR FROM created_date) < 18 THEN '2. Working day 08-18'
            ELSE '3. Evening 18-24' END AS enquiry_time,
       count(*) AS leads,
       round(100.0 * avg(CASE WHEN first_response_min < 60 THEN 1 ELSE 0 END), 1) AS pct_within_1h,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY first_response_min) AS median_reply_min
FROM clean.clean_leads WHERE first_response_min IS NOT NULL
GROUP BY 1 ORDER BY 1;

-- OWN QUESTION B · How much did cleaning the lead source change each channel's lead count?
SELECT lead_source AS channel, count(*) AS leads_after_cleaning,
       count(*) FILTER (WHERE lead_source_raw = lead_source) AS leads_with_exact_spelling,
       round(100.0 * count(*) FILTER (WHERE lead_source_raw <> lead_source) / count(*), 1) AS pct_recovered_by_cleaning
FROM clean.clean_leads GROUP BY 1 ORDER BY 4 DESC;
