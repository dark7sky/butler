import time
from datetime import datetime, timedelta
from typing import Any, Dict

from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.orm import Session

from api.deps import get_current_user, get_db
from db.utils import (
    account_exists,
    fetch_account_snapshot_rows,
    get_app_timezone,
    local_day_start,
    local_month_start,
    now_local,
    serialize_timestamp,
    to_utc,
)

router = APIRouter()

_ACCOUNTS_CACHE = {"ts": 0.0, "data": None}
_ACCOUNTS_CACHE_TTL_SECONDS = 10


def _build_account_payload(rows: list[dict]) -> list[dict]:
    payload = []
    for row in rows:
        latest_balance = float(row["latest_balance"] or 0)
        yesterday_balance = float(row["yesterday_balance"] or 0)
        today_balance = row["today_balance"]
        today_diff = 0.0 if today_balance is None else float(today_balance) - yesterday_balance

        company = row["company"] or (row["account_key"] if row["is_special"] else "")
        account_type = row["type"] or ("Special" if row["is_special"] else "")
        name = row["name"] or row["account_key"]
        memo = row["memo"] or ("Auto-detected special account" if row["is_special"] else "")

        payload.append(
            {
                "account_number": row["account_key"],
                "company": company,
                "type": account_type,
                "name": name,
                "memo": memo,
                "latest_balance": latest_balance,
                "today_diff": today_diff,
            }
        )
    return payload


def _parse_request_datetime(value: str | None, default: datetime) -> datetime:
    if not value:
        return default

    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=get_app_timezone())
    return parsed.astimezone(get_app_timezone())


def _group_balance_rows(rows: list[tuple], chart_type: str) -> list[dict[str, float | str]]:
    grouped: dict[datetime, float] = {}
    timezone = get_app_timezone()

    for recorded_at, balance in rows:
        local_stamp = recorded_at.astimezone(timezone) if recorded_at.tzinfo else recorded_at.replace(tzinfo=timezone)
        if chart_type == "day":
            bucket = local_stamp.replace(minute=0, second=0, microsecond=0)
        else:
            bucket = local_stamp.replace(hour=0, minute=0, second=0, microsecond=0)
        grouped[bucket] = float(balance)

    data: list[dict[str, float | str]] = []
    previous: float | None = None
    for bucket in sorted(grouped):
        current = grouped[bucket]
        diff = 0.0 if previous is None else current - previous
        data.append({"date": bucket.isoformat(sep=" "), "balance": diff})
        previous = current
    return data


