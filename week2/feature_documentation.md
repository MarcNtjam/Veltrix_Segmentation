# Veltrix customer features and outcomes (Week 2, Day 7)

Two tables, one row per customer (100,573 after merging duplicates), data to 30 Sep 2026.

- `feat.customer_features`: what we know **about** a customer before any decision. The DS team clusters on these.
- `feat.customer_outcomes`: what **happened**. It is never used as a clustering input. It is used afterwards to test whether the segments differ (Day 10), and on the dashboard.

Rebuild order after a data refresh: Week 1 Day 4, then Week 2 Days 6, 7, 9 and 10.

## Leakage rules

1. No outcome column (converted, lead_stage, lost_reason, closed_date, deals, deal value, payments) goes into `customer_features`. Day 7 step 4 checks this automatically.
2. Contacts and viewings count only up to the date the lead was decided. On this data, 0 events fall after that date, but the rule protects future monthly refreshes.
3. Viewing **outcomes** ("Offer made", "Application submitted") are not used as features, because they are part of the result.
4. Features describe behaviour over the customer's whole history. Use them to **describe** segments. Do not use them to **predict** conversion without first cutting them at a reference date.

## customer_features

| Group | Feature | Source | Definition | Leakage risk |
|---|---|---|---|---|
| Profile | customer_type, primary_intent, buyer_position, finance_type, age_band, occupation_sector | clean_customers | As stated at sign-up; blanks on a master record filled from its merged duplicates | None |
| Profile | country_of_residence, country_iso2, is_overseas, uk_region_of_residence | clean_customers | Country standardised to 12 ISO countries | None |
| Profile | stated_budget_gbp, stated_rent_budget_pcm_gbp, budget_fixed | clean_customers | Budget after typo fixes; budget_fixed = 1 if corrected | None. About 38% blank: DS imputes from median_viewed_* |
| Browsing | n_sessions, active_days, avg_pages_per_session, avg_session_minutes | customer_session_summary | Known (logged-in) web sessions only | Low |
| Browsing | pct_night_sessions | customer_session_summary | % of sessions starting 00:00–05:59 UK time | Low |
| Browsing | mobile/desktop/tablet_sessions, main_device, main_traffic_source, non_uk_ip_sessions | customer_session_summary | Counts and most common value | Low |
| Browsing | n_property_events, n_distinct_properties, n_saves, n_virtual_tours, n_shares, n_floorplans | customer_property_view_summary | Events on listings, by event type | Low |
| Browsing | n_sale/rent_listing_events, n_new_build_events, n_off_plan_events, n_london_events, n_regions_viewed, top_region_viewed, avg_bedrooms_viewed | customer_property_view_summary, properties, locations | What kind of listing they look at, and where | Low |
| Browsing | pct_events_virtual_tour, pct_events_new_build | derived | Share of property events | Low |
| Prices viewed | median_viewed_price_gbp, n_sale_price_views, median_viewed_rent_pcm_gbp, n_rent_price_views | customer_viewed_prices | Median asking price and rent of listings viewed. For budget imputation, use only when the count is 3 or more | None |
| Pipeline | n_leads, n_buy_leads, n_rent_leads | clean_leads | Total enquiries | Medium: customers who win often make further enquiries afterwards (for example, investors). Describe, don't predict |
| Pipeline | first_lead_day, n_channels_used, main_channel, main_channel_group, n_campaign_leads | clean_leads | Channel and campaign at enquiry | None |
| Pipeline | median_first_response_min, pct_leads_answered_within_1h | clean_leads.first_response_min | Our reply speed on the first inbound contact | None. Set at the start of the lead |
| Pipeline | n_inbound_contacts, n_outbound_contacts | clean_interactions | Contacts up to the decision date | Medium: long negotiations produce more contacts |
| Pipeline | n_viewings, n_virtual_viewings | clean_site_visits | Viewings up to the decision date | Medium: viewings are part of the sales process |
| Pipeline | n_campaign_responses, n_campaign_clicks_or_forms, n_campaign_rejections | clean_campaign_responses | Responses to marketing | None |

## customer_outcomes

| Outcome | Definition |
|---|---|
| n_closed_leads, n_won_leads, n_open_leads | Lead counts by status at 30 Sep 2026 |
| converted | 1 if any lead was won, 0 if all closed leads were lost, NULL if the customer has no decided lead |
| conversion_rate | Won ÷ closed leads for that customer |
| median_days_to_decision, median_days_to_win | Days from lead created to closed (all closed leads / won leads) |
| n_deals, n_sale_deals, n_letting_deals, deal_value_gbp | Completed transactions; deal value = agreed price (sale) or rent × tenancy months (letting) |
| payments_due, payments_on_time, payments_late_or_overdue | Payments due up to 30 Sep 2026 (scheduled payments excluded) |
| ontime_payment_rate | On-time ÷ due; NULL when nothing was due |
| overdue_now_gbp | Amount still unpaid after its due date at 30 Sep 2026 |

## Coverage (checked on the full data)

| | Customers |
|---|---:|
| All customers | 100,573 |
| With at least one known web session | 95,577 |
| With a viewed price or rent | 75,983 |
| With at least one lead | 60,222 |
| With a decided lead (converted not NULL) | 57,704 (25.9% converted) |
