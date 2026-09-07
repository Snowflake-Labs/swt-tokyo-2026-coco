"""Upload synthetic Parquet data to Snowflake.

Uploads Parquet files from data/synthetic/ to Snowflake internal stage,
then loads into tables in TSHO_SWT_TOKYO_26.FRAUD.

Typical usage::

    uv run python demo2/scripts/upload_data.py
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from snowflake.snowpark import Session

load_dotenv()

DATA_DIR: Path = Path(__file__).resolve().parent.parent / "data" / "synthetic"
PARQUET_FILES: dict[str, str] = {
    "customer_profiles.parquet": "RAW_CUSTOMER_PROFILES",
    "merchant_profiles.parquet": "RAW_MERCHANT_PROFILES",
    "transactions.parquet": "RAW_TRANSACTIONS",
    "prediction_log.parquet": "PREDICTION_LOG",
}


def get_session() -> Session:
    """Create a Snowpark session using the configured connection."""
    connection_name = os.environ.get("SNOWFLAKE_CONNECTION_NAME", "default")
    return Session.builder.configs({"connection_name": connection_name}).create()


def upload(session: Session) -> None:
    """Upload all Parquet files to Snowflake via PUT + COPY INTO.

    Truncates each target table and clears its stage path before loading
    to ensure idempotent results across repeated runs.

    Args:
        session: Active Snowpark session.
    """
    db = os.environ.get("DATABASE_NAME", "TSHO_SWT_TOKYO_26")
    schema = "FRAUD"
    stage = f"@{db}.{schema}.DATA_STAGE"

    session.sql(f"USE SCHEMA {db}.{schema}").collect()

    for parquet_file, table_name in PARQUET_FILES.items():
        path = DATA_DIR / parquet_file
        if not path.exists():
            print(f"  SKIP {parquet_file}: not found. Run generate_synthetic_data.py first.")
            continue

        try:
            session.sql(f"DESCRIBE TABLE {table_name}").collect()
        except Exception:
            print(f"  WARNING: Table {table_name} does not exist. Skipping.")
            continue

        print(f"  TRUNCATE {table_name}")
        session.sql(f"TRUNCATE TABLE IF EXISTS {table_name}").collect()
        session.sql(f"REMOVE {stage}/{table_name.lower()}/").collect()

        print(f"  PUT {parquet_file} -> {stage}/{table_name.lower()}/")
        session.file.put(
            str(path),
            f"{stage}/{table_name.lower()}",
            auto_compress=False,
            overwrite=True,
        )

        print(f"  COPY INTO {table_name}")
        session.sql(f"""
            COPY INTO {table_name}
            FROM {stage}/{table_name.lower()}/
            FILE_FORMAT = (TYPE = PARQUET)
            MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
            ON_ERROR = ABORT_STATEMENT
            FORCE = TRUE
        """).collect()

        count: int = session.sql(f"SELECT COUNT(*) AS cnt FROM {table_name}").collect()[0]["CNT"]
        print(f"  {table_name}: {count} rows loaded")


def main() -> None:
    """Entry point: parse args, connect, upload, close."""
    parser = argparse.ArgumentParser(description="Upload synthetic data to Snowflake")
    parser.parse_args()

    print("Connecting to Snowflake...")
    session = get_session()

    print("Uploading data...")
    try:
        upload(session)
        print("Upload complete.")
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        session.close()


if __name__ == "__main__":
    main()
