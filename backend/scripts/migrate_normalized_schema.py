import os
import sys
from datetime import date, datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import psycopg2.extras
from psycopg2 import sql

APP_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if APP_ROOT not in sys.path:
    sys.path.insert(0, APP_ROOT)

from core.config import settings
from db.database import Base, engine
import db.models  # noqa: F401

OLD_NON_ACCOUNT_TABLES = {
    "accounts_info",
    "accounts_balance",
    "accounts_diff",
    "accounts_daydiff",
    "accounts_monthdiff",
    "manual_inputs",
    "system_settings",
}
KNOWN_SPECIAL_KEYS = {
    "accounts_cards",
    "toss",
    "debt",
    "insurance",
    "lab_private",
    "외화",
    "지역화폐",
    "장기수선충당금",
}
INDEX_STATEMENTS = [
    'CREATE INDEX IF NOT EXISTS "idx_account_balance_history_account_recorded_at" ON "account_balance_history" ("account_key", "recorded_at" DESC)',
    'CREATE INDEX IF NOT EXISTS "idx_account_balance_history_recorded_at" ON "account_balance_history" ("recorded_at" DESC)',
    'CREATE INDEX IF NOT EXISTS "idx_portfolio_balance_history_recorded_at" ON "portfolio_balance_history" ("recorded_at" DESC)',
    'CREATE INDEX IF NOT EXISTS "idx_portfolio_daydiff_balance_date" ON "portfolio_daydiff" ("balance_date" DESC)',
    'CREATE INDEX IF NOT EXISTS "idx_portfolio_monthdiff_balance_date" ON "portfolio_monthdiff" ("balance_date" DESC)',
]


def get_app_timezone() -> ZoneInfo | timezone:
    try:
        return ZoneInfo(settings.APP_TIMEZONE)
    except ZoneInfoNotFoundError:
        return timezone.utc


def parse_legacy_timestamp(raw: object) -> datetime:
    if isinstance(raw, datetime):
        stamp = raw
    else:
        text_value = str(raw).strip()
        try:
            stamp = datetime.fromisoformat(text_value)
        except ValueError:
            stamp = datetime.strptime(text_value, "%Y-%m-%d %H:%M:%S")
    if stamp.tzinfo is None:
        return stamp.replace(tzinfo=get_app_timezone())
    return stamp.astimezone(get_app_timezone())


def chunked(rows: list[tuple], size: int = 2000) -> list[list[tuple]]:
    return [rows[index : index + size] for index in range(0, len(rows), size)]


def list_old_account_tables(cur) -> list[str]:
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
        (list(OLD_NON_ACCOUNT_TABLES),),
    )
    return [row[0] for row in cur.fetchall()]


def determine_special(account_key: str, metadata: dict[str, object] | None) -> bool:
    if account_key in KNOWN_SPECIAL_KEYS:
        return True
    if metadata is None:
        return not account_key.isdigit()
    return (
        not account_key.isdigit()
        and not (metadata.get("company") or metadata.get("type") or metadata.get("name"))
    )


def make_default_metadata(account_key: str) -> dict[str, object]:
    is_special = determine_special(account_key, None)
    return {
        "company": account_key if is_special else "",
        "type": "Special" if is_special else "",
        "name": account_key,
        "memo": "Auto-migrated account" if is_special else "",
        "is_special": is_special,
        "is_active": True,
    }


def rebuild_portfolio_from_history(cur) -> list[tuple[datetime, int]]:
    cur.execute(
        """
        SELECT account_key, recorded_at, balance
        FROM account_balance_history
        ORDER BY recorded_at, account_key
        """
    )
    latest_by_account: dict[str, int] = {}
    total = 0
    current_ts: datetime | None = None
    rows: list[tuple[datetime, int]] = []

    for account_key, recorded_at, balance in cur.fetchall():
        if current_ts is not None and recorded_at != current_ts:
            rows.append((current_ts, total))
        previous = latest_by_account.get(account_key, 0)
        balance_int = int(balance)
        total += balance_int - previous
        latest_by_account[account_key] = balance_int
        current_ts = recorded_at

    if current_ts is not None:
        rows.append((current_ts, total))

    return rows


def build_daydiff_rows(portfolio_rows: list[tuple[datetime, int]]) -> list[tuple[date, int]]:
    day_totals: dict[date, int] = {}
    for recorded_at, balance in portfolio_rows:
        local_date = recorded_at.astimezone(get_app_timezone()).date()
        day_totals[local_date] = int(balance)

    ordered = sorted(day_totals.items())
    diff_rows: list[tuple[date, int]] = []
    previous_total: int | None = None
    for balance_date, total in ordered:
        if previous_total is None:
            previous_total = total
            continue
        diff_rows.append((balance_date, total - previous_total))
        previous_total = total
    return diff_rows


