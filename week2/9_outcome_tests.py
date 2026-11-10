"""
Day 10 - Outcome tests by segment (SciPy).

Do the segments differ on conversion, revenue and late payment?
  conversion   : chi-square test on won vs lost leads by segment
  late payment : chi-square test on late/overdue vs on-time payments by segment
  revenue      : Kruskal-Wallis test on deal value per customer (customers with a decision)

Run from Anaconda Prompt (once: pip install psycopg2-binary sqlalchemy):
    python day10_outcome_tests.py                 # tests the segmentation in use (clean.segment_in_use)
    python day10_outcome_tests.py placeholder-A   # or any model_version in clean.customer_segments

It asks for the PostgreSQL password (never type it into the file). Results print on screen
and are saved to outcome_tests_<model_version>.csv next to this script.
"""
import sys
import getpass
from pathlib import Path

import numpy as np
import pandas as pd
from scipy import stats
from sqlalchemy import create_engine, text

HOST, PORT, DB, USER = "localhost", 5432, "veltrix", "postgres"


def cramers_v(table: np.ndarray, chi2: float) -> float:
    n = table.sum()
    r, c = table.shape
    return float(np.sqrt(chi2 / (n * (min(r, c) - 1))))


def main() -> None:
    password = getpass.getpass(f"PostgreSQL password for {USER}: ")
    engine = create_engine(f"postgresql+psycopg2://{USER}:{password}@{HOST}:{PORT}/{DB}")

    with engine.connect() as con:
        version = sys.argv[1] if len(sys.argv) > 1 else con.execute(
            text("SELECT model_version FROM clean.segment_in_use")).scalar()
        print(f"\nTesting segmentation: {version}\n")

        conv = pd.read_sql(text("""
            SELECT cs.segment_name,
                   count(*) FILTER (WHERE l.converted)     AS won,
                   count(*) FILTER (WHERE NOT l.converted) AS lost
            FROM clean.customer_segments cs JOIN clean.clean_leads l USING (customer_id)
            WHERE cs.model_version = :v AND l.is_closed = 1
            GROUP BY 1 ORDER BY 1"""), con, params={"v": version})

        late = pd.read_sql(text("""
            SELECT cs.segment_name,
                   count(*) FILTER (WHERE p.is_late_or_overdue = 1) AS late,
                   count(*) FILTER (WHERE p.is_late_or_overdue = 0) AS on_time
            FROM clean.customer_segments cs JOIN clean.clean_payments p USING (customer_id)
            WHERE cs.model_version = :v AND p.status <> 'Scheduled'
            GROUP BY 1 ORDER BY 1"""), con, params={"v": version})

        revenue = pd.read_sql(text("""
            SELECT cs.segment_name, o.deal_value_gbp
            FROM clean.customer_segments cs JOIN feat.customer_outcomes o USING (customer_id)
            WHERE cs.model_version = :v AND o.converted IS NOT NULL"""), con, params={"v": version})

    rows = []

    # 1. Conversion: chi-square on won / lost
    t = conv[["won", "lost"]].to_numpy()
    chi2, p, dof, _ = stats.chi2_contingency(t)
    rate = 100 * conv["won"] / (conv["won"] + conv["lost"])
    rows.append(["Conversion (won vs lost leads)", "chi-square", round(chi2, 1), dof, p,
                 round(cramers_v(t, chi2), 3), round(rate.min(), 1), round(rate.max(), 1)])

    # 2. Late payment: chi-square on late / on time
    t = late[["late", "on_time"]].to_numpy()
    chi2, p, dof, _ = stats.chi2_contingency(t)
    rate = 100 * late["late"] / (late["late"] + late["on_time"])
    rows.append(["Late payment (late or overdue vs on time)", "chi-square", round(chi2, 1), dof, p,
                 round(cramers_v(t, chi2), 3), round(rate.min(), 1), round(rate.max(), 1)])

    # 3. Revenue: Kruskal-Wallis on deal value per customer (many zeros, very skewed -> rank test)
    groups = [g["deal_value_gbp"].to_numpy() for _, g in revenue.groupby("segment_name")]
    h, p = stats.kruskal(*groups)
    n, k = len(revenue), len(groups)
    epsilon_sq = (h - k + 1) / (n - k)          # effect size: 0.01 small, 0.08 medium, 0.26 large
    means = revenue.groupby("segment_name")["deal_value_gbp"].mean()
    rows.append(["Revenue (deal value per customer)", "Kruskal-Wallis", round(h, 1), k - 1, p,
                 round(epsilon_sq, 3), round(means.min(), 0), round(means.max(), 0)])

    out = pd.DataFrame(rows, columns=["outcome", "test", "statistic", "df", "p_value",
                                      "effect_size", "lowest_segment", "highest_segment"])
    out["verdict"] = np.where(out["p_value"] < 0.001, "Segments differ (p < 0.001)", "No clear difference")
    out.insert(0, "model_version", version)

    pd.set_option("display.width", 200)
    print(out.to_string(index=False))
    print("\nEffect size: Cramer's V (0.1 small, 0.3 medium) for chi-square; epsilon-squared "
          "(0.01 small, 0.08 medium) for Kruskal-Wallis.")
    print("lowest/highest_segment = lowest and highest rate (%) or mean deal value (GBP) across segments.")

    path = Path(__file__).with_name(f"outcome_tests_{version}.csv")
    out.to_csv(path, index=False)
    print(f"\nSaved: {path}")


if __name__ == "__main__":
    main()
