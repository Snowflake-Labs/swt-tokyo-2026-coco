"""Generate synthetic fraud detection data with drift injection.

Outputs Parquet files to data/synthetic/:
    - customer_profiles.parquet
    - merchant_profiles.parquet
    - transactions.parquet
    - prediction_log.parquet (backdated predictions with drift)

Typical usage::

    uv run python demo2/scripts/generate_synthetic_data.py
    uv run python demo2/scripts/generate_synthetic_data.py --fraud-ratio 0.05
    uv run python demo2/scripts/generate_synthetic_data.py --backdate-days 60
"""

from __future__ import annotations

import argparse
import os
import uuid
from pathlib import Path

import numpy as np
import pandas as pd

_SEED: int = 42
_OUTPUT_DIR: Path = Path(__file__).resolve().parent.parent / "data" / "synthetic"

_COUNTRIES: list[str] = ["JP", "US", "GB", "SG", "DE"]
_CHANNELS: list[str] = ["web", "mobile", "pos", "atm"]
_CURRENCIES: list[str] = ["JPY", "USD", "GBP", "SGD", "EUR"]
_SEGMENTS: list[str] = ["individual", "premium", "business", "student"]
_MERCHANT_CATEGORIES: list[str] = [
    "electronics",
    "grocery",
    "travel",
    "restaurant",
    "fuel",
    "entertainment",
    "clothing",
    "health",
]
_RISK_LEVELS: list[str] = ["low", "medium", "high"]


def _make_uuid(rng: np.random.Generator) -> str:
    """Generate a deterministic UUID from the RNG."""
    high = int(rng.integers(0, 2**63))
    low = int(rng.integers(0, 2**63))
    return str(uuid.UUID(int=(high << 64) | low))


def make_customer_profiles(
    rng: np.random.Generator,
    n: int = 1000,
) -> pd.DataFrame:
    """Generate synthetic customer profiles.

    Args:
        rng: NumPy random generator.
        n: Number of customers.

    Returns:
        DataFrame with customer_id, country, account_age_days, customer_segment.
    """
    return pd.DataFrame(
        {
            "customer_id": [_make_uuid(rng) for _ in range(n)],
            "country": rng.choice(_COUNTRIES, n),
            "account_age_days": rng.integers(30, 3650, n),
            "customer_segment": rng.choice(_SEGMENTS, n),
        }
    )


def make_merchant_profiles(
    rng: np.random.Generator,
    n: int = 500,
) -> pd.DataFrame:
    """Generate synthetic merchant profiles.

    Args:
        rng: NumPy random generator.
        n: Number of merchants.

    Returns:
        DataFrame with merchant_id, merchant_country, merchant_category, risk_level.
    """
    return pd.DataFrame(
        {
            "merchant_id": [f"M{i:05d}" for i in range(n)],
            "merchant_country": rng.choice(_COUNTRIES, n),
            "merchant_category": rng.choice(_MERCHANT_CATEGORIES, n),
            "risk_level": rng.choice(_RISK_LEVELS, n, p=[0.6, 0.3, 0.1]),
        }
    )


def make_transactions(
    rng: np.random.Generator,
    customers: pd.DataFrame,
    merchants: pd.DataFrame,
    n: int = 50_000,
    fraud_ratio: float = 0.03,
) -> pd.DataFrame:
    """Generate synthetic transaction data.

    Args:
        rng: NumPy random generator.
        customers: Customer profiles DataFrame.
        merchants: Merchant profiles DataFrame.
        n: Number of transactions.
        fraud_ratio: Fraction of transactions that are fraudulent.

    Returns:
        DataFrame sorted by transaction_ts.
    """
    customer_ids = rng.choice(customers["customer_id"].values, n)
    merchant_ids = rng.choice(merchants["merchant_id"].values, n)

    base_ts = pd.Timestamp("2025-01-01")
    offsets = pd.to_timedelta(rng.integers(0, 180 * 24 * 3600, n), unit="s")
    timestamps = base_ts + offsets

    amounts = np.round(rng.lognormal(mean=4.0, sigma=1.5, size=n), 2)
    amounts = np.clip(amounts, 1.0, 500_000.0)

    countries = rng.choice(_COUNTRIES, n)
    channels = rng.choice(_CHANNELS, n)
    device_ids = [f"DEV{rng.integers(10000, 99999)}" for _ in range(n)]
    currencies = [_CURRENCIES[_COUNTRIES.index(c)] for c in countries]

    n_fraud = int(n * fraud_ratio)
    is_fraud = np.zeros(n, dtype=int)
    fraud_indices = rng.choice(n, n_fraud, replace=False)
    is_fraud[fraud_indices] = 1

    amounts[fraud_indices] = np.round(
        rng.lognormal(mean=7.0, sigma=1.0, size=n_fraud),
        2,
    )
    amounts[fraud_indices] = np.clip(amounts[fraud_indices], 500.0, 500_000.0)

    n_obvious = min(5, n_fraud)
    obvious = fraud_indices[:n_obvious]
    amounts[obvious] = rng.uniform(10_000, 100_000, n_obvious).round(2)
    for idx in obvious:
        cust_country = customers.loc[
            customers["customer_id"] == customer_ids[idx], "country"
        ].values[0]
        other = [c for c in _COUNTRIES if c != cust_country]
        countries[idx] = rng.choice(other)
    high_risk = merchants[merchants["risk_level"] == "high"]["merchant_id"].values
    if len(high_risk) > 0:
        merchant_ids[obvious] = rng.choice(high_risk, n_obvious)

    df = pd.DataFrame(
        {
            "transaction_id": [f"TXN{i:08d}" for i in range(n)],
            "customer_id": customer_ids,
            "merchant_id": merchant_ids,
            "transaction_ts": timestamps,
            "amount": amounts,
            "currency": currencies,
            "country": countries,
            "channel": channels,
            "device_id": device_ids,
            "is_fraud": is_fraud,
        }
    )
    return df.sort_values("transaction_ts").reset_index(drop=True)


