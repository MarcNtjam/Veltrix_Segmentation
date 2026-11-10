-- =====================================================================================
-- DAY 2 · Create the tables with primary and foreign keys, load the CSVs, reconcile
-- Run in pgAdmin: Query Tool on veltrix. Run ONE STEP AT A TIME (highlight a step, F5).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- STEP 1 · A schema (folder) for the untouched source data
-- -------------------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS raw;

-- -------------------------------------------------------------------------------------
-- STEP 2 · The 13 empty tables. PRIMARY KEY = the column that identifies each row;
-- PostgreSQL will refuse duplicates or blanks in it.
-- -------------------------------------------------------------------------------------
CREATE TABLE raw.locations (
    location_id            VARCHAR PRIMARY KEY,
    area_name              VARCHAR,
    region                 VARCHAR,
    country                VARCHAR,
    postcode_district      VARCHAR,
    avg_price_per_sqm_gbp  BIGINT,
    avg_gross_yield_pct    DOUBLE PRECISION,
    latitude               DOUBLE PRECISION,
    longitude              DOUBLE PRECISION
);

CREATE TABLE raw.agents (
    agent_id               VARCHAR PRIMARY KEY,
    team                   VARCHAR,
    branch                 VARCHAR,
    seniority              VARCHAR,
    hire_date              DATE,
    propertymark_qualified BOOLEAN
);

CREATE TABLE raw.customers (
    customer_id                VARCHAR PRIMARY KEY,
    email_sha256               VARCHAR,
    phone_sha256               VARCHAR,
    customer_type              VARCHAR,
    gender                     VARCHAR,
    age_band                   VARCHAR,
    occupation_sector          VARCHAR,
    country_of_residence       VARCHAR,
    is_overseas                BOOLEAN,
    uk_region_of_residence     VARCHAR,
    buyer_position             VARCHAR,
    finance_type               VARCHAR,
    primary_intent             VARCHAR,
    stated_budget_gbp          BIGINT,
    stated_rent_budget_pcm_gbp BIGINT,
    preferred_currency         VARCHAR,
    first_contact_date         DATE,
    consent_marketing          BOOLEAN,
    created_at                 TIMESTAMP
);

CREATE TABLE raw.campaigns (
    campaign_id      VARCHAR PRIMARY KEY,
    campaign_name    VARCHAR,
    channel          VARCHAR,
    theme            VARCHAR,
    objective        VARCHAR,
    planned_audience VARCHAR,
    target_segment   VARCHAR,
    start_date       DATE,
    end_date         DATE,
    spend_gbp        DOUBLE PRECISION
);

CREATE TABLE raw.leads (
    lead_id      VARCHAR PRIMARY KEY,
    customer_id  VARCHAR,
    agent_id     VARCHAR,
    lead_source  VARCHAR,
    campaign_id  VARCHAR,
    intent       VARCHAR,
    lead_stage   VARCHAR,
    lost_reason  VARCHAR,
    created_date TIMESTAMP,
    closed_date  DATE,
    converted    BOOLEAN
);

CREATE TABLE raw.interactions (
    interaction_id    VARCHAR PRIMARY KEY,
    lead_id           VARCHAR,
    agent_id          VARCHAR,
    channel           VARCHAR,
    direction         VARCHAR,
    interaction_time  TIMESTAMP,
    response_time_min BIGINT,
    topic             VARCHAR
);

CREATE TABLE raw.properties (
    property_id           VARCHAR PRIMARY KEY,
    location_id           VARCHAR,
    development_name      VARCHAR,
    property_type         VARCHAR,
    bedrooms              BIGINT,
    size_sqm              BIGINT,
    listing_purpose       VARCHAR,
    asking_price_gbp      BIGINT,
    rent_pcm_gbp          BIGINT,
    new_build             BOOLEAN,
    development_status    VARCHAR,
    tenure                VARCHAR,
    epc_rating            VARCHAR,
    council_tax_band      VARCHAR,
    service_charge_gbp_pa BIGINT,
    furnishing            VARCHAR,
    first_marketed_date   DATE,
    latitude              DOUBLE PRECISION,
    longitude             DOUBLE PRECISION
);

CREATE TABLE raw.site_visits (
    visit_id    VARCHAR PRIMARY KEY,
    lead_id     VARCHAR,
    property_id VARCHAR,
    visit_type  VARCHAR,
    visit_date  DATE,
    outcome     VARCHAR
);

