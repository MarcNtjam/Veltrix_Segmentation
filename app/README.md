# Veltrix segmentation app (Streamlit)

Deploys the chosen model, **seg-v1.0** (k-prototypes, k = 6), as a web app with five pages:

| Page | What it does |
|---|---|
| Segments | the 6 segments: size vs deal value, table, persona cards with routing |
| Score a customer | form for one new customer → segment, priority tier, desk, reply target, and how clear the fit is |
| Batch scoring | upload a CSV of customers → scored file to download (for the CRM) |
| Look up a customer | existing customer ID → segment and persona card |
| Model | every model tried (k-means baseline, k-prototypes k = 2-10) and why k = 6 was chosen |

The app needs **no database**: it reads only the files in `model/`, written by `notebooks/08_export_model.ipynb`.

## Files

```
app/
├── streamlit_app.py          the app
├── segmenter.py              loads the model, turns raw inputs into model features, scores
├── requirements.txt          packages for Streamlit Community Cloud
├── .streamlit/config.toml    Veltrix colours
└── model/
    ├── kprototypes_seg-v1.0.joblib   fitted model
    ├── model_meta.json               feature lists, scaler, segment map, allowed values, metrics
    ├── segment_profiles.csv          one row per segment (persona facts, tier, desk, action)
    ├── model_comparison.csv          all models tried
    ├── customer_lookup.csv           customer_id → segment
    └── example_batch.csv             200 customers to test batch scoring
```

## 1. Run it on your laptop

In Anaconda Prompt:

```
cd D:\Amdari\Project_veltrix\Marc\app
pip install streamlit kmodes scikit-learn joblib altair
streamlit run streamlit_app.py
```

The app opens at http://localhost:8501. Stop it with Ctrl+C.

If you re-train or change the model, run `notebooks/08_export_model.ipynb` again first: it rewrites `model/`.

## 2. Deploy it online (Streamlit Community Cloud, free)

1. Create a GitHub repository (private is fine) and upload the whole **`app`** folder, including `model/` and `.streamlit/`.
   Do **not** upload the database, the raw CSVs, the `restricted/` folder or the answer key.
2. Go to https://share.streamlit.io, sign in with GitHub, click **Create app**.
3. Choose the repository and branch; **Main file path**: `app/streamlit_app.py` (or `streamlit_app.py` if the app folder is the repository root).
4. **Deploy**. Streamlit installs `requirements.txt` and gives you a link (`https://<name>.streamlit.app`).
5. To share it with the team only: app **Settings > Sharing**, set it to private and invite their e-mails.

Every push to GitHub redeploys the app automatically.

## Batch file format

One row per customer, these columns (`customer_id` optional, kept in the output):

`budget_gbp, rent_budget_pcm_gbp, sessions_total, night_session_share, virtual_tour_share, enquiries_total, days_since_last_activity, mobile_share, new_build_share, london_share, preferred_region, preferred_property_type, lead_source_primary, finance_type, customer_type, is_overseas, buyer_position, age_band`

* Budgets in £ (purchase) and £ per month (rent); leave the one that does not apply blank or 0.
* Shares between 0 and 1.
* Categories must use the model's values (listed on the Model page). An unknown value still scores, counted as a mismatch, and the app warns you.

The app applies the same steps as notebook 04: log of budgets, scaling with the training mean and standard deviation, then the nearest k-prototypes prototype. The **fit** column is *clear* when the customer is clearly closer to its segment than to the next one, *borderline* otherwise.
