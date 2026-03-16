# Security incident remediation checklist (Google API key)

Use this checklist before closing a GitHub secret-scanning alert for a leaked Google API key.

## 1) Rotate first (if still in use)
- Create a replacement API key in Google Cloud / Firebase.
- Apply least-privilege restrictions on the new key before rollout:
  - API restrictions (only required APIs)
  - Application restrictions (Android package/SHA-1, iOS bundle ID, HTTP referrers, or server IPs)
- Deploy the replacement key to all active environments/workflows.
- Verify dependent apps/workflows are healthy.

## 2) Revoke exposed key
- Disable/delete the exposed key in Google Cloud Console.
- Confirm requests with that key are rejected.

## 3) Investigate for misuse
- Review Google Cloud audit logs and API metrics around the exposure window.
- Check for unusual sources, spikes, or unauthorized API calls.
- If suspicious activity is found, escalate incident response and widen credential rotation.

## 4) Clean repository and prevent recurrence
- Remove tracked credential artifacts from git content.
- Keep local-only files untracked:
  - `ta_watchdog/android/app/google-services.json`
  - `ta_watchdog/ios/Runner/GoogleService-Info.plist`
- Keep only template/example files in the repository.

## 5) Close alert
- Close the GitHub alert as **revoked** after steps 1-4 are complete.

## Evidence to attach in PR/incident ticket
- Key rotation timestamp and rollout confirmation.
- Revocation confirmation screenshot/log reference.
- Log review summary and outcome.
- Link to cleanup commit/PR.
