# Veltrix Week 3 (DA): personas, dashboard and activation

Run in pgAdmin on database **veltrix**, in this order, one STEP at a time. Needs Weeks 1–2.
Every file works on the segmentation in use (clean.segment_in_use): placeholder-A now, seg-v1.0 after the Day 10 switch.
If Week 2 Day 9 or 10 is re-run, re-run Days 11–15 afterwards.

| File | Day | Builds |
|---|---|---|
| day11_segment_profiles.sql | 11 | price_level / days_to_decision, segment_dim, segment_index, segment_channels, segment_profile |
| day12_tiers_routing_demand.sql | 12 | segment_tiers, tier_rules, segment_actions, open_leads_by_tier, segment_demand, demand_report (~2 min) |
| persona_cards.md | 12 | One card per segment (placeholder-A) |
| report_test_checklist.xlsx | 12 | 34 report tests with expected values + outside-user sheet |
| day13_final_model_checks.sql | 13 | segment_movement, final_check (15 reconciled numbers), star-schema list |
| day14_crm_activation_and_test.sql | 14 | crm_export (+counts), audiences (e-mail, Meta, Google), campaign_plan, test settings/assignment/weekly KPI |
| day15_monitoring_and_handover.sql | 15 | monitoring_log, segment_size_baseline, monthly run (16 checks), drift test, 90-day sizing |
| Veltrix_final_presentation.pptx | 15 | Final presentation, 14 slides with speaker notes |
| dashboard_user_guide.md | 15 | User guide for handover |
| dax_measures_week3.txt | 11–14 | New measures, relationships, display folders |
| week3_business_question_log.xlsx | 11–15 | Week 3 questions with checked answers |
