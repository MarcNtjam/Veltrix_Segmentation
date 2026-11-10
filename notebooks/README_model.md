# Veltrix notebooks and reports

These notebooks turn the PostgreSQL database built by the Week 1-3 SQL files into the project documents.
Each one connects to **localhost, database veltrix**, asks for the password once (it is never typed into a cell or saved), and writes its outputs to `reports/<folder>/`.

```
D:\Amdari\Project_veltrix\Marc
├── week1\  week2\  week3\        SQL deliverables (run in pgAdmin, one step at a time)
├── notebooks\                    these notebooks + vx.py (shared helpers) + dictionary_text.py
├── reports\                      everything the notebooks write
│   ├── 01_data_quality\  02_eda\  03_data_dictionary\  04_features\
│   └── 05_model\  06_personas\  07_activation\
├── app\                        Streamlit app of the chosen model (notebook 08 fills app\model\)
├── features\customer_features.parquet   model input (written by notebook 04)
├── mlruns\                       MLflow runs (written by notebook 05)
└── restricted\                   answer key: PROJECT LEAD ONLY, never shared or committed
```

## Run order

| # | Notebook | Needs (SQL already run) | Writes (in `reports/`) | Plan deliverable |
|---|---|---|---|---|
| 01 | `01_data_quality.ipynb` | week1 files 1-3 (incl. file 3 STEP 11) | `data_quality_log.csv/.xlsx`, **`Veltrix_data_quality_report.docx`** | Phase 1: data quality log and report |
| 02 | `02_eda_summary.ipynb` | week1 files 1-4 (week3 file 10 STEP 7 for the timing chart) | 13 charts, **`Veltrix_EDA_summary.docx`**, `eda_numbers.json` | Phase 1: EDA summary (10+ charts) |
| 03 | `03_data_dictionary.ipynb` | any | **`Veltrix_data_dictionary.docx`**, `data_dictionary.md/.xlsx` | Phase 1: data dictionary |
| 04 | `04_feature_engineering.ipynb` | week2 file 5 (incl. STEP 6) and file 6 | table **`feat.customer_features_model`**, `features/customer_features.parquet`, **`Veltrix_feature_documentation.docx`** | Phase 2: customer_features table, feature documentation |
| 05 | `05_model_and_validation.ipynb` | notebook 04 | **`customer_segments_seg-v1.0.csv`** (also loaded into `clean.ds_labels_staging`), **`Veltrix_validation_report.docx`** | Phase 3: model notebook, validation report with ARI, chosen segmentation |
| - | **pgAdmin** | | | Switch the dashboard to seg-v1.0: `week2/9_validation_and_swap.sql` STEP 1c, 1d, 2, 3; then re-run week3 files 10-14 (set the test target as noted in file 13 STEP 4); refresh Power BI |
| 08 | `08_export_model.ipynb` | notebook 05 | `app/model/` (fitted model, profiles, comparison) for the **Streamlit app** (see `app/README.md`) | Deployment |
| 06 | `06_personas.ipynb` | week3 files 10-11 | **`Veltrix_persona_deck.pptx`**, **`Veltrix_segment_profile_report.docx`**, `persona_cards.xlsx` | Phase 4: persona deck, segment profile report |
| 07 | `07_activation_and_testing.ipynb` | week3 files 11-14 | **`Veltrix_CRM_fields_and_routing_rules.xlsx`**, `crm_segments_<date>.csv`, **`Veltrix_campaign_plan.xlsx`**, **`Veltrix_dashboard_reconciliation.xlsx`**, **`Veltrix_activation_and_test_report.docx`** | Phase 5: CRM fields and routing rules, campaign plan, dashboard checks, test results |

Open each notebook in Jupyter (Anaconda), then **Kernel > Restart & Run All**. Notebook 05 takes about 10 minutes; the others take under a minute.

## First time only

In Anaconda Prompt:

```
pip install sqlalchemy psycopg2-binary python-docx python-pptx openpyxl seaborn kmodes scikit-learn scipy pyarrow mlflow
```

If your database is not called `veltrix`, or PostgreSQL is not on localhost:5432 with user postgres, set these before starting Jupyter (no code changes needed):

```
set VELTRIX_PG_DB=Veltrix
set VELTRIX_PG_HOST=localhost
set VELTRIX_PG_PORT=5432
set VELTRIX_PG_USER=postgres
```

(The helper also tries `veltrix` and `Veltrix` automatically.)

## Project lead only

Notebooks 01 and 05 contain one step each that reads the answer key in `restricted\answer_key\veltrix_medium\` (01: `duplicate_of` only, for the de-duplication score and the 95% gate; 05: `true_persona`, only after the team has committed to seg-v1.0, for the adjusted Rand index). If the file is not there, those steps are skipped and the reports say so. Never commit the `restricted` folder, the CSVs or the database to git.

## What changed in the SQL files

| File | New step | Creates |
|---|---|---|
| `week1/3_cleaning_and_baselines.sql` | STEP 11: profile look-alikes queued for manual review | `clean.lookalike_base`, `clean.lookalike_weights`, `clean.dedupe_review_queue` (1,000 pairs) |
| | STEP 12: de-duplication scored against `duplicate_of`, with the 95% active-leads gate (**project lead only**) | `restricted.duplicate_key`, `restricted.dedupe_truth` |
| `week2/5_feature_views.sql` | STEP 6: compatibility view with the plan's column names (`budget_gbp`, `sessions_total`, `enquiries_total`, `preferred_region` ...) | `feat.customer_property_type_pref`, `feat.customer_features_ds` (materialized views) |
| `week3/10_segment_profiles.sql` | STEP 7: which segments surged before the April 2025 stamp duty change; when each segment browses | `clean.segment_stamp_duty`, `clean.segment_browsing_hours` |
| `week3/11_tiers_routing_demand.sql` | STEP 5: window-shopper flag and nurture list | `clean.window_shoppers`, `clean.customer_engagement`, `clean.nurture_list` |
| | STEP 6: routing rules as a CRM table | `clean.routing_rules` |
| `week3/13_crm_activation_and_test.sql` | STEP 2d-2f: TikTok and WeChat audiences, reach on all 5 channels | `clean.audience_tiktok`, `clean.audience_wechat`, `clean.audience_reach` |

Run times on a laptop: file 3 STEP 11 about 1-2 minutes on the test machine (allow up to 15), file 5 STEP 6 about 2 minutes, the rest seconds.
