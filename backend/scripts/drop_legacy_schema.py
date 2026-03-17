import argparse
import os
import sys

from psycopg2 import sql

APP_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if APP_ROOT not in sys.path:
    sys.path.insert(0, APP_ROOT)

from db.database import engine

LEGACY_FIXED_TABLES = {
    "accounts_info",
    "accounts_balance",
    "accounts_diff",
    "accounts_daydiff",
    "accounts_monthdiff",
}

NORMALIZED_TABLES = {
    "accounts",
    "account_balance_history",
    "portfolio_balance_history",
    "portfolio_daydiff",
    "portfolio_monthdiff",
    "manual_inputs",
    "system_settings",
}


def list_existing_tables(cur) -> set[str]:
    cur.execute(
        """
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
        """
    )
    return {row[0] for row in cur.fetchall()}


def verify_normalized_tables(cur) -> dict[str, int]:
    existing = list_existing_tables(cur)
    missing = sorted(NORMALIZED_TABLES - existing)
    if missing:
        raise RuntimeError(f"missing normalized tables: {missing}")

    counts: dict[str, int] = {}
    for table_name in sorted(NORMALIZED_TABLES):
        cur.execute(sql.SQL("SELECT COUNT(*) FROM {}").format(sql.Identifier(table_name)))
        counts[table_name] = int(cur.fetchone()[0])

    for critical in ("accounts", "account_balance_history", "portfolio_balance_history"):
        if counts[critical] <= 0:
            raise RuntimeError(f"critical normalized table is empty: {critical}")

    return counts


def list_legacy_account_tables(cur) -> list[str]:
    excluded = sorted(LEGACY_FIXED_TABLES | NORMALIZED_TABLES)
    cur.execute(
        """
        SELECT t.table_name
        FROM information_schema.tables t
        WHERE t.table_schema = 'public'
          AND t.table_type = 'BASE TABLE'
          AND NOT (t.table_name = ANY(%s))
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
        """,
        (excluded,),
    )
    return [row[0] for row in cur.fetchall()]


def list_drop_targets(cur) -> list[str]:
    existing = list_existing_tables(cur)
    fixed = sorted(existing & LEGACY_FIXED_TABLES)
    dynamic = list_legacy_account_tables(cur)
    return sorted(set(fixed + dynamic))


def print_summary(cur, targets: list[str], counts: dict[str, int]) -> None:
    print("[VERIFY] normalized table counts:")
    for table_name, count in counts.items():
        print(f"  - {table_name}: {count}")

    cur.execute(
        """
        SELECT recorded_at, balance
        FROM portfolio_balance_history
        ORDER BY recorded_at DESC
        LIMIT 1
        """
    )
    latest = cur.fetchone()
    if latest:
        print(f"[VERIFY] latest normalized total: {latest[1]} @ {latest[0]}")

    print(f"[PLAN] drop target count: {len(targets)}")
    for table_name in targets:
        print(f"  - {table_name}")


def drop_targets(cur, targets: list[str]) -> None:
    for table_name in targets:
        cur.execute(sql.SQL("DROP TABLE IF EXISTS {} CASCADE").format(sql.Identifier(table_name)))


def main() -> int:
    parser = argparse.ArgumentParser(description="Drop legacy PostgreSQL account tables after normalized migration.")
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Actually drop the detected legacy tables. Without this flag, only print the plan.",
    )
    args = parser.parse_args()

    with engine.raw_connection() as conn:
        with conn.cursor() as cur:
            counts = verify_normalized_tables(cur)
            targets = list_drop_targets(cur)
            print_summary(cur, targets, counts)

            if not targets:
                print("[OK] no legacy tables remain.")
                conn.rollback()
                return 0

            if not args.execute:
                print("[DRY-RUN] no tables were dropped.")
                conn.rollback()
                return 0

            drop_targets(cur, targets)
            conn.commit()

        with conn.cursor() as cur:
            remaining = list_drop_targets(cur)
            print(f"[VERIFY] remaining legacy table count: {len(remaining)}")
            if remaining:
                raise RuntimeError(f"legacy tables still remain: {remaining}")

    print("[OK] legacy schema drop complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
