# Event Booking Mobile App

Flutter mobile client for Event Booking Management.

## Local Run (Server + Client + Mobile)

1. Start backend from [../Server](../Server) on port 8000.
2. For Android emulator, mobile app uses `http://10.0.2.2:8000` by default.
3. For physical Android device, pass your machine LAN IP:

```bash
flutter run -d <device-id> --dart-define=API_BASE_URL=http://<lan-ip>:8000
```

4. Optional: keep local defines in a json file and reuse:

```bash
cp env.local.example.json env.local.json
flutter run -d <device-id> --dart-define-from-file=env.local.json
```

## Google Login Flow

This app uses the same token flow for web/mobile:
1. User signs in with Google.
2. App receives Google ID token.
3. App sends token to backend endpoint `/api/v1/auth/google`.
4. Backend verifies token and returns app JWT + user profile.

## Create New Google Cloud Project (Step-by-Step)

### 1) Create project
1. Open Google Cloud Console.
2. Create a new project (example: `Event Booking Management`).
3. Select that project.

### 2) Configure OAuth consent screen
1. Go to APIs and Services -> OAuth consent screen.
2. Select `External` (or `Internal` for Workspace-only).
3. Fill app name, support email, developer email.
4. Add scopes: `openid`, `email`, `profile`.
5. Add your own account as a Test user.

### 3) Create OAuth clients
Create all three:
1. Web application
2. Android
3. iOS

## Your Project OAuth Values

**Web OAuth Client ID:**
```
1051124848059-c1si7f3i0njmhm2baeit8oacri1cin19.apps.googleusercontent.com
```

**Android OAuth Client ID:**
```
1051124848059-9imqmepcd8m2rppa98nsor5j7bpvsugs.apps.googleusercontent.com
```

**Android Package & SHA-1:**
- Package: `com.example.mobile_app`
- SHA-1: `69:AE:0E:84:7A:53:1D:46:0D:1D:1C:66:CA:4F:EC:03:F3:51:6C:49`

### Web OAuth client
Use this for Flutter web login and backend audience checks.

Set JavaScript origins at least for local:
- `http://localhost`
- `http://localhost:44065`

Copy generated client ID (format `....apps.googleusercontent.com`).

### Android OAuth client
Use these repo values when creating Android OAuth client:
- Package name: `com.example.mobile_app`
- SHA-1/SHA-256: from debug or release keystore

Get debug SHA values:

```bash
cd android
./gradlew signingReport
```

### iOS OAuth client
Use this repo bundle ID when creating iOS OAuth client:
- Bundle ID: `com.example.mobileApp`

Then copy the reversed client ID into both:
- `ios/Flutter/Debug.xcconfig`
- `ios/Flutter/Release.xcconfig`

Example:

```ini
GOOGLE_REVERSED_CLIENT_ID=com.googleusercontent.apps.1234567890-abcxyz
```

## Required App Configuration

### 1) Web fallback meta tag
File `web/index.html` includes:

```html
<meta name="google-signin-client_id" content="REPLACE_WITH_WEB_CLIENT_ID.apps.googleusercontent.com">
```

Replace it with your real Web OAuth client ID.

### 2) Run with dart-define

```bash
flutter run -d chrome \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=GOOGLE_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Notes:
- `GOOGLE_CLIENT_ID`: used by Google Sign-In web client initialization.
- `GOOGLE_SERVER_CLIENT_ID`: used when requesting ID token for backend verification.
- In this architecture, both are typically your Web OAuth client ID.

## Platform Integration Status

Already configured in repo:
1. `android/app/src/main/AndroidManifest.xml`: internet permission is present.
2. `ios/Runner/Info.plist`: URL scheme uses `$(GOOGLE_REVERSED_CLIENT_ID)`.
3. `ios/Flutter/Debug.xcconfig`: has `GOOGLE_REVERSED_CLIENT_ID` placeholder.
4. `ios/Flutter/Release.xcconfig`: has `GOOGLE_REVERSED_CLIENT_ID` placeholder.

## Android Google Sign-In Fix

If Android sign-in fails with `ApiException: 10`, add an Android OAuth client in Google Cloud with:

- Package name: `com.example.mobile_app`
- Debug SHA-1: `69:AE:0E:84:7A:53:1D:46:0D:1D:1C:66:CA:4F:EC:03:F3:51:6C:49`

Then keep using the web client ID for `GOOGLE_CLIENT_ID` and `GOOGLE_SERVER_CLIENT_ID`.
