from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import datetime
from typing import Dict, Any, Tuple
import time

from api.deps import get_current_user, get_db
from db.utils import list_account_tables

router = APIRouter()

_ACCOUNTS_CACHE = {"ts": 0.0, "data": None}
_ACCOUNTS_CACHE_TTL_SECONDS = 10

@router.get("/summary")
async def get_dashboard_summary(
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db)
) -> Dict[str, Any]:
    """
    Migrated from summary_data(), summary_month(), and diff_detail()
    Returns a unified JSON response for the dashboard.
    """
    
    today_str = datetime.now().strftime("%Y-%m-%d")
    day_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    day_str = day_start.strftime("%Y-%m-%d %H:%M:%S")

    # --- 1. diff_detail (Today's detailed live changes) ---
    diffs = []
    today_diff = 0
    last_update = ""
    try:
        # PostgreSQL: Get all individual account tables (date/balance columns)
        table_list = list_account_tables(db)

        # Try to get snapshotted today_diff first
        diff_res = db.execute(text("SELECT balance FROM accounts_daydiff WHERE date >= :d ORDER BY date DESC LIMIT 1"), {"d": today_str}).scalar()
        today_diff = float(diff_res) if diff_res is not None else False

        last_update_res = db.execute(text("SELECT date FROM accounts_balance ORDER BY date DESC LIMIT 1")).scalar()
        last_update = str(last_update_res) if last_update_res else ""

        for tab in table_list:
            try:
                # Value at the start of today
                y_val = db.execute(text(f'SELECT balance FROM "{tab}" WHERE date::timestamp < :d ORDER BY date DESC LIMIT 1'), {"d": day_str}).scalar()
                tabval_yesterday = float(y_val) if y_val is not None else 0.0

                # Latest value today
                t_val = db.execute(text(f'SELECT balance FROM "{tab}" WHERE date::timestamp >= :d ORDER BY date DESC LIMIT 1'), {"d": day_str}).scalar()
                if t_val is None:
                    continue
                tabval_today = float(t_val)

                if tabval_today - tabval_yesterday != 0:
                    info = db.execute(text("SELECT account_number, company, type, name, memo FROM accounts_info WHERE account_number = :t"), {"t": tab}).fetchone()
                    if info:
                        diffs.append({"diff": tabval_today - tabval_yesterday, "account": tab, "info": dict(info._mapping)})
                    else:
                        diffs.append({"diff": tabval_today - tabval_yesterday, "account": tab, "info": tab})
            except Exception:
                pass
        
        # If no snapshot in accounts_daydiff, sum up current live diffs
        if today_diff is False:
            today_diff = sum([d["diff"] for d in diffs])

        diffs.sort(key=lambda x: x["diff"], reverse=True)

    except Exception as e:
        last_update = f"Error: {e}"

    # --- 2. summary_data (Historical snapshots) ---
    daily_sums = ["N/A", 0, 0, 0] # last_date, balance_now, diff_day, diff_month
    try:
        # Balance Now
        bal_now = db.execute(text("SELECT date, balance FROM accounts_balance ORDER BY date DESC LIMIT 1")).fetchone()
        if bal_now:
            daily_sums[0] = str(bal_now[0]).split(".")[0]
            daily_sums[1] = float(bal_now[1])
        
        # diff_day: use the live today_diff we just calculated
        daily_sums[2] = today_diff

        # diff_month: latest row from accounts_monthdiff
        mon_diff = db.execute(text("SELECT balance FROM accounts_monthdiff ORDER BY date DESC LIMIT 1")).scalar()
        daily_sums[3] = float(mon_diff) if mon_diff is not None else 0.0

    except Exception:
        pass

    # --- 3. summary_month ---
    month_sums = [0, 0, 0] # balance_now, diff_this_month, avg_12m
    try:
        month_sums[0] = daily_sums[1]
        
        # diff_this_month: try to find today's snapshot, otherwise latest month snapshot
        this_mon_res = db.execute(text("SELECT balance FROM accounts_monthdiff WHERE date >= :d ORDER BY date DESC LIMIT 1"), 
                                  {"d": datetime.now().strftime("%Y-%m-01")}).scalar()
        month_sums[1] = float(this_mon_res) if this_mon_res is not None else daily_sums[3]

        # Avg 12 months
        results = db.execute(text("SELECT balance FROM accounts_monthdiff ORDER BY date DESC LIMIT 13")).fetchall()
        if results:
            temp_sum = -results[0][-1]
            for row in results: temp_sum += row[-1]
            month_sums[2] = float(temp_sum / 12)
    except Exception:
        pass

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
                "accounts_diff": diffs
            }
        }
    }

import io
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from fastapi.responses import StreamingResponse

def make_plot(data: pd.DataFrame, title: str, fmt: str, xlims: list = None) -> io.BytesIO:
    fig, ax = plt.subplots(figsize=(5, 11))
    ax.plot(data["date"], data["balance"], "ko-")
    plt.title(title)
    if xlims is not None:
        plt.xlim(xlims[0], xlims[1])
    plt.grid(True)
    dateFmt = mdates.DateFormatter(fmt)
    ax.xaxis.set_major_formatter(dateFmt)
    
    buf = io.BytesIO()
    plt.savefig(buf, format="png")
    plt.close(fig)
    buf.seek(0)
    return buf