CREATE TABLE raw.transactions (
    transaction_id             VARCHAR PRIMARY KEY,
    lead_id                    VARCHAR,
    customer_id                VARCHAR,
    property_id                VARCHAR,
    transaction_type           VARCHAR,
    finance_type               VARCHAR,
    agreed_price_gbp           BIGINT,
    agreed_rent_pcm_gbp        BIGINT,
    discount_pct               DOUBLE PRECISION,
    contract_date              DATE,
    completion_or_move_in_date DATE,
    tenancy_months             BIGINT,
    mortgage_ltv_pct           DOUBLE PRECISION,
    payment_currency           VARCHAR
);

CREATE TABLE raw.payments (
    payment_id       VARCHAR PRIMARY KEY,
    transaction_id   VARCHAR,
    payment_type     VARCHAR,
    due_date         DATE,
    paid_date        DATE,
    amount_gbp       DOUBLE PRECISION,
    payment_currency VARCHAR,
    payment_method   VARCHAR,
    status           VARCHAR,
    days_late        BIGINT
);

CREATE TABLE raw.campaign_responses (
    response_id   VARCHAR PRIMARY KEY,
    campaign_id   VARCHAR,
    customer_id   VARCHAR,
    response_type VARCHAR,
    response_time TIMESTAMP
);

CREATE TABLE raw.web_sessions (
    session_id     VARCHAR PRIMARY KEY,
    customer_id    VARCHAR,
    session_start  TIMESTAMP,
    device         VARCHAR,
    ip_country     VARCHAR,
    traffic_source VARCHAR,
    pages_viewed   BIGINT,
    duration_sec   BIGINT
);

CREATE TABLE raw.property_views (
    view_id     VARCHAR PRIMARY KEY,
    session_id  VARCHAR,
    property_id VARCHAR,
    event_type  VARCHAR,
    event_time  TIMESTAMP
);

-- -------------------------------------------------------------------------------------
-- STEP 3 · Load the CSVs. TWO WAYS - pick one:
--   (a) Click: right-click each table (raw > Tables) > Import/Export Data > Import >
--       pick its CSV > Options: Header ON, Delimiter "," > OK.  Do them in this order.
--   (b) Code: the COPY lines below. Edit the folder path to where YOUR CSVs are.
--       If you get "Permission denied", use (a): pgAdmin's import reads the file as you.
-- property_views (1 GB) takes 1-3 minutes.
-- -------------------------------------------------------------------------------------
COPY raw.locations           FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/locations.csv' WITH (FORMAT csv, HEADER true);
COPY raw.agents              FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/agents.csv' WITH (FORMAT csv, HEADER true);
COPY raw.customers           FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/customers.csv' WITH (FORMAT csv, HEADER true);
COPY raw.campaigns           FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/campaigns.csv' WITH (FORMAT csv, HEADER true);
COPY raw.leads               FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/leads.csv' WITH (FORMAT csv, HEADER true);
COPY raw.interactions        FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/interactions.csv' WITH (FORMAT csv, HEADER true);
COPY raw.properties          FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/properties.csv' WITH (FORMAT csv, HEADER true);
COPY raw.site_visits         FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/site_visits.csv' WITH (FORMAT csv, HEADER true);
COPY raw.transactions        FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/transactions.csv' WITH (FORMAT csv, HEADER true);
COPY raw.payments            FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/payments.csv' WITH (FORMAT csv, HEADER true);
COPY raw.campaign_responses  FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/campaign_responses.csv' WITH (FORMAT csv, HEADER true);
COPY raw.web_sessions        FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/web_sessions.csv' WITH (FORMAT csv, HEADER true);
COPY raw.property_views      FROM 'D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium/property_views.csv' WITH (FORMAT csv, HEADER true);

