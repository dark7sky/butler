import time
from datetime import date, datetime, time as dt_time, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from sqlalchemy import text
from sqlalchemy.orm import Session

from core.config import settings

LEGACY_SUMMARY_TABLE_ALIASES = {
    "accounts_balance": "portfolio_balance_history",
    "accounts_daydiff": "portfolio_daydiff",
    "accounts_monthdiff": "portfolio_monthdiff",
    "accounts_diff": "accounts_diff",
}
SUMMARY_TABLES = set(LEGACY_SUMMARY_TABLE_ALIASES)

_ACCOUNT_CACHE = {"ts": 0.0, "accounts": []}
_CACHE_TTL_ENV = "ACCOUNT_TABLE_CACHE_TTL_SECONDS"


def _get_cache_ttl() -> int:
    try:
        return max(0, int(settings.__dict__.get(_CACHE_TTL_ENV, 0) or 0))
    except ValueError:
        pass
    try:
        import os

        return max(0, int(os.environ.get(_CACHE_TTL_ENV, "30")))
    except ValueError:
        return 30


def get_app_timezone() -> ZoneInfo | timezone:
    try:
        return ZoneInfo(settings.APP_TIMEZONE)
    except ZoneInfoNotFoundError:
        return timezone.utc


def now_local() -> datetime:
    return datetime.now(get_app_timezone())


def local_day_start(now: datetime | None = None) -> datetime:
    current = now or now_local()
    return datetime.combine(current.date(), dt_time.min, tzinfo=current.tzinfo)


def local_month_start(now: datetime | None = None) -> datetime:
    current = now or now_local()
    month_start = date(current.year, current.month, 1)
    return datetime.combine(month_start, dt_time.min, tzinfo=current.tzinfo)


def to_utc(dt: datetime) -> datetime:
    if dt.tzinfo is None:
        return dt.replace(tzinfo=get_app_timezone()).astimezone(timezone.utc)
    return dt.astimezone(timezone.utc)


def serialize_date(value: date | datetime | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.astimezone(get_app_timezone()).date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return str(value)


def serialize_timestamp(value: datetime | str | None) -> str:
    if value is None:
        return ""
    if isinstance(value, datetime):
        stamp = value.astimezone(get_app_timezone()) if value.tzinfo else value
        return stamp.strftime("%Y-%m-%d %H:%M:%S")
    return str(value).split(".")[0]


def list_accounts(db: Session) -> list[dict]:
    ttl = _get_cache_ttl()
    if ttl > 0 and (time.monotonic() - _ACCOUNT_CACHE["ts"]) < ttl:
        return list(_ACCOUNT_CACHE["accounts"])

    rows = db.execute(
        text(
            """
            SELECT account_key, company, type, name, memo, is_special, is_active
            FROM accounts
            ORDER BY account_key
            """
        )
    ).mappings().all()
    accounts = [dict(row) for row in rows]
    _ACCOUNT_CACHE["ts"] = time.monotonic()
    _ACCOUNT_CACHE["accounts"] = accounts
    return list(accounts)


def list_account_keys(db: Session) -> list[str]:
    return [row["account_key"] for row in list_accounts(db)]


def account_exists(db: Session, account_key: str) -> bool:
    return any(row["account_key"] == account_key for row in list_accounts(db))


def fetch_account_snapshot_rows(db: Session, day_start_utc: datetime) -> list[dict]:
    rows = db.execute(
        text(
            """
            SELECT
                a.account_key,
                a.company,
                a.type,
                a.name,
                a.memo,
                a.is_special,
                a.is_active,
                latest.balance AS latest_balance,
                today.balance AS today_balance,
                yesterday.balance AS yesterday_balance
            FROM accounts a
            LEFT JOIN LATERAL (
                SELECT balance
                FROM account_balance_history h
                WHERE h.account_key = a.account_key
                ORDER BY h.recorded_at DESC
                LIMIT 1
            ) latest ON TRUE
            LEFT JOIN LATERAL (
                SELECT balance
                FROM account_balance_history h
                WHERE h.account_key = a.account_key
                  AND h.recorded_at >= :day_start
                ORDER BY h.recorded_at DESC
                LIMIT 1
            ) today ON TRUE
            LEFT JOIN LATERAL (
                SELECT balance
                FROM account_balance_history h
                WHERE h.account_key = a.account_key
                  AND h.recorded_at < :day_start
                ORDER BY h.recorded_at DESC
                LIMIT 1
            ) yesterday ON TRUE
            ORDER BY a.account_key
            """
        ),
        {"day_start": day_start_utc},
    ).mappings().all()
    return [dict(row) for row in rows]


def resolve_summary_table(requested: str) -> str:
    return LEGACY_SUMMARY_TABLE_ALIASES.get(requested, "portfolio_balance_history")


def fetch_summary_rows(db: Session, requested: str, limit: int) -> list[dict]:
    table_name = resolve_summary_table(requested)
    limit = max(1, min(limit, 200))

    if table_name == "portfolio_balance_history":
        rows = db.execute(
            text(
                """
                SELECT recorded_at AS point_date, balance
                FROM portfolio_balance_history
                ORDER BY recorded_at DESC
                LIMIT :limit
                """
            ),
            {"limit": limit},
        ).mappings().all()
        return [
            {"date": serialize_timestamp(row["point_date"]), "balance": float(row["balance"])}
            for row in rows
        ]

    if table_name == "portfolio_daydiff":
        rows = db.execute(
            text(
                """
                SELECT balance_date AS point_date, balance
                FROM portfolio_daydiff
                ORDER BY balance_date DESC
                LIMIT :limit
                """
            ),
            {"limit": limit},
        ).mappings().all()
        return [
            {"date": serialize_date(row["point_date"]), "balance": float(row["balance"])}
            for row in rows
        ]

    if table_name == "portfolio_monthdiff":
        rows = db.execute(
            text(
                """
                SELECT balance_date AS point_date, balance
                FROM portfolio_monthdiff
                ORDER BY balance_date DESC
                LIMIT :limit
                """
            ),
            {"limit": limit},
        ).mappings().all()
        return [
            {"date": serialize_date(row["point_date"]), "balance": float(row["balance"])}
            for row in rows
        ]

    rows = db.execute(
        text(
            """
            WITH ordered AS (
                SELECT
                    recorded_at,
                    balance - COALESCE(LAG(balance) OVER (ORDER BY recorded_at), balance) AS diff
                FROM portfolio_balance_history
            )
            SELECT recorded_at AS point_date, diff AS balance
            FROM ordered
            ORDER BY point_date DESC
            LIMIT :limit
            """
        ),
        {"limit": limit},
    ).mappings().all()
    return [
        {"date": serialize_timestamp(row["point_date"]), "balance": float(row["balance"])}
        for row in rows
    ]