@router.get("/chart_native")
async def get_dashboard_chart_data(
    chart_type: str = "day",
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns raw data for native charts.
    """
    try:
        sql = ""
        if chart_type == "day":
            sql = "SELECT date, balance FROM accounts_balance ORDER BY date DESC LIMIT 100"
        elif chart_type == "month":
            sql = "SELECT date, balance FROM accounts_balance ORDER BY date DESC LIMIT 2000"
        elif chart_type == "year":
            sql = "SELECT date, balance FROM accounts_monthdiff ORDER BY date DESC LIMIT 12"
        else:
            return {"status": "error", "message": "Invalid chart_type"}

        result = db.execute(text(sql)).fetchall()
        
        # Format for JSON: [{"date": "...", "balance": ...}]
        data = []
        for row in result:
            data.append({
                "date": str(row[0]),
                "balance": float(row[1])
            })
            
        # Optional: For day/month we might want to do some server-side filtering 
        # but for now let's send the raw points and let Flutter handle it.
        return {"status": "success", "data": data[::-1]} # reverse to chronological order

    except Exception as e:
        return {"status": "error", "message": str(e)}
@router.get("/accounts")
async def get_all_accounts(
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns a list of all accounts with their latest balance.
    """
    try:
        now = time.monotonic()
        cached = _ACCOUNTS_CACHE.get("data")
        if cached is not None and (now - _ACCOUNTS_CACHE["ts"]) < _ACCOUNTS_CACHE_TTL_SECONDS:
            return {"status": "success", "data": cached}

        day_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
        day_str = day_start.strftime("%Y-%m-%d %H:%M:%S")

        def fetch_latest_and_today_diff(table_name: str) -> Tuple[float, float]:
            try:
                row = db.execute(
                    text(
                        f"""
                        SELECT
                          (SELECT balance FROM "{table_name}" ORDER BY date DESC LIMIT 1) AS latest,
                          (SELECT balance FROM "{table_name}" WHERE date::timestamp >= :d ORDER BY date DESC LIMIT 1) AS today,
                          (SELECT balance FROM "{table_name}" WHERE date::timestamp < :d ORDER BY date DESC LIMIT 1) AS yesterday
                        """
                    ),
                    {"d": day_str},
                ).fetchone()
                if not row:
                    return 0.0, 0.0
                latest_val = float(row[0]) if row[0] is not None else 0.0
                if row[1] is None:
                    return latest_val, 0.0
                yesterday_val = float(row[2]) if row[2] is not None else 0.0
                return latest_val, float(row[1]) - yesterday_val
            except Exception:
                return 0.0, 0.0

        # 1. Get account info
        accounts_info = db.execute(text("SELECT account_number, company, type, name, memo FROM accounts_info")).fetchall()
        
        account_tables = set(list_account_tables(db))
        # 2. Get special tables (toss, etc.)
        special_tables = [t for t in account_tables if not t.isnumeric()]

        acc_list = []
        
        # Add normal accounts
        for acc in accounts_info:
            acc_num = acc[0]
            # Get latest balance only if table exists
            latest_bal = None
            today_diff = 0.0
            if acc_num in account_tables:
                latest_bal, today_diff = fetch_latest_and_today_diff(acc_num)
            acc_list.append({
                "account_number": acc_num,
                "company": acc[1],
                "type": acc[2],
                "name": acc[3],
                "memo": acc[4],
                "latest_balance": float(latest_bal) if latest_bal is not None else 0.0,
                "today_diff": float(today_diff)
            })
            
        # Add special tables
        for tab in sorted(special_tables):
            latest_bal, today_diff = fetch_latest_and_today_diff(tab)
            acc_list.append({
                "account_number": tab,
                "company": tab,
                "type": "Special",
                "name": tab,
                "memo": "Auto-detected special account",
                "latest_balance": float(latest_bal) if latest_bal is not None else 0.0,
                "today_diff": float(today_diff)
            })

        _ACCOUNTS_CACHE["ts"] = time.monotonic()
        _ACCOUNTS_CACHE["data"] = acc_list
        return {"status": "success", "data": acc_list}
    except Exception as e:
        print(f"DEBUG: Error in get_all_accounts: {e}")
        return {"status": "error", "message": str(e), "data": []}

@router.get("/accounts/{account_number}/history")
async def get_account_history(
    account_number: str,
    limit: int = 50,
    current_user: str = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns history for a specific account.
    """
    try:
        # Secure the table name
        # We check if it exists first
        if account_number not in set(list_account_tables(db)):
            return {"status": "error", "message": "Account table not found"}

        result = db.execute(text(f'SELECT date, balance FROM "{account_number}" ORDER BY date DESC LIMIT :l'), {"l": limit}).fetchall()
        
        history = []
        for row in result:
            history.append({
                "date": str(row[0]),
                "balance": float(row[1])
            })
            
        return {"status": "success", "data": history}
    except Exception as e:
        print(f"DEBUG: Error in get_account_history: {e}")
        return {"status": "error", "message": str(e), "data": []}