-- -------------------------------------------------------------------------------------
-- STEP 4 · Reconcile: every table must match the generation log (all matches = true)
-- This is also the source for the Power BI "Data check" page.
-- -------------------------------------------------------------------------------------
CREATE TABLE raw.row_count_check AS
SELECT table_name, generation_log_rows, sql_rows, (generation_log_rows = sql_rows) AS matches FROM (
SELECT 'locations' AS table_name, 36 AS generation_log_rows, (SELECT count(*) FROM raw.locations) AS sql_rows UNION ALL
SELECT 'agents' AS table_name, 300 AS generation_log_rows, (SELECT count(*) FROM raw.agents) AS sql_rows UNION ALL
SELECT 'customers' AS table_name, 102000 AS generation_log_rows, (SELECT count(*) FROM raw.customers) AS sql_rows UNION ALL
SELECT 'campaigns' AS table_name, 270 AS generation_log_rows, (SELECT count(*) FROM raw.campaigns) AS sql_rows UNION ALL
SELECT 'leads' AS table_name, 95804 AS generation_log_rows, (SELECT count(*) FROM raw.leads) AS sql_rows UNION ALL
SELECT 'interactions' AS table_name, 532789 AS generation_log_rows, (SELECT count(*) FROM raw.interactions) AS sql_rows UNION ALL
SELECT 'properties' AS table_name, 16667 AS generation_log_rows, (SELECT count(*) FROM raw.properties) AS sql_rows UNION ALL
SELECT 'site_visits' AS table_name, 233593 AS generation_log_rows, (SELECT count(*) FROM raw.site_visits) AS sql_rows UNION ALL
SELECT 'transactions' AS table_name, 16665 AS generation_log_rows, (SELECT count(*) FROM raw.transactions) AS sql_rows UNION ALL
SELECT 'payments' AS table_name, 106199 AS generation_log_rows, (SELECT count(*) FROM raw.payments) AS sql_rows UNION ALL
SELECT 'campaign_responses' AS table_name, 808953 AS generation_log_rows, (SELECT count(*) FROM raw.campaign_responses) AS sql_rows UNION ALL
SELECT 'web_sessions' AS table_name, 2003460 AS generation_log_rows, (SELECT count(*) FROM raw.web_sessions) AS sql_rows UNION ALL
SELECT 'property_views' AS table_name, 15163137 AS generation_log_rows, (SELECT count(*) FROM raw.property_views) AS sql_rows
) x;
SELECT * FROM raw.row_count_check;

-- -------------------------------------------------------------------------------------
-- STEP 5 · Foreign keys: the 17 links between tables. If one fails, the error names
-- the broken link = a data problem. (Expected: all 17 succeed, ~1-2 minutes.)
-- -------------------------------------------------------------------------------------
ALTER TABLE raw.properties         ADD CONSTRAINT fk_properties_location   FOREIGN KEY (location_id)    REFERENCES raw.locations(location_id);
ALTER TABLE raw.leads              ADD CONSTRAINT fk_leads_customer        FOREIGN KEY (customer_id)    REFERENCES raw.customers(customer_id);
ALTER TABLE raw.leads              ADD CONSTRAINT fk_leads_agent           FOREIGN KEY (agent_id)       REFERENCES raw.agents(agent_id);
ALTER TABLE raw.leads              ADD CONSTRAINT fk_leads_campaign        FOREIGN KEY (campaign_id)    REFERENCES raw.campaigns(campaign_id);
ALTER TABLE raw.interactions       ADD CONSTRAINT fk_interactions_lead     FOREIGN KEY (lead_id)        REFERENCES raw.leads(lead_id);
ALTER TABLE raw.interactions       ADD CONSTRAINT fk_interactions_agent    FOREIGN KEY (agent_id)       REFERENCES raw.agents(agent_id);
ALTER TABLE raw.site_visits        ADD CONSTRAINT fk_visits_lead           FOREIGN KEY (lead_id)        REFERENCES raw.leads(lead_id);
ALTER TABLE raw.site_visits        ADD CONSTRAINT fk_visits_property       FOREIGN KEY (property_id)    REFERENCES raw.properties(property_id);
ALTER TABLE raw.transactions       ADD CONSTRAINT fk_tx_lead               FOREIGN KEY (lead_id)        REFERENCES raw.leads(lead_id);
ALTER TABLE raw.transactions       ADD CONSTRAINT fk_tx_customer           FOREIGN KEY (customer_id)    REFERENCES raw.customers(customer_id);
ALTER TABLE raw.transactions       ADD CONSTRAINT fk_tx_property           FOREIGN KEY (property_id)    REFERENCES raw.properties(property_id);
ALTER TABLE raw.payments           ADD CONSTRAINT fk_payments_tx           FOREIGN KEY (transaction_id) REFERENCES raw.transactions(transaction_id);
ALTER TABLE raw.campaign_responses ADD CONSTRAINT fk_responses_campaign    FOREIGN KEY (campaign_id)    REFERENCES raw.campaigns(campaign_id);
ALTER TABLE raw.campaign_responses ADD CONSTRAINT fk_responses_customer    FOREIGN KEY (customer_id)    REFERENCES raw.customers(customer_id);
ALTER TABLE raw.web_sessions       ADD CONSTRAINT fk_sessions_customer     FOREIGN KEY (customer_id)    REFERENCES raw.customers(customer_id);
ALTER TABLE raw.property_views     ADD CONSTRAINT fk_views_session         FOREIGN KEY (session_id)     REFERENCES raw.web_sessions(session_id);
ALTER TABLE raw.property_views     ADD CONSTRAINT fk_views_property        FOREIGN KEY (property_id)    REFERENCES raw.properties(property_id);

