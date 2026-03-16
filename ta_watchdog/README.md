# TA Watchdog (Flutter)

## Local Development

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<server-host>:8921
```

## Android Release CI/CD

GitHub Actions workflow:
- `.github/workflows/flutter-android-release.yml`

On push to `main` (when `ta_watchdog/**` changes), the workflow:
1. builds release `AAB` and `APK`
2. uploads artifacts to the workflow run
3. optionally uploads `AAB` to Google Play Internal track

## GitHub Settings Required

Repository Variables:
- `API_BASE_URL` (example: `https://api.yourdomain.com`)
- `PLAY_PACKAGE_NAME` (example: `com.yourcompany.ta_watchdog`)

Repository Secrets:
- `ANDROID_KEYSTORE_BASE64` (base64-encoded upload keystore file)
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (service account JSON text for Play Console API)

If `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` is not set, CI still builds artifacts but skips Play upload.
