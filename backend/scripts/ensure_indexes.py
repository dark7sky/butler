import hashlib
import os
import re
import sys
from sqlalchemy import text

APP_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if APP_ROOT not in sys.path:
    sys.path.insert(0, APP_ROOT)

from db.database import SessionLocal
from db.utils import SUMMARY_TABLES, list_account_tables


def _index_name(prefix: str, table: str, column: str) -> str:
    digest = hashlib.md5(f"{table}:{column}".encode("utf-8")).hexdigest()
    safe_table = re.sub(r"[^a-zA-Z0-9_]+", "_", table).strip("_")
    base = f"{prefix}_{safe_table}" if safe_table else prefix
    suffix = digest[:8]
    name = f"{base}_{suffix}"
    if len(name) > 60:
        name = f"{base[:60 - len(suffix) - 1]}_{suffix}"
    return name


def _index_exists(db, table: str, column: str) -> bool:
    result = db.execute(
        text(
            """
            SELECT 1
            FROM pg_index i
            JOIN pg_class t ON t.oid = i.indrelid
            JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(i.indkey)
            JOIN pg_namespace n ON n.oid = t.relnamespace
            WHERE n.nspname = 'public'
              AND t.relname = :table
              AND a.attname = :column
            LIMIT 1
            """
        ),
        {"table": table, "column": column},
    ).scalar()
    return result is not None


def _ensure_index(db, table: str, column: str, prefix: str = "idx") -> str:
    if _index_exists(db, table, column):
        return "skip"
    index_name = _index_name(f"{prefix}_{column}", table, column)
    db.execute(text(f'CREATE INDEX IF NOT EXISTS "{index_name}" ON "{table}" ("{column}")'))
    return "created"


def main() -> None:
    db = SessionLocal()
    created = 0
    skipped = 0
    failed = 0
    try:
        account_tables = list_account_tables(db)
        for table in account_tables:
            try:
                result = _ensure_index(db, table, "date", prefix="idx_date")
                if result == "created":
                    created += 1
                else:
                    skipped += 1
                db.commit()
            except Exception as exc:
                db.rollback()
                failed += 1
                print(f"[WARN] index failed for {table}.date: {exc}")

        for table in sorted(SUMMARY_TABLES):
            try:
                result = _ensure_index(db, table, "date", prefix="idx_date")
                if result == "created":
                    created += 1
                else:
                    skipped += 1
                db.commit()
            except Exception as exc:
                db.rollback()
                failed += 1
                print(f"[WARN] index failed for {table}.date: {exc}")

        try:
            result = _ensure_index(db, "accounts_info", "account_number", prefix="idx_account")
            if result == "created":
                created += 1
            else:
                skipped += 1
            db.commit()
        except Exception as exc:
            db.rollback()
            failed += 1
            print(f"[WARN] index failed for accounts_info.account_number: {exc}")
    finally:
        db.close()

    print(f"[OK] index ensure complete. created={created}, skipped={skipped}, failed={failed}")


if __name__ == "__main__":
    main()
