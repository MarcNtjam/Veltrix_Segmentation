# Veltrix Week 1 (DA) — PostgreSQL + Power BI

Run in pgAdmin, in this order. Open each file with Query Tool > Open File, on database **veltrix** (Day 1: on **postgres**).

| File | Day | What it does | Time |
|---|---|---|---|
| day1_create_database.sql | 1 | Creates the veltrix database | 1 s |
| day2_create_tables_and_load.sql | 2 | 13 tables with primary keys, load CSVs, row-count reconciliation, 17 foreign keys, data dictionary, Day 2 questions | 2–5 min |
| day3_data_quality_audit.sql | 3 | 62 checks into dq.dq_log, profiling, Day 3 questions | ~1 min |
| day4_cleaning_and_baselines.sql | 4 | CASE maps, budget fixes, self-join dedup, UPDATE re-pointing, clean.clean_* tables, re-check, baselines, Power BI check table | ~1–2 min |
| day5_eda.sql | 5 | eda.* views for every chart, Day 5 questions | <30 s |

Also here: `veltrix_theme.json` (Power BI theme), `dax_measures_week1.txt`, `week1_logs_template.xlsx` (business question log + data quality log).
Change the CSV folder in day2 STEP 3 if yours is not `D:/Amdari/Project_veltrix/Marc/data/raw/veltrix_medium` (use forward slashes).