-- Indexes on join columns, so later queries and Power BI refreshes are faster
CREATE INDEX ix_leads_customer       ON raw.leads(customer_id);
CREATE INDEX ix_interactions_lead    ON raw.interactions(lead_id);
CREATE INDEX ix_visits_lead          ON raw.site_visits(lead_id);
CREATE INDEX ix_tx_customer          ON raw.transactions(customer_id);
CREATE INDEX ix_payments_tx          ON raw.payments(transaction_id);
CREATE INDEX ix_responses_customer   ON raw.campaign_responses(customer_id);
CREATE INDEX ix_sessions_customer    ON raw.web_sessions(customer_id);
CREATE INDEX ix_views_session        ON raw.property_views(session_id);
CREATE INDEX ix_views_property       ON raw.property_views(property_id);
ANALYZE;

-- =====================================================================================
-- STEP 6 · First data dictionary entries (from the case study tables)
-- COMMENT stores the description inside the database, so pgAdmin shows it and the
-- query at the end lists the whole dictionary. Export that result as data_dictionary.csv.
-- =====================================================================================
COMMENT ON TABLE raw.locations IS 'The 36 areas Veltrix operates in, with market price and yield benchmarks. One row per location.';
COMMENT ON COLUMN raw.locations.location_id IS 'Location key (VLX-LOC###)';
COMMENT ON COLUMN raw.locations.area_name IS 'Area name, e.g. Canary Wharf';
COMMENT ON COLUMN raw.locations.region IS 'One of the 11 GB regions';
COMMENT ON COLUMN raw.locations.country IS 'England, Scotland or Wales';
COMMENT ON COLUMN raw.locations.postcode_district IS 'Outward postcode, e.g. E14';
COMMENT ON COLUMN raw.locations.avg_price_per_sqm_gbp IS 'Average sale price per m² in the area (£)';
COMMENT ON COLUMN raw.locations.avg_gross_yield_pct IS 'Average gross rental yield in the area (%)';
COMMENT ON COLUMN raw.locations.latitude IS 'Latitude (WGS84)';
COMMENT ON COLUMN raw.locations.longitude IS 'Longitude (WGS84)';
COMMENT ON TABLE raw.agents IS 'Sales and lettings staff. One row per agent.';
COMMENT ON COLUMN raw.agents.agent_id IS 'Agent key (VLX-A#####)';
COMMENT ON COLUMN raw.agents.team IS 'Desk, e.g. London Sales, Investor desk, International desk';
COMMENT ON COLUMN raw.agents.branch IS 'Home branch';
COMMENT ON COLUMN raw.agents.seniority IS 'Senior / Mid / Junior';
COMMENT ON COLUMN raw.agents.hire_date IS 'Date the agent joined';
COMMENT ON COLUMN raw.agents.propertymark_qualified IS 'Holds a Propertymark qualification';
COMMENT ON TABLE raw.customers IS 'CRM customer records (buyers, tenants, investors, corporates). One row per record; ~2% are duplicates of another record.';
COMMENT ON COLUMN raw.customers.customer_id IS 'Customer key (VLX-C########). In clean views: the surviving master ID after merging duplicates';
COMMENT ON COLUMN raw.customers.email_sha256 IS 'SHA-256 hash of email (no raw contact data). Used for duplicate matching';
COMMENT ON COLUMN raw.customers.phone_sha256 IS 'SHA-256 hash of phone; blank when no phone given';
COMMENT ON COLUMN raw.customers.customer_type IS 'Individual / Limited company (SPV) / Corporate';
COMMENT ON COLUMN raw.customers.gender IS 'Female / Male / Not stated (raw also has blanks)';
COMMENT ON COLUMN raw.customers.age_band IS '18-24 ... 65+; often blank';
COMMENT ON COLUMN raw.customers.occupation_sector IS 'Self-reported sector; often blank';
COMMENT ON COLUMN raw.customers.country_of_residence IS 'Raw: inconsistent labels (UK, U.K., England, HK, UAE...). Clean: one standard country name';
COMMENT ON COLUMN raw.customers.is_overseas IS 'Lives outside the UK';
COMMENT ON COLUMN raw.customers.uk_region_of_residence IS 'UK region for UK residents';
COMMENT ON COLUMN raw.customers.buyer_position IS 'Self-declared position: first-time buyer, home mover, downsizer, landlord, renter...';
COMMENT ON COLUMN raw.customers.finance_type IS 'How they will pay: mortgage, cash, Lifetime ISA, shared ownership, equity release, renting, company let...';
COMMENT ON COLUMN raw.customers.primary_intent IS 'Buy or Rent';
COMMENT ON COLUMN raw.customers.stated_budget_gbp IS 'Purchase budget as typed (contains typos; see budget_gbp)';
COMMENT ON COLUMN raw.customers.stated_rent_budget_pcm_gbp IS 'Monthly rent budget as typed (some annual figures; see rent_budget_pcm_gbp)';
COMMENT ON COLUMN raw.customers.preferred_currency IS 'Currency the customer prefers to deal in';
COMMENT ON COLUMN raw.customers.first_contact_date IS 'Date of first contact (clean: earliest across merged records)';
COMMENT ON COLUMN raw.customers.consent_marketing IS 'Marketing consent (clean: true only if every merged record consents)';
COMMENT ON COLUMN raw.customers.created_at IS 'Record creation timestamp';
COMMENT ON TABLE raw.campaigns IS 'Monthly marketing campaigns per channel. One row per campaign.';
COMMENT ON COLUMN raw.campaigns.campaign_id IS 'Campaign key (CMP-YYYYMM-CHANNEL)';
COMMENT ON COLUMN raw.campaigns.campaign_name IS 'Campaign name';
COMMENT ON COLUMN raw.campaigns.channel IS 'Campaign: Meta, Google Ads, TikTok, WeChat, Email, Portal featured. Interactions: Phone, Email, WhatsApp...';
COMMENT ON COLUMN raw.campaigns.theme IS 'Creative theme';
COMMENT ON COLUMN raw.campaigns.objective IS 'Campaign objective';
COMMENT ON COLUMN raw.campaigns.planned_audience IS 'Intended audience';
COMMENT ON COLUMN raw.campaigns.target_segment IS 'Segment targeted; empty until Phase 5';
COMMENT ON COLUMN raw.campaigns.start_date IS 'Campaign start';
COMMENT ON COLUMN raw.campaigns.end_date IS 'Campaign end';
COMMENT ON COLUMN raw.campaigns.spend_gbp IS 'Media spend (£)';
COMMENT ON TABLE raw.leads IS 'Enquiries. One row per lead; a customer can have several. Grain of the pipeline.';
COMMENT ON COLUMN raw.leads.lead_id IS 'Lead key (VLX-L#########)';
COMMENT ON COLUMN raw.leads.customer_id IS 'Customer key (VLX-C########). In clean views: the surviving master ID after merging duplicates';
COMMENT ON COLUMN raw.leads.agent_id IS 'Agent key (VLX-A#####)';
COMMENT ON COLUMN raw.leads.lead_source IS 'Raw: 28 spellings of 14 sources. Clean: one of the 14 standard sources';
COMMENT ON COLUMN raw.leads.campaign_id IS 'Campaign key (CMP-YYYYMM-CHANNEL)';
COMMENT ON COLUMN raw.leads.intent IS 'Buy or Rent';
COMMENT ON COLUMN raw.leads.lead_stage IS 'New, Contacted, Qualified, Viewing, Offer (open) / Won, Lost (closed)';
COMMENT ON COLUMN raw.leads.lost_reason IS 'Why a Lost lead was lost';
COMMENT ON COLUMN raw.leads.created_date IS 'When the enquiry arrived';
COMMENT ON COLUMN raw.leads.closed_date IS 'When it was Won or Lost; blank while open';
COMMENT ON COLUMN raw.leads.converted IS 'True when lead_stage = Won';
COMMENT ON TABLE raw.interactions IS 'Every contact on a lead (calls, emails, WhatsApp...). One row per interaction.';
COMMENT ON COLUMN raw.interactions.interaction_id IS 'Interaction key';
COMMENT ON COLUMN raw.interactions.lead_id IS 'Lead key (VLX-L#########)';
COMMENT ON COLUMN raw.interactions.agent_id IS 'Agent key (VLX-A#####)';
COMMENT ON COLUMN raw.interactions.channel IS 'Campaign: Meta, Google Ads, TikTok, WeChat, Email, Portal featured. Interactions: Phone, Email, WhatsApp...';
COMMENT ON COLUMN raw.interactions.direction IS 'Inbound (customer to Veltrix) / Outbound';
COMMENT ON COLUMN raw.interactions.interaction_time IS 'Timestamp';
COMMENT ON COLUMN raw.interactions.response_time_min IS 'Minutes Veltrix took to reply to an inbound contact; blank on outbound (by design) and on 2% of inbound';
COMMENT ON COLUMN raw.interactions.topic IS 'Main topic discussed';
COMMENT ON TABLE raw.properties IS 'Listings for sale or rent. One row per property.';
COMMENT ON COLUMN raw.properties.property_id IS 'Property key (VLX-P#######)';
COMMENT ON COLUMN raw.properties.location_id IS 'Location key (VLX-LOC###)';
COMMENT ON COLUMN raw.properties.development_name IS 'New-homes development, blank for resales';
COMMENT ON COLUMN raw.properties.property_type IS 'Flat, Terraced, Semi-detached, Detached, Maisonette, Bungalow';
COMMENT ON COLUMN raw.properties.bedrooms IS 'Bedrooms (0 = studio)';
COMMENT ON COLUMN raw.properties.size_sqm IS 'Floor area m²; 4% blank';
COMMENT ON COLUMN raw.properties.listing_purpose IS 'Sale or Rent';
COMMENT ON COLUMN raw.properties.asking_price_gbp IS 'Asking price (sale listings)';
COMMENT ON COLUMN raw.properties.rent_pcm_gbp IS 'Monthly rent (rent listings)';
COMMENT ON COLUMN raw.properties.new_build IS 'New-build listing';
COMMENT ON COLUMN raw.properties.development_status IS 'Completed / Under construction / Off-plan (new-build only)';
COMMENT ON COLUMN raw.properties.tenure IS 'Freehold, Leasehold, Share of freehold, Ownership (Scotland)';
COMMENT ON COLUMN raw.properties.epc_rating IS 'Energy rating A-G; 7% blank';
COMMENT ON COLUMN raw.properties.council_tax_band IS 'Council tax band A-H';
COMMENT ON COLUMN raw.properties.service_charge_gbp_pa IS 'Annual service charge (£), leasehold mainly';
COMMENT ON COLUMN raw.properties.furnishing IS 'Furnished / Part / Unfurnished (rent listings)';
COMMENT ON COLUMN raw.properties.first_marketed_date IS 'Date first listed';
COMMENT ON COLUMN raw.properties.latitude IS 'Latitude (WGS84)';
COMMENT ON COLUMN raw.properties.longitude IS 'Longitude (WGS84)';
COMMENT ON TABLE raw.site_visits IS 'Viewings booked on a lead. One row per viewing.';
COMMENT ON COLUMN raw.site_visits.visit_id IS 'Viewing key';
COMMENT ON COLUMN raw.site_visits.lead_id IS 'Lead key (VLX-L#########)';
COMMENT ON COLUMN raw.site_visits.property_id IS 'Property key (VLX-P#######)';
COMMENT ON COLUMN raw.site_visits.visit_type IS 'In person, Virtual, Open house, Proxy';
COMMENT ON COLUMN raw.site_visits.visit_date IS 'Date of viewing';
COMMENT ON COLUMN raw.site_visits.outcome IS 'Result of the viewing';
COMMENT ON TABLE raw.transactions IS 'Completed deals (sales and lettings). One row per deal; each links to one Won lead.';
COMMENT ON COLUMN raw.transactions.transaction_id IS 'Deal key (VLX-T########)';
COMMENT ON COLUMN raw.transactions.lead_id IS 'Lead key (VLX-L#########)';
COMMENT ON COLUMN raw.transactions.customer_id IS 'Customer key (VLX-C########). In clean views: the surviving master ID after merging duplicates';
COMMENT ON COLUMN raw.transactions.property_id IS 'Property key (VLX-P#######)';
COMMENT ON COLUMN raw.transactions.transaction_type IS 'Resale / New-build / Off-plan purchase, Assured shorthold tenancy, Company let';
COMMENT ON COLUMN raw.transactions.finance_type IS 'How they will pay: mortgage, cash, Lifetime ISA, shared ownership, equity release, renting, company let...';
COMMENT ON COLUMN raw.transactions.agreed_price_gbp IS 'Agreed sale price';
COMMENT ON COLUMN raw.transactions.agreed_rent_pcm_gbp IS 'Agreed monthly rent';
COMMENT ON COLUMN raw.transactions.discount_pct IS 'Discount from asking (%); negative = above asking';
COMMENT ON COLUMN raw.transactions.contract_date IS 'Exchange / contract signed';
COMMENT ON COLUMN raw.transactions.completion_or_move_in_date IS 'Completion (sale) or move-in (let); can be in the future for off-plan';
COMMENT ON COLUMN raw.transactions.tenancy_months IS 'Tenancy length (lettings)';
COMMENT ON COLUMN raw.transactions.mortgage_ltv_pct IS 'Loan-to-value (mortgage deals)';
COMMENT ON COLUMN raw.transactions.payment_currency IS 'Currency paid in';
COMMENT ON TABLE raw.payments IS 'Money due and paid on each deal (deposits, completion balances, monthly rent). One row per payment.';
COMMENT ON COLUMN raw.payments.payment_id IS 'Payment key';
COMMENT ON COLUMN raw.payments.transaction_id IS 'Deal key (VLX-T########)';
COMMENT ON COLUMN raw.payments.payment_type IS 'Reservation fee, deposits, completion balance, monthly rent...';
COMMENT ON COLUMN raw.payments.due_date IS 'Due date (can be after Sep 2026 for schedules)';
COMMENT ON COLUMN raw.payments.paid_date IS 'Date paid; blank if Scheduled or Overdue';
COMMENT ON COLUMN raw.payments.amount_gbp IS 'Amount in £ (4 small negative exchange deposits: see DQ log)';
COMMENT ON COLUMN raw.payments.payment_currency IS 'Currency paid in';
COMMENT ON COLUMN raw.payments.payment_method IS 'Bank transfer, Standing order, CHAPS, Card, International transfer';
COMMENT ON COLUMN raw.payments.status IS 'Paid, Paid late, Overdue, Scheduled';
COMMENT ON COLUMN raw.payments.days_late IS 'Days paid after due date';
COMMENT ON TABLE raw.campaign_responses IS 'Customer responses to campaigns (clicks, opens, form submits...). One row per response.';
COMMENT ON COLUMN raw.campaign_responses.response_id IS 'Response key';
COMMENT ON COLUMN raw.campaign_responses.campaign_id IS 'Campaign key (CMP-YYYYMM-CHANNEL)';
COMMENT ON COLUMN raw.campaign_responses.customer_id IS 'Customer key (VLX-C########). In clean views: the surviving master ID after merging duplicates';
COMMENT ON COLUMN raw.campaign_responses.response_type IS 'Click, Open, Form submit, Hide ad, Unsubscribe';
COMMENT ON COLUMN raw.campaign_responses.response_time IS 'Timestamp';
COMMENT ON TABLE raw.web_sessions IS 'Website/app sessions. One row per session; 25% are anonymous (no customer_id).';
COMMENT ON COLUMN raw.web_sessions.session_id IS 'Session key';
COMMENT ON COLUMN raw.web_sessions.customer_id IS 'Customer key (VLX-C########). In clean views: the surviving master ID after merging duplicates';
COMMENT ON COLUMN raw.web_sessions.session_start IS 'Session start, UK time';
COMMENT ON COLUMN raw.web_sessions.device IS 'Mobile, Tablet, Desktop';
COMMENT ON COLUMN raw.web_sessions.ip_country IS 'ISO country of the IP address; noisy (VPNs, travel) - do not use as residence';
COMMENT ON COLUMN raw.web_sessions.traffic_source IS 'How the visitor arrived';
COMMENT ON COLUMN raw.web_sessions.pages_viewed IS 'Pages in the session';
COMMENT ON COLUMN raw.web_sessions.duration_sec IS 'Session length (seconds)';
COMMENT ON TABLE raw.property_views IS 'Events inside a session on a listing (view, save, virtual tour...). One row per event. ~15M rows.';
COMMENT ON COLUMN raw.property_views.view_id IS 'Event key';
COMMENT ON COLUMN raw.property_views.session_id IS 'Session key';
COMMENT ON COLUMN raw.property_views.property_id IS 'Property key (VLX-P#######)';
COMMENT ON COLUMN raw.property_views.event_type IS 'View, Save, Virtual tour, Share, Floorplan download';
COMMENT ON COLUMN raw.property_views.event_time IS 'Timestamp';

