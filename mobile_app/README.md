# Event Booking Management — Flutter App

A complete Flutter/Dart mobile application for institutional event booking and management.

## Features

- **Google Sign-In** with role-based access (Admin, Registrar, Faculty, Facility Manager, Marketing, IT, IQAC, Transport)
- **Dashboard** with stats grid, quick actions, and upcoming events
- **Event Management** — create (3-step wizard), list (tabbed by status), detail view
- **Approvals** — Registrar inbox for event approval/rejection with conflict override support
- **Requirements** — Facility, IT, and Marketing service request management
- **Calendar** — TableCalendar view with event markers and daily event list
- **Real-time Chat** — WebSocket-powered group and direct messaging
- **Publications** — Research publication tracker
- **IQAC** — NAAC accreditation file browser (7 criteria with sub-folders)
- **Admin Console** — User management (roles) and venue management

## Tech Stack

| Layer | Technology |
|-------|------------|
| Framework | Flutter 3.x (Dart 3.3+) |
| Navigation | go_router 13 |
| State | Provider + ChangeNotifier |
| HTTP | Dio 5 with interceptors |
| WebSocket | web_socket_channel |
| Auth | google_sign_in + flutter_secure_storage |
| UI | Material 3, Google Fonts Inter |
| Calendar | table_calendar |
| Animations | Built-in Flutter animations |

## Getting Started

### Prerequisites
- Flutter SDK 3.16+
- Dart 3.3+
- Android Studio / Xcode
- Google Sign-In credentials

### Setup

1. **Clone and install dependencies**
   ```bash
   cd artifacts/flutter-app
   flutter pub get
   ```

2. **Configure Google Sign-In**
   - Go to [Google Cloud Console](https://console.cloud.google.com)
   - Create an OAuth 2.0 Client ID (Android + iOS)
   - Android: Add SHA-1 fingerprint, place `google-services.json` in `android/app/`
   - iOS: Update `Info.plist` with your `GIDClientID` and URL scheme

3. **Configure API URL**
   
   In `lib/main.dart`, change:
   ```dart
   const String kApiBaseUrl = 'http://YOUR_API_SERVER:8000';
   ```
   Or pass it via `--dart-define`:
   ```bash
   flutter run --dart-define=API_BASE_URL=https://your-api.example.com
   ```

4. **Run the app**
   ```bash
   # Android
   flutter run -d android

   # iOS
   flutter run -d ios

   # Debug
   flutter run
   ```

### Build for Release

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release
```

## Project Structure

```
lib/
├── main.dart                  # App entry point
├── constants/
│   ├── app_colors.dart        # Color palette + status/role colors
│   ├── app_theme.dart         # Material 3 theme
│   └── app_constants.dart     # Routes, roles, lists
├── models/
│   └── models.dart            # All data models
├── services/
│   ├── api_service.dart       # Dio HTTP client (singleton)
│   └── auth_service.dart      # Google Sign-In + token storage
├── providers/
│   └── auth_provider.dart     # Auth state (ChangeNotifier)
├── router/
│   └── app_router.dart        # GoRouter config + ShellRoute nav
├── widgets/
│   └── common/
│       └── app_widgets.dart   # Shared UI components
└── screens/
    ├── auth/login_screen.dart
    ├── dashboard/dashboard_screen.dart
    ├── events/
    │   ├── events_screen.dart
    │   └── create_event_screen.dart
    ├── approvals/approvals_screen.dart
    ├── requirements/requirements_screen.dart
    ├── calendar/calendar_screen.dart
    ├── chat/
    │   ├── chat_list_screen.dart
    │   └── chat_screen.dart
    ├── publications/publications_screen.dart
    ├── iqac/iqac_screen.dart
    └── admin/admin_screen.dart
```

## API Endpoints Used

All endpoints relative to `/api/v1`:

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | `/auth/google` | Google OAuth login |
| GET | `/events/me` | My events |
| POST | `/events` | Create event |
| POST | `/events/conflicts` | Check venue conflicts |
| GET | `/approvals/inbox` | Pending approvals |
| PATCH | `/approvals/:id` | Approve/reject |
| GET | `/facility/inbox` | Facility requests |
| GET | `/it/requests/me` | IT requests |
| GET | `/marketing/requests/me` | Marketing requests |
| GET | `/calendar/app-events` | All events for calendar |
| GET | `/chat/conversations/me` | Chat list |
| GET | `/chat/conversations/:id/messages` | Messages |
| WS | `/chat/ws?token=<JWT>` | Real-time chat |
| GET | `/publications` | Publications list |
| POST | `/publications` | Add publication |
| GET | `/iqac/files` | IQAC file browser |
| GET | `/users` | User list (admin) |
| GET | `/venues` | Venue list |
| POST | `/venues` | Add venue |

## Design

- **Primary color**: Deep Navy Blue `#1565C0`
- **Accent**: Gold `#FFD54F`
- **Font**: Google Fonts Inter
- **Design system**: Material 3

## Role-Based Access

| Role | Features |
|------|----------|
| `admin` | All features + Admin Console |
| `registrar` | Events, Approvals, All features |
| `faculty` | Events, Requirements, Chat, Calendar, Publications |
| `facility_manager` | Requirements (Facility inbox), Chat |
| `marketing` | Requirements (Marketing inbox), Chat |
| `it` | Requirements (IT inbox), Chat |
| `iqac` | IQAC Data Collection, Events, Chat |
| `transport` | Events, Chat |