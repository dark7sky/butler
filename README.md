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

## Security incident remediation (GitHub secret alert)
Detailed checklist: `SECURITY.md`

When a cloud credential (for example a Google API key) is detected in the repository:

1. Rotate the key in the provider console first if any running workflows/apps still depend on it.
2. Revoke the exposed key in Google Cloud / Firebase so it cannot be abused.
3. Review provider audit/security logs for suspicious use during the exposed window.
4. Remove credential files from git-tracked content and keep only local copies from templates.
5. Close the GitHub alert as `revoked` after steps 1-4 are complete.

For this workspace, local mobile credential files should remain untracked:
- `ta_watchdog/android/app/google-services.json`
- `ta_watchdog/ios/Runner/GoogleService-Info.plist`