-- The dictionary: one row per column, with type, description, blanks measured later on Day 3
SELECT c.table_name, c.ordinal_position AS col_no, c.column_name, c.data_type,
       obj_description(('raw.' || c.table_name)::regclass, 'pg_class')                      AS table_description,
       col_description(('raw.' || c.table_name)::regclass, c.ordinal_position::int)          AS column_description,
       CASE WHEN k.column_name IS NOT NULL THEN 'PK' WHEN f.column_name IS NOT NULL THEN 'FK -> ' || f.ref_table END AS key
FROM information_schema.columns c
LEFT JOIN (SELECT kcu.table_name, kcu.column_name FROM information_schema.table_constraints tc
           JOIN information_schema.key_column_usage kcu USING (constraint_schema, constraint_name)
           WHERE tc.table_schema = 'raw' AND tc.constraint_type = 'PRIMARY KEY') k
       ON k.table_name = c.table_name AND k.column_name = c.column_name
LEFT JOIN (SELECT kcu.table_name, kcu.column_name, ccu.table_name AS ref_table FROM information_schema.table_constraints tc
           JOIN information_schema.key_column_usage kcu USING (constraint_schema, constraint_name)
           JOIN information_schema.constraint_column_usage ccu USING (constraint_schema, constraint_name)
           WHERE tc.table_schema = 'raw' AND tc.constraint_type = 'FOREIGN KEY') f
       ON f.table_name = c.table_name AND f.column_name = c.column_name
