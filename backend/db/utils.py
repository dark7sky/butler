import os
import time
from typing import List, Set

from sqlalchemy import text
from sqlalchemy.orm import Session

SUMMARY_TABLES: Set[str] = {
    "accounts_balance",
    "accounts_daydiff",
    "accounts_monthdiff",
    "accounts_diff",
}

ACCOUNT_EXCLUDED_TABLES: Set[str] = SUMMARY_TABLES | {
    "accounts_info",
    "system_settings",
    "manual_inputs",
}

IGNORE_TABLES_ENV = "ACCOUNT_IGNORE_TABLES"
ACCOUNT_TABLE_CACHE_TTL_ENV = "ACCOUNT_TABLE_CACHE_TTL_SECONDS"

_TABLE_CACHE = {"ts": 0.0, "tables": []}

def _get_cache_ttl() -> int:
    try:
        return max(0, int(os.environ.get(ACCOUNT_TABLE_CACHE_TTL_ENV, "30")))
    except ValueError:
        return 30


def _parse_ignored_tables(value: str | None) -> Set[str]:
    if not value:
        return set()
    items = set()
    for raw in value.split(","):
        name = raw.strip().strip('"').strip("'")
        if name:
            items.add(name)
    return items


def get_excluded_tables() -> Set[str]:
    return ACCOUNT_EXCLUDED_TABLES | _parse_ignored_tables(os.environ.get(IGNORE_TABLES_ENV))


def list_account_tables(db: Session) -> List[str]:
    """Return tables that look like account history tables (date/balance columns)."""
    ttl = _get_cache_ttl()
    if ttl > 0 and (time.monotonic() - _TABLE_CACHE["ts"]) < ttl:
        return list(_TABLE_CACHE["tables"])

    excluded = sorted(get_excluded_tables())
    placeholders = ", ".join([f":e{i}" for i in range(len(excluded))])
    params = {f"e{i}": name for i, name in enumerate(excluded)}

    query = f"""
        SELECT t.table_name
        FROM information_schema.tables t
        WHERE t.table_schema = 'public'
          AND t.table_type = 'BASE TABLE'
          AND t.table_name NOT IN ({placeholders})
          AND EXISTS (
            SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = t.table_schema
              AND c.table_name = t.table_name
              AND c.column_name = 'date'
          )
          AND EXISTS (
            SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = t.table_schema
              AND c.table_name = t.table_name
              AND c.column_name = 'balance'
          )
        ORDER BY t.table_name
    """
    rows = db.execute(text(query), params).fetchall()
    tables = [r[0] for r in rows]
    _TABLE_CACHE["ts"] = time.monotonic()
    _TABLE_CACHE["tables"] = tables
    return tables


def has_date_balance_columns(db: Session, table_name: str) -> bool:
    rows = db.execute(
        text(
            """
            SELECT column_name FROM information_schema.columns
            WHERE table_schema = 'public'
              AND table_name = :t
              AND column_name IN ('date', 'balance')
            """
        ),
        {"t": table_name},
    ).fetchall()
    cols = {r[0] for r in rows}
    return {"date", "balance"}.issubset(cols)
