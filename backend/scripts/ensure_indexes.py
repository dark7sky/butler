import os
import sys

from sqlalchemy import text

APP_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if APP_ROOT not in sys.path:
    sys.path.insert(0, APP_ROOT)

from db.database import SessionLocal

INDEX_STATEMENTS = [
    (
        "idx_account_balance_history_account_recorded_at",
        'CREATE INDEX IF NOT EXISTS "idx_account_balance_history_account_recorded_at" '
        'ON "account_balance_history" ("account_key", "recorded_at" DESC)',
    ),
    (
        "idx_account_balance_history_recorded_at",
        'CREATE INDEX IF NOT EXISTS "idx_account_balance_history_recorded_at" '
        'ON "account_balance_history" ("recorded_at" DESC)',
    ),
    (
        "idx_portfolio_balance_history_recorded_at",
        'CREATE INDEX IF NOT EXISTS "idx_portfolio_balance_history_recorded_at" '
        'ON "portfolio_balance_history" ("recorded_at" DESC)',
    ),
    (
        "idx_portfolio_daydiff_balance_date",
        'CREATE INDEX IF NOT EXISTS "idx_portfolio_daydiff_balance_date" '
        'ON "portfolio_daydiff" ("balance_date" DESC)',
    ),
    (
        "idx_portfolio_monthdiff_balance_date",
        'CREATE INDEX IF NOT EXISTS "idx_portfolio_monthdiff_balance_date" '
        'ON "portfolio_monthdiff" ("balance_date" DESC)',
    ),
]


def main() -> None:
    db = SessionLocal()
    created = 0
    failed = 0
    try:
        for name, statement in INDEX_STATEMENTS:
            try:
                db.execute(text(statement))
                db.commit()
                created += 1
                print(f"[OK] ensured {name}")
            except Exception as exc:
                db.rollback()
                failed += 1
                print(f"[WARN] index failed for {name}: {exc}")
    finally:
        db.close()

    print(f"[OK] index ensure complete. created={created}, failed={failed}")


if __name__ == "__main__":
    main()