WHERE c.table_schema = 'raw' AND c.table_name <> 'row_count_check'
ORDER BY c.table_name, c.ordinal_position;

-- =====================================================================================
-- DAY 2 BUSINESS QUESTIONS
-- =====================================================================================

-- Q1 · How many customers, leads, transactions and payments does Veltrix hold for
--      January 2023 to September 2026?            (Check: 102,000 / 95,804 / 16,665 / 106,199)
SELECT (SELECT count(*) FROM raw.customers)    AS customer_records,
       (SELECT count(*) FROM raw.leads)        AS leads,
       (SELECT count(*) FROM raw.transactions) AS transactions,
       (SELECT count(*) FROM raw.payments)     AS payments,
       (SELECT min(created_date)::date FROM raw.leads) AS first_lead,
       (SELECT max(created_date)::date FROM raw.leads) AS last_lead;

-- ... and by year
SELECT EXTRACT(YEAR FROM created_date)::int AS year, count(*) AS leads
FROM raw.leads GROUP BY 1 ORDER BY 1;

-- Q2 · Which tables feed each of the 4 pages, and how do they join?
--   Overview            : leads + customers + transactions   (leads.customer_id = customers.customer_id; transactions.lead_id = leads.lead_id)
--   Segment deep dive   : customers + web_sessions + property_views + properties + locations
--                         (web_sessions.customer_id = customers.customer_id; property_views.session_id = web_sessions.session_id;
--                          property_views.property_id = properties.property_id; properties.location_id = locations.location_id)
--   Pipeline and agents : leads + interactions + agents + site_visits (leads.agent_id = agents.agent_id; interactions.lead_id = leads.lead_id)
--   Payments & lettings : payments + transactions + properties (payments.transaction_id = transactions.transaction_id)
-- Proof the joins work: list the foreign keys PostgreSQL now enforces (expected 17 rows)
SELECT tc.table_name, kcu.column_name, ccu.table_name AS references_table
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu ON kcu.constraint_name = tc.constraint_name
JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = 'raw'
ORDER BY 1, 2;

