"""Register an external lineage node via the Snowflake OpenLineage API.

Registers "Q3 Exec Dashboard" (Tableau-equivalent) as an external node
that reads ``DISCOUNT_AMT`` from ``TSHO_SWT_TOKYO_26.MARTS.FCT_ORDERS``.

Typical usage::

    # Dry run — print payload only
    uv run python demo1/scripts/register_external_lineage.py --dry-run

    # POST with PAT
    uv run python demo1/scripts/register_external_lineage.py \\
        --account-url https://MYACCOUNT.snowflakecomputing.com \\
        --token "$SNOWFLAKE_PAT"

    # Delete the registered node
    uv run python demo1/scripts/register_external_lineage.py --delete \\
        --account-url https://MYACCOUNT.snowflakecomputing.com \\
        --token "$SNOWFLAKE_PAT"

Requires:
    INGEST LINEAGE privilege (ACCOUNTADMIN) for POST.
    DELETE LINEAGE privilege (ACCOUNTADMIN) for --delete.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any

_DEFAULT_DATABASE = "TSHO_SWT_TOKYO_26"
_SCHEMA = "MARTS"
_TABLE = "FCT_ORDERS"
_ENDPOINT = "/api/v2/lineage/external-lineage"


def build_openlineage_event(
    database: str,
    schema: str,
    table: str,
) -> dict[str, Any]:
    """Build an OpenLineage COMPLETE event for the external dashboard.

    Args:
        database: Snowflake database name.
        schema: Snowflake schema name.
        table: Snowflake table name.

    Returns:
        A dict representing the OpenLineage RunEvent payload.
    """
    return {
        "eventType": "COMPLETE",
        "eventTime": "2025-06-30T00:00:00Z",
        "producer": "https://tableau.example.com",
        "schemaURL": ("https://openlineage.io/spec/2-0-2/OpenLineage.json#/definitions/RunEvent"),
        "run": {"runId": "impact-radar-demo-001", "facets": {}},
        "job": {
            "namespace": "tableau://bi.example.com",
            "name": "Q3 Exec Dashboard",
            "facets": {},
        },
        "inputs": [
            {
                "namespace": f"snowflake://{database}",
                "name": f"{schema}.{table}",
                "facets": {
                    "columnLineage": {
                        "_producer": "https://tableau.example.com",
                        "_schemaURL": (
                            "https://openlineage.io/spec/facets/1-1-1/"
                            "ColumnLineageDatasetFacet.json"
                            "#/$defs/ColumnLineageDatasetFacet"
                        ),
                        "fields": {
                            col: {
                                "inputFields": [
                                    {
                                        "namespace": f"snowflake://{database}",
                                        "name": f"{schema}.{table}",
                                        "field": col,
                                    }
                                ]
                            }
                            for col in ("DISCOUNT_AMT", "NET_REVENUE")
                        },
                    }
                },
            }
        ],
        "outputs": [],
    }


def post_event(account_url: str, token: str, event: dict[str, Any]) -> None:
    """POST an OpenLineage event to the Snowflake external-lineage endpoint.

    Args:
        account_url: Snowflake account base URL.
        token: Programmatic Access Token (PAT).
        event: OpenLineage RunEvent payload.

    Raises:
        SystemExit: On HTTP error.
    """
    url = account_url.rstrip("/") + _ENDPOINT
    data = json.dumps(event).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
            "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode("utf-8")
            print(f"POST {url} -> {resp.status}")
            if body:
                print(body)
    except urllib.error.HTTPError as e:
        print(f"ERROR: POST {url} -> {e.code}", file=sys.stderr)
        print(e.read().decode("utf-8"), file=sys.stderr)
        sys.exit(1)


def delete_event(account_url: str, token: str) -> None:
    """DELETE the registered external lineage node.

    Args:
        account_url: Snowflake account base URL.
        token: Programmatic Access Token (PAT).

    Raises:
        SystemExit: On HTTP error.
    """
    url = (
        account_url.rstrip("/")
        + _ENDPOINT
        + "?namespace=tableau://bi.example.com&name=Q3+Exec+Dashboard"
    )
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "X-Snowflake-Authorization-Token-Type": "PROGRAMMATIC_ACCESS_TOKEN",
        },
        method="DELETE",
    )
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"DELETE {url} -> {resp.status}")
    except urllib.error.HTTPError as e:
        print(f"ERROR: DELETE {url} -> {e.code}", file=sys.stderr)
        print(e.read().decode("utf-8"), file=sys.stderr)
        sys.exit(1)


def main() -> None:
    """Parse CLI arguments and register/delete external lineage."""
    database = os.environ.get("DATABASE_NAME", _DEFAULT_DATABASE)

    parser = argparse.ArgumentParser(
        description="Register external lineage node via OpenLineage API.",
    )
    parser.add_argument(
        "--delete",
        action="store_true",
        help="Delete the external lineage (requires DELETE LINEAGE).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print payload without sending.",
    )
    parser.add_argument(
        "--database",
        default=database,
        help=f"Database name (default: {database}).",
    )
    parser.add_argument(
        "--account-url",
        default=os.environ.get("SNOWFLAKE_ACCOUNT_URL"),
        help=(
            "Snowflake account URL "
            "(e.g. https://MYACCOUNT.snowflakecomputing.com). "
            "Also reads SNOWFLAKE_ACCOUNT_URL env var."
        ),
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("SNOWFLAKE_PAT"),
        help=(
            "Snowflake PAT. Also reads SNOWFLAKE_PAT env var. "
            "Never commit tokens to the repository."
        ),
    )
    args = parser.parse_args()

    event = build_openlineage_event(args.database, _SCHEMA, _TABLE)

    if args.dry_run:
        print(json.dumps(event, indent=2))
        return

    if not args.account_url or not args.token:
        print(
            "ERROR: --account-url and --token are required "
            "(or set SNOWFLAKE_ACCOUNT_URL / SNOWFLAKE_PAT).",
            file=sys.stderr,
        )
        print("Use --dry-run to print the payload without sending.", file=sys.stderr)
        sys.exit(1)

    if args.delete:
        delete_event(args.account_url, args.token)
    else:
        post_event(args.account_url, args.token, event)


if __name__ == "__main__":
    main()