def build_monthdiff_rows(portfolio_rows: list[tuple[datetime, int]]) -> list[tuple[date, int]]:
    month_totals: dict[tuple[int, int], int] = {}
    month_labels: dict[tuple[int, int], date] = {}
    for recorded_at, balance in portfolio_rows:
        local_stamp = recorded_at.astimezone(get_app_timezone())
        month_key = (local_stamp.year, local_stamp.month)
        month_totals[month_key] = int(balance)
        month_labels[month_key] = local_stamp.date()

    ordered_keys = sorted(month_totals)
    diff_rows: list[tuple[date, int]] = []
    previous_total: int | None = None
    for month_key in ordered_keys:
        total = month_totals[month_key]
        if previous_total is None:
            previous_total = total
            continue
        diff_rows.append((month_labels[month_key], total - previous_total))
        previous_total = total
    return diff_rows


def fetch_latest_old_balance(cur, table_name: str) -> int | None:
    cur.execute(
        sql.SQL("SELECT balance FROM {} ORDER BY date DESC LIMIT 1").format(
            sql.Identifier(table_name)
        )
    )
    row = cur.fetchone()
    return None if row is None or row[0] is None else int(row[0])


def print_verification(cur, old_tables: list[str], old_history_rows: int) -> None:
    cur.execute("SELECT COUNT(*) FROM accounts_info")
    old_info_count = int(cur.fetchone()[0])
    cur.execute("SELECT COUNT(*) FROM accounts")
    new_account_count = int(cur.fetchone()[0])
    cur.execute("SELECT COUNT(*) FROM account_balance_history")
    new_history_count = int(cur.fetchone()[0])

    cur.execute("SELECT balance FROM accounts_balance ORDER BY date DESC LIMIT 1")
    old_total = cur.fetchone()
    old_total_value = None if old_total is None else int(old_total[0])
    cur.execute("SELECT balance FROM portfolio_balance_history ORDER BY recorded_at DESC LIMIT 1")
    new_total = cur.fetchone()
    new_total_value = None if new_total is None else int(new_total[0])

    print(f"[VERIFY] accounts_info rows: {old_info_count}")
    print(f"[VERIFY] accounts rows: {new_account_count}")
    print(f"[VERIFY] old account-history rows: {old_history_rows}")
    print(f"[VERIFY] new account_balance_history rows: {new_history_count}")
    print(f"[VERIFY] old latest total: {old_total_value}")
    print(f"[VERIFY] new latest total: {new_total_value}")

    cur.execute("SELECT account_key FROM accounts ORDER BY account_key")
    new_keys = {row[0] for row in cur.fetchall()}
    missing_accounts = [table for table in old_tables if table not in new_keys]
    print(f"[VERIFY] missing account keys: {missing_accounts[:20]}")

    cur.execute(
        """
        SELECT account_key
        FROM accounts
        WHERE account_key NOT IN (
            SELECT DISTINCT account_key FROM account_balance_history
        )
        ORDER BY account_key
        LIMIT 20
        """
    )
    no_history = [row[0] for row in cur.fetchall()]
    print(f"[VERIFY] accounts without history: {no_history}")

    cur.execute(
        """
        SELECT account_key, is_special
        FROM accounts
        ORDER BY is_special DESC, account_key
        """
    )
    numeric_keys: list[str] = []
    special_keys: list[str] = []
    for account_key, is_special in cur.fetchall():
        if is_special and len(special_keys) < 5:
            special_keys.append(account_key)
        elif not is_special and len(numeric_keys) < 5:
            numeric_keys.append(account_key)
        if len(numeric_keys) >= 5 and len(special_keys) >= 5:
            break

    for account_key in numeric_keys + special_keys:
        old_latest = fetch_latest_old_balance(cur, account_key)
        cur.execute(
            """
            SELECT balance
            FROM account_balance_history
            WHERE account_key = %s
            ORDER BY recorded_at DESC
            LIMIT 1
            """,
            (account_key,),
        )
        new_latest = cur.fetchone()
        new_latest_value = None if new_latest is None else int(new_latest[0])
        print(
            f"[VERIFY] {account_key}: old_latest={old_latest} new_latest={new_latest_value}"
        )