-- Q3 · Are any months missing or unusually thin? (rows per month; 45 months expected)
SELECT m.month::date,
       (SELECT count(*) FROM raw.leads        WHERE date_trunc('month', created_date)  = m.month) AS leads,
       (SELECT count(*) FROM raw.transactions WHERE date_trunc('month', contract_date) = m.month) AS transactions,
       (SELECT count(*) FROM raw.web_sessions WHERE date_trunc('month', session_start) = m.month) AS web_sessions
FROM generate_series('2023-01-01'::timestamp, '2026-09-01', interval '1 month') AS m(month)
ORDER BY 1;
-- Look for: zeros (missing), very low months (thin: Jan-Feb 2023), very high months (Mar 2025, Sep 2026).

-- OWN QUESTION A · How much web browsing is anonymous (no customer_id)?    (Check: 25.0%)
SELECT count(*) AS sessions,
       count(*) FILTER (WHERE customer_id IS NULL) AS anonymous,
       round(100.0 * count(*) FILTER (WHERE customer_id IS NULL) / count(*), 1) AS pct_anonymous
FROM raw.web_sessions;

-- OWN QUESTION B · What share of leads can be linked to a marketing campaign?  (Check: 32.8%)
SELECT round(100.0 * count(campaign_id) / count(*), 1) AS pct_leads_with_campaign FROM raw.leads;
