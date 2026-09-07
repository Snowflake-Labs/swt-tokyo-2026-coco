"""Impact Radar: detect downstream breakage from SQL column removal.

Analyzes staged git changes to SQL files, identifies removed columns,
queries GET_LINEAGE to find affected downstream assets (tables, Dynamic Tables,
Semantic Views, Cortex Agents, external BI), and classifies risk.

Exit codes:
    0: Safe to commit.
    1: HIGH risk detected; commit should be blocked.

Typical usage::

    uv run python demo1/plugins/impact-radar/impact_radar.py
    uv run python demo1/plugins/impact-radar/impact_radar.py \\
        --offline fixtures/fct_orders_drop_two_cols.json
    uv run python demo1/plugins/impact-radar/impact_radar.py \\
        --connection <your_connection>
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

# ---------------------------------------------------------------------------
# Defaults (overridable via env vars or CLI args)
# ---------------------------------------------------------------------------

_DEFAULT_DATABASE = "TSHO_SWT_TOKYO_26"
_DEFAULT_WAREHOUSE = "TSHO_WH_XL"
_DEFAULT_CONNECTION = "default"

DATABASE: str = os.environ.get("DATABASE_NAME", _DEFAULT_DATABASE)
WAREHOUSE: str = os.environ.get("WAREHOUSE_NAME", _DEFAULT_WAREHOUSE)
CONNECTION: str = os.environ.get("SNOWFLAKE_CONNECTION_NAME", _DEFAULT_CONNECTION)

SCHEMA_MAP: dict[str, str] = {
    "staging": "STAGING",
    "marts": "MARTS",
    "ai": "AI",
}

# Domain values returned by ``GET_LINEAGE`` (verified 2026-09-06).
AI_DOMAINS: frozenset[str] = frozenset({"SEMANTIC_VIEW", "CORTEX_AGENT"})
EXTERNAL_DOMAIN: str = "EXTERNAL"
HIGH_RISK_DOMAINS: frozenset[str] = AI_DOMAINS | {EXTERNAL_DOMAIN}

_SQL_KEYWORDS: frozenset[str] = frozenset(
    {
        "SELECT",
        "FROM",
        "WHERE",
        "AND",
        "OR",
        "AS",
        "ON",
        "JOIN",
        "LEFT",
        "RIGHT",
        "INNER",
        "OUTER",
        "GROUP",
        "BY",
        "ORDER",
        "HAVING",
        "CASE",
        "WHEN",
        "THEN",
        "ELSE",
        "END",
        "CREATE",
        "REPLACE",
        "VIEW",
        "TABLE",
        "INT",
        "STRING",
        "FLOAT",
        "DATE",
        "TIMESTAMP",
        "BOOLEAN",
        "NOT",
        "NULL",
        "DEFAULT",
        "COMMENT",
        "SET",
        "USE",
        "ROLE",
        "WAREHOUSE",
        "DATABASE",
        "SCHEMA",
        "IDENTIFIER",
        "IF",
        "EXISTS",
        "TRUNCATE",
        "INSERT",
        "INTO",
        "VALUES",
        "DYNAMIC",
        "TARGET_LAG",
        "SUM",
        "COUNT",
        "AVG",
        "ROUND",
        "MOD",
    }
)


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class RemovedColumn:
    """A column identified as removed in a staged SQL diff."""

    fqn: str
    column: str


@dataclass
class DownstreamHit:
    """A single downstream object/column returned by GET_LINEAGE."""

    target_db: str | None
    target_schema: str | None
    target_name: str
    target_domain: str
    target_column: str | None
    target_namespace: str | None
    distance: int
    source_column: str | None


@dataclass
class ImpactResult:
    """Aggregated impact assessment for one removed column."""

    fqn: str
    column: str
    risk: str  # HIGH / MEDIUM / LOW
    downstream: list[DownstreamHit] = field(default_factory=list)
    reason: str = ""


# ---------------------------------------------------------------------------
# Step 1 – Extract staged changes
# ---------------------------------------------------------------------------


def get_staged_sql_diff() -> str:
    """Return the ``git diff --staged`` output limited to ``*.sql`` files.

    Returns:
        Unified diff text for all staged SQL files, or empty string if none.
    """
    result = subprocess.run(
        ["git", "diff", "--staged", "--", "*.sql"],
        capture_output=True,
        text=True,
        check=False,
    )
    return result.stdout


def parse_diff_files(
    diff_text: str,
) -> dict[str, tuple[set[str], set[str]]]:
    """Parse a unified diff into per-file removed/added identifier sets.

    Args:
        diff_text: Raw output of ``git diff --staged``.

    Returns:
        Mapping of ``{filepath: (removed_ids, added_ids)}``.
    """
    files: dict[str, tuple[set[str], set[str]]] = {}
    current_file: str | None = None

    for line in diff_text.splitlines():
        if line.startswith("diff --git"):
            match = re.search(r"b/(.+\.sql)$", line)
            current_file = match.group(1) if match else None
            if current_file:
                files[current_file] = (set(), set())
        elif current_file and line.startswith("-") and not line.startswith("---"):
            files[current_file][0].update(_extract_identifiers(line[1:]))
        elif current_file and line.startswith("+") and not line.startswith("+++"):
            files[current_file][1].update(_extract_identifiers(line[1:]))

    return files


def _extract_identifiers(line: str) -> set[str]:
    """Extract SQL column-like identifiers from a single diff line.

    SQL keywords are excluded so that only user-defined names remain.

    Args:
        line: A single diff line (str) without the leading ``+``/``-`` prefix.

    Returns:
        set[str]: Upper-cased SQL identifier names found in the line,
        excluding SQL keywords.
    """
    cleaned = re.sub(r"--.*$", "", line).strip()
    if not cleaned:
        return set()
    tokens = re.findall(r"\b([a-zA-Z_][a-zA-Z0-9_]*)\b", cleaned)
    return {t.upper() for t in tokens if t.upper() not in _SQL_KEYWORDS}


# ---------------------------------------------------------------------------
# Step 2 – Resolve fully-qualified name
# ---------------------------------------------------------------------------


def resolve_fqn(filepath: str, database: str = DATABASE) -> str | None:
    """Derive the Snowflake FQN for an object from its file path or contents.

    Resolution order:
        1. Directory name matching ``SCHEMA_MAP`` + filename stem.
        2. ``CREATE [OR REPLACE] (VIEW|TABLE|DYNAMIC TABLE) <fqn>`` in the file.

    Args:
        filepath: Relative path to the SQL file.
        database: Database name to prepend when the FQN is unqualified.

    Returns:
        A ``DB.SCHEMA.OBJECT`` string, or ``None`` if resolution fails.
    """
    parts = Path(filepath).parts
    for part in parts:
        if part.lower() in SCHEMA_MAP:
            schema = SCHEMA_MAP[part.lower()]
            obj_name = Path(filepath).stem.upper()
            return f"{database}.{schema}.{obj_name}"

    try:
        content = Path(filepath).read_text()
        match = re.search(
            r"CREATE\s+(?:OR\s+REPLACE\s+)?(?:VIEW|TABLE|DYNAMIC\s+TABLE)\s+"
            r"([A-Za-z0-9_.]+)",
            content,
            re.IGNORECASE,
        )
        if match:
            name = match.group(1).upper()
            if "." not in name:
                return f"{database}.MARTS.{name}"
            if name.count(".") == 1:
                return f"{database}.{name}"
            return name
    except FileNotFoundError:
        pass

    return None


# ---------------------------------------------------------------------------
# Step 3 – Identify removed columns
# ---------------------------------------------------------------------------


def find_removed_columns(
    files: dict[str, tuple[set[str], set[str]]],
    database: str = DATABASE,
) -> list[RemovedColumn]:
    """Identify columns present in removed lines but absent from added lines.

    Args:
        files: Output of ``parse_diff_files``.
        database: Database name for FQN resolution.

    Returns:
        Sorted list of ``RemovedColumn`` instances.
    """
    removed: list[RemovedColumn] = []
    for filepath, (minus_ids, plus_ids) in files.items():
        dropped = minus_ids - plus_ids
        if not dropped:
            continue
        fqn = resolve_fqn(filepath, database)
        if not fqn:
            continue
        for col in sorted(dropped):
            removed.append(RemovedColumn(fqn=fqn, column=col))
    return removed


# ---------------------------------------------------------------------------
# Step 4 – Query GET_LINEAGE (single round-trip)
# ---------------------------------------------------------------------------


def build_lineage_query(removed: list[RemovedColumn]) -> str:
    """Build a ``UNION ALL`` query that fetches lineage for every removed column.

    A single round-trip avoids latency on stage.

    Args:
        removed: Columns to look up.

    Returns:
        SQL string, or empty string if *removed* is empty.
    """
    parts: list[str] = []
    for rc in removed:
        col_fqn = f"{rc.fqn}.{rc.column}"
        parts.append(
            f"SELECT '{rc.column}' AS src_column,"
            " TARGET_OBJECT_DATABASE, TARGET_OBJECT_SCHEMA, TARGET_OBJECT_NAME,"
            " TARGET_OBJECT_DOMAIN, TARGET_COLUMN_NAME, TARGET_NAMESPACE, DISTANCE"
            f" FROM TABLE(SNOWFLAKE.CORE.GET_LINEAGE('{col_fqn}','COLUMN','DOWNSTREAM',5))"
        )
    if not parts:
        return ""
    return " UNION ALL ".join(parts) + " ORDER BY src_column, DISTANCE"


def run_lineage_query(
    query: str,
    connection: str = CONNECTION,
) -> list[dict[str, Any]]:
    """Execute a lineage query via the ``snow sql`` CLI.

    Args:
        query: SQL to execute.
        connection: Snowflake CLI connection name.

    Returns:
        Parsed JSON rows, or an empty list on failure.
    """
    if not query:
        return []
    result = subprocess.run(
        ["snow", "sql", "-c", connection, "-q", query, "--format", "json"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        print(
            f"WARNING: snow sql failed: {result.stderr[:500]}",
            file=sys.stderr,
        )
        return []
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        print("WARNING: could not parse lineage result", file=sys.stderr)
        return []


# ---------------------------------------------------------------------------
# Step 5-6 – Classify and assess risk
# ---------------------------------------------------------------------------


def classify_downstream(
    removed: list[RemovedColumn],
    lineage_rows: list[dict[str, Any]],
) -> list[ImpactResult]:
    """Match lineage rows to removed columns and assign risk levels.

    Risk levels:
        HIGH: Deleted column reaches a Semantic View, Cortex Agent, or external BI.
        MEDIUM: Deleted column has downstream objects (tables, DTs) but no AI/BI.
        LOW: No downstream at all.

    Args:
        removed: Columns removed from staged SQL.
        lineage_rows: Rows from GET_LINEAGE (or offline fixture).

    Returns:
        One ``ImpactResult`` per removed column.
    """
    results: dict[str, ImpactResult] = {}
    for rc in removed:
        key = f"{rc.fqn}.{rc.column}"
        results[key] = ImpactResult(fqn=rc.fqn, column=rc.column, risk="LOW")

    for row in lineage_rows:
        src_col = row.get("SRC_COLUMN", "")
        domain = (row.get("TARGET_OBJECT_DOMAIN") or "").upper()

        hit = DownstreamHit(
            target_db=row.get("TARGET_OBJECT_DATABASE"),
            target_schema=row.get("TARGET_OBJECT_SCHEMA"),
            target_name=row.get("TARGET_OBJECT_NAME", ""),
            target_domain=domain,
            target_column=row.get("TARGET_COLUMN_NAME"),
            target_namespace=row.get("TARGET_NAMESPACE"),
            distance=row.get("DISTANCE", 0),
            source_column=src_col,
        )

        for ir in results.values():
            if ir.column == src_col:
                ir.downstream.append(hit)
                if domain in HIGH_RISK_DOMAINS:
                    ir.risk = "HIGH"
                    ir.reason = f"Reaches {domain}: {hit.target_name}"
                elif ir.risk != "HIGH":
                    ir.risk = "MEDIUM"
                    ir.reason = f"Has downstream: {hit.target_name} ({domain})"
                break

    return list(results.values())


# ---------------------------------------------------------------------------
# Step 7 – Output
# ---------------------------------------------------------------------------

_RISK_ICON: dict[str, str] = {"HIGH": "[!!]", "MEDIUM": "[!]", "LOW": "[ok]"}


def print_report(results: list[ImpactResult]) -> str:
    """Print a human-readable impact report to stdout.

    Args:
        results: Classified impact results.

    Returns:
        The overall risk level (``HIGH``, ``MEDIUM``, or ``LOW``).
    """
    print("=" * 60)
    print("IMPACT RADAR — Column Removal Analysis")
    print("=" * 60)

    max_risk = "LOW"
    for r in results:
        if r.risk == "HIGH":
            max_risk = "HIGH"
        elif r.risk == "MEDIUM" and max_risk != "HIGH":
            max_risk = "MEDIUM"

        print(f"\n{_RISK_ICON[r.risk]} {r.column} ({r.fqn})")
        print(f"    Risk: {r.risk}")
        if r.reason:
            print(f"    Reason: {r.reason}")
        if r.downstream:
            print(f"    Downstream ({len(r.downstream)}):")
            for d in r.downstream:
                print(f"      - {d.target_name} ({d.target_domain}) @ distance {d.distance}")
                if d.target_column:
                    print(f"        column: {d.target_column}")
        else:
            print("    Downstream: none")

    print(f"\n{'=' * 60}")
    print(f"Overall: {max_risk}")
    if max_risk == "HIGH":
        print("COMMIT BLOCKED: AI assets or external BI would break silently.")
        print("Fix the downstream references or update the metric definitions.")
    print("=" * 60)

    return max_risk


def save_json(results: list[ImpactResult], path: str) -> None:
    """Write the impact results to a JSON file.

    Args:
        results: Classified impact results.
        path: Destination file path.
    """
    with open(path, "w") as f:
        json.dump([asdict(r) for r in results], f, indent=2, default=str)
    print(f"JSON report: {path}")


# ---------------------------------------------------------------------------
# Offline fixture mode
# ---------------------------------------------------------------------------


def load_offline_fixture(
    path: str,
) -> tuple[list[RemovedColumn], list[dict[str, Any]]]:
    """Load a pre-recorded fixture for offline / network-failure demos.

    Args:
        path: Path to the fixture JSON file.

    Returns:
        A tuple of ``(removed_columns, lineage_rows)``.
    """
    with open(path) as f:
        data = json.load(f)
    removed = [RemovedColumn(**r) for r in data["removed_columns"]]
    return removed, data["lineage_rows"]


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main() -> None:
    """Parse arguments and run the impact analysis pipeline."""
    parser = argparse.ArgumentParser(
        description="Impact Radar: column removal risk analysis",
    )
    parser.add_argument(
        "--offline",
        type=str,
        default=None,
        help="Path to offline fixture JSON (skip git/Snowflake).",
    )
    parser.add_argument(
        "--connection",
        default=CONNECTION,
        help=f"Snowflake connection name (default: {CONNECTION}).",
    )
    parser.add_argument(
        "--database",
        default=DATABASE,
        help=f"Database name (default: {DATABASE}).",
    )
    parser.add_argument(
        "--json-output",
        type=str,
        default=None,
        help="Path to write JSON report.",
    )
    args = parser.parse_args()

    if args.offline:
        print(f"[offline mode] Loading fixture: {args.offline}")
        removed, lineage_rows = load_offline_fixture(args.offline)
    else:
        diff_text = get_staged_sql_diff()
        if not diff_text:
            print("No staged SQL changes found.")
            sys.exit(0)

        files = parse_diff_files(diff_text)
        removed = find_removed_columns(files, args.database)
        if not removed:
            print("No column removals detected in staged changes.")
            sys.exit(0)

        print(f"Detected {len(removed)} removed column(s):")
        for rc in removed:
            print(f"  - {rc.column} from {rc.fqn}")

        query = build_lineage_query(removed)
        print("\nQuerying GET_LINEAGE (1 call)...")
        lineage_rows = run_lineage_query(query, args.connection)

    results = classify_downstream(removed, lineage_rows)
    max_risk = print_report(results)

    if args.json_output:
        save_json(results, args.json_output)

    sys.exit(1 if max_risk == "HIGH" else 0)


if __name__ == "__main__":
    main()
