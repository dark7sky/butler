# 220624_Butler Workspace

## Structure
- `backend/`: FastAPI backend (Docker/Compose target)
- `ta_watchdog/`: Flutter app
- `legacy/butler/`: legacy Python bot code and legacy Docker build files (separate git repo)
- `docs/`: project notes and specs
- `logs/`: local runtime logs (ignored by git)

## Notes
- Shared local secrets are managed with root `.env` (ignored by git).
- Backend-specific template: `backend/.env.example`
- Legacy bot template values are documented in root `.env.example`