@router.get("/summary")
async def get_dashboard_summary(
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Dict[str, Any]:
    current = now_local()
    day_start = to_utc(local_day_start(current))
    month_start = local_month_start(current).date()
    today_date = local_day_start(current).date()

    diffs = []
    today_diff = 0.0
    last_update = ""
    daily_sums = ["N/A", 0.0, 0.0, 0.0]
    month_sums = [0.0, 0.0, 0.0]

    try:
        rows = fetch_account_snapshot_rows(db, day_start)
        for row in rows:
            today_balance = row["today_balance"]
            if today_balance is None:
                continue
            yesterday_balance = float(row["yesterday_balance"] or 0)
            diff_value = float(today_balance) - yesterday_balance
            if diff_value == 0:
                continue
            diffs.append(
                {
                    "diff": diff_value,
                    "account": row["account_key"],
                    "info": {
                        "account_number": row["account_key"],
                        "company": row["company"] or (row["account_key"] if row["is_special"] else ""),
                        "type": row["type"] or ("Special" if row["is_special"] else ""),
                        "name": row["name"] or row["account_key"],
                        "memo": row["memo"] or ("Auto-detected special account" if row["is_special"] else ""),
                    },
                }
            )

        diff_res = db.execute(
            text(
                """
                SELECT balance
                FROM portfolio_daydiff
                WHERE balance_date >= :today_date
                ORDER BY balance_date DESC
                LIMIT 1
                """
            ),
            {"today_date": today_date},
        ).scalar()
        today_diff = float(diff_res) if diff_res is not None else sum(item["diff"] for item in diffs)

        bal_now = db.execute(
            text(
                """
                SELECT recorded_at, balance
                FROM portfolio_balance_history
                ORDER BY recorded_at DESC
                LIMIT 1
                """
            )
        ).fetchone()
        if bal_now:
            daily_sums[0] = serialize_timestamp(bal_now[0])
            last_update = daily_sums[0]
            daily_sums[1] = float(bal_now[1])
            month_sums[0] = float(bal_now[1])

        daily_sums[2] = today_diff

        mon_diff = db.execute(
            text(
                """
                SELECT balance
                FROM portfolio_monthdiff
                ORDER BY balance_date DESC
                LIMIT 1
                """
            )
        ).scalar()
        daily_sums[3] = float(mon_diff) if mon_diff is not None else 0.0

        this_mon_res = db.execute(
            text(
                """
                SELECT balance
                FROM portfolio_monthdiff
                WHERE balance_date >= :month_start
                ORDER BY balance_date DESC
                LIMIT 1
                """
            ),
            {"month_start": month_start},
        ).scalar()
        month_sums[1] = float(this_mon_res) if this_mon_res is not None else daily_sums[3]

        results = db.execute(
            text(
                """
                SELECT balance
                FROM portfolio_monthdiff
                ORDER BY balance_date DESC
                LIMIT 13
                """
            )
        ).fetchall()
        if results:
            temp_sum = -float(results[0][0])
            for row in results:
                temp_sum += float(row[0])
            month_sums[2] = temp_sum / 12

        diffs.sort(key=lambda item: item["diff"], reverse=True)
    except Exception as exc:
        last_update = f"Error: {exc}"

    return {
        "status": "success",
        "data": {
            "summary_daily": {
                "last_date": daily_sums[0],
                "balance_now": daily_sums[1],
                "diff_day": daily_sums[2],
                "diff_month": daily_sums[3],
            },
            "summary_monthly": {
                "balance_now": month_sums[0],
                "diff_this_month": month_sums[1],
                "avg_last_12h_months": month_sums[2],
            },
            "today_detail": {
                "last_update": last_update,
                "today_total_diff": today_diff,
                "accounts_diff": diffs,
            },
        },
    }


@router.get("/chart_native")
async def get_dashboard_chart_data(
    chart_type: str = "day",
    start_at: str | None = None,
    end_at: str | None = None,
    diff_mode: bool = False,
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        end_local = _parse_request_datetime(end_at, now_local())
        default_start = end_local - timedelta(hours=24)
        start_local = _parse_request_datetime(start_at, default_start)
        if start_local > end_local:
            start_local, end_local = end_local, start_local

        if diff_mode and chart_type == "year":
            rows = db.execute(
                text(
                    """
                    SELECT balance_date, balance
                    FROM portfolio_monthdiff
                    WHERE balance_date BETWEEN :start_date AND :end_date
                    ORDER BY balance_date ASC
                    """
                ),
                {
                    "start_date": start_local.date(),
                    "end_date": end_local.date(),
                },
            ).fetchall()
            data = [
                {"date": row[0].isoformat(), "balance": float(row[1])}
                for row in rows
            ]
            return {"status": "success", "data": data}

        start_utc = to_utc(start_local)
        end_utc = to_utc(end_local)
        rows = db.execute(
            text(
                """
                SELECT recorded_at, balance
                FROM portfolio_balance_history
                WHERE recorded_at BETWEEN :start_at AND :end_at
                ORDER BY recorded_at ASC
                """
            ),
            {
                "start_at": start_utc,
                "end_at": end_utc,
            },
        ).fetchall()

        if diff_mode:
            if chart_type not in {"day", "month"}:
                return {"status": "error", "message": "Invalid chart_type"}
            return {"status": "success", "data": _group_balance_rows(rows, chart_type)}

        if chart_type not in {"day", "month", "year"}:
            return {"status": "error", "message": "Invalid chart_type"}

        data = [
            {"date": serialize_timestamp(row[0]), "balance": float(row[1])}
            for row in rows
        ]
        return {"status": "success", "data": data}
    except Exception as exc:
        return {"status": "error", "message": str(exc)}


@router.get("/accounts")
async def get_all_accounts(
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        now_tick = time.monotonic()
        cached = _ACCOUNTS_CACHE.get("data")
        if cached is not None and (now_tick - _ACCOUNTS_CACHE["ts"]) < _ACCOUNTS_CACHE_TTL_SECONDS:
            return {"status": "success", "data": cached}

        day_start = to_utc(local_day_start())
        rows = fetch_account_snapshot_rows(db, day_start)
        payload = _build_account_payload(rows)

        _ACCOUNTS_CACHE["ts"] = now_tick
        _ACCOUNTS_CACHE["data"] = payload
        return {"status": "success", "data": payload}
    except Exception as exc:
        print(f"DEBUG: Error in get_all_accounts: {exc}")
        return {"status": "error", "message": str(exc), "data": []}


@router.get("/accounts/{account_number}/history")
async def get_account_history(
    account_number: str,
    limit: int = 50,
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    try:
        if not account_exists(db, account_number):
            return {"status": "error", "message": "Account not found"}

        rows = db.execute(
            text(
                """
                SELECT recorded_at, balance
                FROM account_balance_history
                WHERE account_key = :account_key
                ORDER BY recorded_at DESC
                LIMIT :limit
                """
            ),
            {"account_key": account_number, "limit": max(1, min(limit, 500))},
        ).fetchall()

        history = [
            {"date": serialize_timestamp(row[0]), "balance": float(row[1])}
            for row in rows
        ]
        return {"status": "success", "data": history}
    except Exception as exc:
        print(f"DEBUG: Error in get_account_history: {exc}")
        return {"status": "error", "message": str(exc), "data": []}
