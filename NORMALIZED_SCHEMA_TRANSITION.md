# Normalized Schema Transition Status

Updated: 2026-03-18 (Asia/Seoul)

## Scope
This note summarizes the committed migration from the legacy PostgreSQL account layout
(`accounts_info` + per-account tables + `accounts_*` summary tables) to the normalized schema.
It also records the follow-up utility cleanup completed in `Total_Account_Tracker_210308`.

## Current source of truth
The active PostgreSQL schema is now:
- `accounts`
- `account_balance_history`
- `portfolio_balance_history`
- `portfolio_daydiff`
- `portfolio_monthdiff`
- `manual_inputs` (kept as-is)
- `system_settings` (untouched, backend-generated, not part of the KB migration scope)

Legacy PostgreSQL account tables were dropped after validation.

## Runtime status
Active read/write paths now use the normalized schema only:
- `Total_Account_Tracker_210308/KB.py` writes normalized account snapshots
- `Total_Account_Tracker_210308/cards.py` writes normalized card history
- `220624_Butler/backend` reads normalized account and portfolio history
- `220624_Butler/legacy/butler` readers use the normalized compatibility layer
- `Total_Account_Tracker_210308` utility scripts now query normalized PostgreSQL instead of SQLite `stored.db`

## Verified operational state
The migration and post-drop validation confirmed:
- legacy PostgreSQL account tables removed
- backend summary/accounts/history endpoints still responding
- normalized portfolio summary rebuilt from canonical account history
- latest validated portfolio snapshot during the migration work:
  - timestamp: `2026-03-18 00:00:24` KST
  - balance: `233,609,614`
- card recalculation delta matched the portfolio delta exactly:
  - previous reported total: `232,476,901`
  - current total: `233,609,614`
  - delta: `1,132,713`
  - same delta was explained by `accounts_cards`

## Repository commits
Main backend repo: `220624_Butler`
- `a784c85` Normalize account history schema in backend
- `51bb582` Drop legacy PostgreSQL account tables

Legacy Butler repo: `220624_Butler/legacy/butler`
- `9706422` Switch legacy Butler readers to normalized schema

Tracker / writer repo: `Total_Account_Tracker_210308`
- `af89639` Write normalized account history snapshots
- `3f9f46d` Remove legacy card table dependency
- `25f1e33` Migrate utility scripts to normalized PostgreSQL

## Updated utility scripts
The following scripts were converted to normalized PostgreSQL behavior:
- `normalized_pg.py`
- `ysfunc.py`
- `find_pennies.py`
- `grapher.py`
- `migrate_db.py`
- `sqlite3_to_influxed.py`

Notes:
- `migrate_db.py` is now safe by default: no execution without `--execute`
- `sqlite3_to_influxed.py` now reads normalized PostgreSQL history, but still needs Influx env vars and the optional `influxdb_client` package at runtime
- `ysfunc.py` keeps compatibility-oriented method names, but its implementation is now PostgreSQL-based

## Intentional leftovers / out of scope
These were not treated as active runtime blockers and were left for a later pass:
- `Total_Account_Tracker_210308/left_days.py`
  - separate `account_balance.db` helper, not part of normalized PostgreSQL runtime
- `Total_Account_Tracker_210308/migrate_kb_cards.py`
  - one-off code transformation helper
- `Total_Account_Tracker_210308/optimize_names.py`
  - one-off rename helper

## Recommended order if work resumes later
1. Run `KB.py` after any upstream data-source changes and confirm the latest portfolio snapshot.
2. Use backend API smoke tests (`/api/dashboard/summary`, `/api/dashboard/accounts`, `/api/dashboard/accounts/{id}/history`) after schema-related edits.
3. Treat `account_balance_history` as the canonical history table and rebuild portfolio summaries from it rather than patching summary tables directly.
4. If utility cleanup continues, target the out-of-scope helper scripts listed above rather than re-opening the normalized migration work.