def main() -> None:
    Base.metadata.create_all(bind=engine)

    connection = engine.raw_connection()
    try:
        connection.autocommit = False
        cur = connection.cursor()

        for statement in INDEX_STATEMENTS:
            cur.execute(statement)

        old_tables = list_old_account_tables(cur)
        print(f"[INFO] found {len(old_tables)} legacy account tables")

        metadata_by_key: dict[str, dict[str, object]] = {}
        cur.execute(
            "SELECT account_number, company, type, name, memo FROM accounts_info ORDER BY account_number"
        )
        for account_key, company, account_type, name, memo in cur.fetchall():
            metadata_by_key[str(account_key)] = {
                "company": company or "",
                "type": account_type or "",
                "name": name or "",
                "memo": memo or "",
            }

        for table_name in old_tables:
            if table_name not in metadata_by_key:
                metadata_by_key[table_name] = make_default_metadata(table_name)

        account_rows = []
        for account_key, metadata in sorted(metadata_by_key.items()):
            is_special = bool(metadata.get("is_special", determine_special(account_key, metadata)))
            account_rows.append(
                (
                    account_key,
                    metadata.get("company", "") or "",
                    metadata.get("type", "") or "",
                    metadata.get("name", "") or account_key,
                    metadata.get("memo", "") or "",
                    is_special,
                    bool(metadata.get("is_active", True)),
                )
            )

        cur.execute(
            "TRUNCATE TABLE account_balance_history, portfolio_balance_history, portfolio_daydiff, portfolio_monthdiff"
        )
        cur.execute("DELETE FROM accounts")

        psycopg2.extras.execute_values(
            cur,
            """
            INSERT INTO accounts (
                account_key, company, type, name, memo, is_special, is_active
            ) VALUES %s
            ON CONFLICT (account_key) DO UPDATE SET
                company = EXCLUDED.company,
                type = EXCLUDED.type,
                name = EXCLUDED.name,
                memo = EXCLUDED.memo,
                is_special = EXCLUDED.is_special,
                is_active = EXCLUDED.is_active,
                updated_at = now()
            """,
            account_rows,
        )

        old_history_rows = 0
        for table_name in old_tables:
            cur.execute(
                sql.SQL("SELECT date, balance FROM {} ORDER BY date").format(
                    sql.Identifier(table_name)
                )
            )
            source_rows = []
            for raw_date, raw_balance in cur.fetchall():
                if raw_date is None or raw_balance is None:
                    continue
                source_rows.append(
                    (
                        table_name,
                        parse_legacy_timestamp(raw_date),
                        int(raw_balance),
                        f"migration:{table_name}",
                    )
                )
            old_history_rows += len(source_rows)
            for chunk in chunked(source_rows):
                psycopg2.extras.execute_values(
                    cur,
                    """
                    INSERT INTO account_balance_history (
                        account_key, recorded_at, balance, source
                    ) VALUES %s
                    ON CONFLICT (account_key, recorded_at) DO UPDATE SET
                        balance = EXCLUDED.balance,
                        source = EXCLUDED.source
                    """,
                    chunk,
                )

        cur.execute(
            """
            WITH latest AS (
                SELECT DISTINCT ON (account_key)
                    account_key,
                    balance
                FROM account_balance_history
                ORDER BY account_key, recorded_at DESC
            )
            UPDATE accounts AS a
            SET is_active = COALESCE(latest.balance, 0) <> 0,
                updated_at = now()
            FROM latest
            WHERE latest.account_key = a.account_key
            """
        )

        portfolio_rows: list[tuple[datetime, int]] = []
        cur.execute("SELECT date, balance FROM accounts_balance ORDER BY date")
        for raw_date, raw_balance in cur.fetchall():
            if raw_date is None or raw_balance is None:
                continue
            portfolio_rows.append((parse_legacy_timestamp(raw_date), int(raw_balance)))

        if not portfolio_rows:
            print("[WARN] accounts_balance was empty, rebuilding portfolio history from account history")
            portfolio_rows = rebuild_portfolio_from_history(cur)

        for chunk in chunked(portfolio_rows):
            psycopg2.extras.execute_values(
                cur,
                """
                INSERT INTO portfolio_balance_history (recorded_at, balance)
                VALUES %s
                ON CONFLICT (recorded_at) DO UPDATE SET
                    balance = EXCLUDED.balance
                """,
                chunk,
            )

        daydiff_rows = build_daydiff_rows(portfolio_rows)
        monthdiff_rows = build_monthdiff_rows(portfolio_rows)

        for chunk in chunked(daydiff_rows):
            psycopg2.extras.execute_values(
                cur,
                """
                INSERT INTO portfolio_daydiff (balance_date, balance)
                VALUES %s
                ON CONFLICT (balance_date) DO UPDATE SET
                    balance = EXCLUDED.balance
                """,
                chunk,
            )

        for chunk in chunked(monthdiff_rows):
            psycopg2.extras.execute_values(
                cur,
                """
                INSERT INTO portfolio_monthdiff (balance_date, balance)
                VALUES %s
                ON CONFLICT (balance_date) DO UPDATE SET
                    balance = EXCLUDED.balance
                """,
                chunk,
            )

        connection.commit()
        print_verification(cur, old_tables, old_history_rows)
        print("[OK] normalized migration complete")
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


if __name__ == "__main__":
    main()
