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
1. builds release `APK`
2. uploads APK artifact to the workflow run
3. optionally distributes APK to Firebase App Distribution

## GitHub Settings Required

Repository Variables:
- `API_BASE_URL` (example: `https://api.yourdomain.com`)
- `FIREBASE_APP_ID` (example: `1:1234567890:android:abcdef...`)
- `FIREBASE_TESTERS` (example: `your.email@gmail.com`)

Repository Secrets:
- `ANDROID_KEYSTORE_BASE64` (base64-encoded upload keystore file)
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `FIREBASE_SERVICE_ACCOUNT_JSON` (Firebase service account JSON text)

If signing secrets are not set, CI still attempts to build using debug signing.

Firebase distribution is skipped when Firebase vars/secrets are not fully set.
