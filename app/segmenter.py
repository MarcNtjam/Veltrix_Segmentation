"""Load the exported seg-v1.0 model and score customers from raw inputs.

Used by streamlit_app.py; also usable on its own:
    from segmenter import Segmenter
    seg = Segmenter("model")
    seg.score(df)            # df has the raw input columns, see seg.input_columns
"""
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd


class Segmenter:
    def __init__(self, model_dir="model"):
        d = Path(model_dir)
        self.meta = json.loads((d / "model_meta.json").read_text(encoding="utf-8"))
        self.model = joblib.load(d / f"kprototypes_{self.meta['model_version']}.joblib")
        self.profiles = pd.read_csv(d / "segment_profiles.csv")
        self.comparison = pd.read_csv(d / "model_comparison.csv")
        self.num = self.meta["numeric"]
        self.cat = self.meta["categorical"]
        self.money = self.meta["money_log1p"]
        self.ci = list(range(len(self.num), len(self.num) + len(self.cat)))
        self.c2s = {int(k): v for k, v in self.meta["cluster_to_segment"].items()}
        cent = self.model.cluster_centroids_
        self.cent_num = cent[:, :len(self.num)].astype(float)
        self.cent_cat = cent[:, len(self.num):].astype(str)
        self.gamma = float(self.model.gamma)

    @property
    def input_columns(self):
        return self.num + self.cat

    def check(self, df):
        """Problems with an input table: missing columns, and categories the model has never seen."""
        missing = [c for c in self.input_columns if c not in df.columns]
        unseen = {}
        for c in self.cat:
            if c in df.columns:
                bad = sorted(set(df[c].astype(str)) - set(self.meta["categories"][c]))
                if bad:
                    unseen[c] = bad
        return missing, unseen

    def transform(self, df):
        """Raw inputs -> the model's scaled numeric features + categorical strings (same steps as notebook 04)."""
        Z = pd.DataFrame(index=df.index)
        for c in self.num:
            x = pd.to_numeric(df[c], errors="coerce").astype(float)
            if c in self.money:
                x = np.log1p(x.fillna(0).clip(lower=0))      # a budget that does not apply counts as 0
            else:
                x = x.fillna(self.meta["numeric_ranges"][c][1])  # blank -> median of all customers
            Z[c] = (x - self.meta["scaler_mean"][c]) / self.meta["scaler_scale"][c]
        for c in self.cat:
            v = df[c].astype(str)
            if c == "is_overseas":
                v = v.str.strip().str.lower().map({"true": "True", "1": "True", "yes": "True"}).fillna("False")
            Z[c] = v
        return Z

    def distances(self, Z):
        """k-prototypes cost to every segment prototype: squared distance (numeric) + gamma x mismatches (categorical)."""
        zn = Z[self.num].to_numpy(dtype=float)
        zc = Z[self.cat].to_numpy(dtype=str)
        dn = ((zn[:, None, :] - self.cent_num[None, :, :]) ** 2).sum(axis=2)
        dc = (zc[:, None, :] != self.cent_cat[None, :, :]).sum(axis=2)
        return dn + self.gamma * dc

    def score(self, df):
        """Return df with segment_id, segment_name, tier, routing and a fit check (clear / borderline)."""
        Z = self.transform(df)
        clusters = self.model.predict(Z[self.num + self.cat].to_numpy(dtype=object), categorical=self.ci)
        D = self.distances(Z)
        srt = np.sort(D, axis=1)
        out = df.copy()
        out["segment_id"] = [self.c2s[int(c)]["segment_id"] for c in clusters]
        out["segment_name"] = [self.c2s[int(c)]["segment_name"] for c in clusters]
        out["distance_to_segment"] = srt[:, 0].round(2)
        out["distance_to_next"] = srt[:, 1].round(2)
        out["fit"] = np.where(srt[:, 1] - srt[:, 0] >= 1.0, "clear", "borderline")
        cols = ["segment_id", "priority_tier", "routed_desk", "agent_level", "reply_target", "recommended_action"]
        return out.merge(self.profiles[cols], on="segment_id", how="left")

    def segment_distances(self, df_row):
        """Distance from one customer to each segment, named, closest first (for the explanation chart)."""
        D = self.distances(self.transform(df_row))[0]
        names = [self.c2s[i]["segment_name"] for i in range(len(D))]
        return pd.DataFrame({"segment_name": names, "distance": D.round(2)}).sort_values("distance")