def make_prediction_log(
    rng: np.random.Generator,
    transactions: pd.DataFrame,
    backdate_days: int = 60,
    drift_start_day: int = 30,
    model_version: str = "v_baseline",
) -> pd.DataFrame:
    """Generate backdated prediction log with intentional drift.

    The first ``drift_start_day`` days use the normal fraud distribution.
    After that, fraud scores shift upward and the actual fraud rate increases
    from ~3% to ~8%, causing detectable drift in Model Monitor.

    Args:
        rng: NumPy random generator.
        transactions: Transaction DataFrame (is_fraud column required).
        backdate_days: Total days of backdated predictions.
        drift_start_day: Day at which distribution shift begins.
        model_version: Model version string for the log.

    Returns:
        DataFrame with scored_at timestamps backdated from today.
    """
    n = len(transactions)
    now = pd.Timestamp.now().normalize()

    day_offsets = rng.integers(0, backdate_days, n)
    scored_at = pd.to_datetime([now - pd.Timedelta(days=int(d)) for d in day_offsets.tolist()])

    is_drift = day_offsets < drift_start_day  # recent = drift period

    baseline_scores = np.clip(
        rng.beta(1.5, 15.0, size=n),
        0.0,
        1.0,
    )

    drift_scores = np.clip(
        rng.beta(3.0, 8.0, size=n),
        0.0,
        1.0,
    )

    fraud_scores = np.where(is_drift, drift_scores, baseline_scores)
    fraud_scores = np.round(fraud_scores, 6)

    actual_fraud = transactions["is_fraud"].values.copy()
    drift_extra = rng.random(n) < 0.05
    actual_fraud[is_drift & (drift_extra)] = 1

    predictions = (fraud_scores >= 0.5).astype(int)

    return pd.DataFrame(
        {
            "transaction_id": transactions["transaction_id"].values,
            "customer_id": transactions["customer_id"].values,
            "fraud_score": fraud_scores,
            "prediction": predictions,
            "is_fraud": actual_fraud,
            "model_version": model_version,
            "scored_at": scored_at,
        }
    )


def main() -> None:
    """Parse arguments and generate all synthetic datasets."""
    parser = argparse.ArgumentParser(description="Generate synthetic fraud data")
    parser.add_argument("--num-customers", type=int, default=1000)
    parser.add_argument("--num-merchants", type=int, default=500)
    parser.add_argument("--num-transactions", type=int, default=50_000)
    parser.add_argument(
        "--fraud-ratio",
        type=float,
        default=float(os.environ.get("FRAUD_RATIO", "0.03")),
    )
    parser.add_argument(
        "--backdate-days",
        type=int,
        default=60,
        help="Days of backdated prediction log for drift demo (default: 60).",
    )
    parser.add_argument("--output-dir", type=Path, default=_OUTPUT_DIR)
    args = parser.parse_args()

    rng = np.random.default_rng(_SEED)
    print(f"Generating data (seed={_SEED}, fraud_ratio={args.fraud_ratio})...")

    customers = make_customer_profiles(rng, args.num_customers)
    merchants = make_merchant_profiles(rng, args.num_merchants)
    transactions = make_transactions(
        rng,
        customers,
        merchants,
        args.num_transactions,
        args.fraud_ratio,
    )
    prediction_log = make_prediction_log(
        rng,
        transactions,
        backdate_days=args.backdate_days,
    )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    customers.to_parquet(args.output_dir / "customer_profiles.parquet", index=False)
    merchants.to_parquet(args.output_dir / "merchant_profiles.parquet", index=False)
    # Write transaction_ts as string to avoid Parquet ns timestamp precision issues with Iceberg
    transactions_out = transactions.copy()
    transactions_out["transaction_ts"] = transactions_out["transaction_ts"].dt.strftime(
        "%Y-%m-%d %H:%M:%S"
    )
    transactions_out.to_parquet(args.output_dir / "transactions.parquet", index=False)
    # Write scored_at as string to avoid Parquet timestamp precision issues with Snowflake
    prediction_log_out = prediction_log.copy()
    prediction_log_out["scored_at"] = prediction_log_out["scored_at"].dt.strftime(
        "%Y-%m-%d %H:%M:%S"
    )
    prediction_log_out.to_parquet(args.output_dir / "prediction_log.parquet", index=False)

    fraud_count = int(transactions["is_fraud"].sum())
    drift_count = int(
        (
            prediction_log["scored_at"]
            > (pd.Timestamp.now().normalize() - pd.to_timedelta(30, unit="D"))
        ).sum()
    )

    print(f"  customer_profiles:  {len(customers)} rows")
    print(f"  merchant_profiles:  {len(merchants)} rows")
    print(
        f"  transactions:       {len(transactions)} rows "
        f"({fraud_count} fraud, {fraud_count / len(transactions) * 100:.1f}%)"
    )
    print(f"  prediction_log:     {len(prediction_log)} rows ({drift_count} in drift period)")
    print(f"Output: {args.output_dir}")


if __name__ == "__main__":
    main()
