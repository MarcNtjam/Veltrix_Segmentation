# Veltrix Week 2 (DA): features, segments and dashboard pages

Run in pgAdmin on database **veltrix**, in this order, one STEP at a time (highlight, F5).
Needs Week 1 Days 2-5 already run.

| File | Day | Builds | Time |
|---|---|---|---|
| day6_feature_views.sql | 6 | schema feat: customer_session_summary, customer_property_view_summary, customer_viewed_prices (table), customer_region_views, region_deals; customer_group on clean_customers | 1-2 min |
| day7_pipeline_features_and_outcomes.sql | 7 | customer_pipeline_features, customer_features (table), customer_outcomes (table), leakage check, stage_order, powerbi_check_week2 | ~1 min |
| feature_documentation.md | 7 | Feature list, definitions, leakage risk (share with DS) | |
| day8_slicers_and_headlines.sql | 8 | calendar, region_label, customer_id on clean_payments, kpi_definitions | <10 s |
| day9_segment_placeholder_and_comparison.sql | 9 | customer_segments (placeholder-A/B), ds_labels_staging, segment_in_use + dashboard_segments, segment_comparison | <10 s |
| day10_validation_and_swap.sql | 10 | Load DS seg-v1.0, chi-square tests (segment_outcome_tests), switch, segment_check | <1 min |
| day10_outcome_tests.py | 10 | Exact p-values + Kruskal-Wallis on revenue (pip install psycopg2-binary sqlalchemy) | <1 min |
| dax_measures_week2.txt | 6-10 | All new DAX measures with expected values | |
| week2_business_question_log.xlsx | 6-10 | Questions with checked answers (Days 9-10 to re-answer on DS segments) | |

If Week 1 Day 4 is ever re-run, re-run Days 6, 7, 9, 10 afterwards.
The segment switch: `UPDATE clean.segment_in_use SET model_version = '<version>';` then Refresh in Power BI.
