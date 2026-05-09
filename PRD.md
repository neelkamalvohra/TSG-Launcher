# TSG Launcher — Product Requirements Document

**Version:** 1.2  
**Date:** May 9, 2026  
**Status:** Active Development

---

## 1. Product Overview

**TSG Launcher** is an internal Android mobile application for telecom support teams. It acts as a secure, role-aware launcher that aggregates internal web tools (dashboards, portals, NOC apps) into a single tile-based home screen, with live data panels for operational quick-glance information such as the daily engineer roster.

The app is **not distributed via Play Store** — it is sideloaded onto Android devices within the LAN and communicates with backend services hosted on-premises.

---

## 2. Architecture

```
┌─────────────────────────────────────────┐
│   Flutter App  (Android)                │
│   • Login / Biometric lock              │
│   • Tile grid (home screen)             │
│   • Quick panels (Roster / Time / Date) │
│   • Admin panel (CRUD tiles/users)      │
│   • In-app WebView (per tile)           │
└────────────┬───────────────────────────┘
             │ HTTP (LAN)
             ▼
┌────────────────────────────────────────────────────────────┐
│  Docker Compose Stack  (host: 192.168.1.174)               │
│                                                            │
│  ┌──────────────┐   ┌──────────────┐   ┌───────────────┐  │
│  │  tsg_auth    │   │     n8n      │   │  n8n_mysql    │  │
│  │  FastAPI     │   │  Workflow    │   │  MySQL 8.0    │  │
│  │  :8000       │   │  Engine      │   │  :3306        │  │
│  └──────┬───────┘   │  :5555       │   └───────────────┘  │
│         │           └──────────────┘                       │
│  ┌──────▼───────┐   ┌──────────────┐   ┌───────────────┐  │
│  │  postgres_   │   │  postgres_   │   │  redis_cache  │  │
│  │  tsg_auth    │   │  n8n         │   │  :6379        │  │
│  │  :5435       │   │  :5433       │   └───────────────┘  │
│  └──────────────┘   └──────────────┘                       │
└────────────────────────────────────────────────────────────┘
```

---

## 3. Technology Stack

### Mobile (Frontend)
| Layer | Technology | Version |
|---|---|---|
| Framework | Flutter | 3.x (Dart SDK ^3.8.1) |
| State management | Riverpod | 2.6.1 |
| Routing | go_router | 14.8.1 |
| HTTP client | Dio | 5.8.0 |
| WebView | flutter_inappwebview | 6.1.5 |
| Secure storage | flutter_secure_storage | 9.2.4 |
| Biometrics | local_auth | 2.3.0 |
| Image cache | cached_network_image | 3.4.1 |
| Grid layout | flutter_staggered_grid_view | 0.7.0 |
| JWT parsing | dart_jsonwebtoken | 2.14.1 |

### Backend (TSG Auth Service)
| Layer | Technology | Version |
|---|---|---|
| Framework | FastAPI | 0.115.6 |
| Server | Uvicorn | 0.32.1 |
| ORM | SQLAlchemy | 2.0.36 |
| Database | PostgreSQL 16 (postgres_tsg_auth) | — |
| Auth tokens | JWT (HS256) via python-jose | 3.3.0 |
| Password hashing | bcrypt | 4.2.1 |
| Validation | Pydantic v2 | 2.9.2 |
| Container | Docker (python:3.12-slim) | — |

### Automation / Workflow Engine
| Component | Technology |
|---|---|
| Workflow engine | n8n (self-hosted) |
| Workflow data store | PostgreSQL 16 (postgres_n8n) |
| Workflow session cache | Redis 7 |
| Roster data store | MySQL 8.0 (automation_flow DB) |

---

## 4. Features

### 4.1 Authentication
- **Username + password login** — credentials sent to `POST /auth/login`; app receives JWT access token (60-min expiry) + refresh token (30-day expiry) stored securely in device Keystore.
- **Case-insensitive username** — enforced on backend.
- **Token refresh** — silent auto-refresh via `POST /auth/refresh` before expiry.
- **Logout** — calls `POST /auth/logout` to revoke refresh token server-side.
- **Biometric lock** — after app returns from background, user must authenticate via fingerprint/face before the tile screen is shown again. Lock screen auto-triggers on `AppLifecycleState.resumed`.
- **Initial superadmin** — seeded automatically on first backend startup from environment variables.
- **Forced password change** — new users (or users whose password is reset by admin) must change their password on first login before accessing the app.
- **Password expiry (90 days)** — users whose password is older than 90 days are prompted to change it on login. Enforced server-side via `password_changed_at` column.
- **Self-service password reset** — "Forgot Password?" link on login screen. User enters email; backend generates a temporary password and emails it via Gmail SMTP (App Password). Always returns 202 to prevent email enumeration.
- **Admin password reset** — admin can reset any user's password from the Users tab; a temporary password is generated and emailed to the user.
- **Inactivity auto-disable** — APScheduler job runs daily at midnight (IST); disables users who have not logged in for 30+ days (superadmin excluded).

### 4.2 Tile Home Screen
- **Masonry grid layout** — 2-column portrait, 3–5 column landscape; tiles auto-size to their content (no fixed aspect ratio).
- **Per-user tiles** — only tiles assigned to the user's group(s) are shown; fetched from `GET /me/tiles`.
- **Pull-to-refresh** — invalidates both tile list and all quick-info providers.
- **Tile tap** → opens tile's `meta_launch_url` in an embedded in-app WebView.
- **Admin access** — FAB on tiles screen opens Admin Panel (role-gated: `head` and above).
- **Network topology background** — animated star-field / node mesh on login screen; dots + arcs on tile screen.

### 4.3 Quick Panels
Each tile can optionally display a live data panel instead of (or alongside) its icon. Configured per-tile via `quick_panel` field.

| Value | Panel | Description |
|---|---|---|
| `roster` | **Daily Roster Panel** | Fetches today's engineer schedule from n8n webhook; shows shift groups A / B / G / WO / Leave with on-duty count |
| `time` | **Live Clock Panel** | Shows current time (HH:MM) updating every minute, date, and weekday |
| `date` | **Date Panel** | Shows current date (DD-Mon), year, and weekday |
| `null` | **Default** | Tile icon + name + description |

#### Roster Panel Details
- Data source: `GET http://192.168.1.174:5555/webhook/tsglauncher?apikey=...&symbol=ROSTER`
- Response parsed as `TileQuickInfo` → list of `RosterEntry` (employee_name, role, shift)
- Shift groupings: `A`, `A(WH)`, `B`, `B(WH)` → duty; `G` → G shift; `WO` → Week Off; anything else → Leave
- Header and pills are **center-aligned**; shift rows are left-aligned with color-coded labels
- **Refresh:** once per app session (FutureProvider.family); manual refresh via pull-to-refresh

### 4.4 Admin Panel
Accessible to users with role `head` or above. Three tabs:

#### Tiles Tab
- List all tiles in the system
- Create tile (name, slug, launch URL, icon URL, description, quick panel type)
- Edit / delete tile
- Assign tiles to groups

#### Groups Tab
- Create / rename / delete groups
- Assign tiles to group
- Assign/remove users from group

#### Users Tab
- List all users with their groups and status
- Create user (username, password, name, email, groups)
- Edit user (name, email, active/inactive, groups)
- Delete user
- Role-based restrictions: only superadmin can modify admin-level users

### 4.5 Role Hierarchy (RBAC)
Roles are implemented as group names. Level determines permission scope.

| Role | Level | Permissions |
|---|---|---|
| `superadmin` | 7 | Full access; can modify any user including admins |
| `admin` | 6 | Full admin panel; cannot modify superadmin |
| `head` | 5 | Can manage tiles, groups, users below supervisor level |
| `supervisor` | 4 | Can view/manage users at engineer/trainee level |
| `sme` | 3 | Can manage engineer/trainee users |
| `engineer` | 2 | Standard tile access only |
| `trainee` | 1 | Standard tile access only |

### 4.6 In-App WebView
- Launches tile `meta_launch_url` in a full-screen in-app browser
- Back navigation returns to tile grid
- WebView shares cookie session (supports SSO with Authentik)

---

## 5. Data Models

### User
```
id, username (unique, lowercase), email (unique), name,
hashed_password (bcrypt), is_active, is_superadmin, created_at,
must_change_password (bool, default True for new users),
password_changed_at (datetime, updated on every password change),
last_login_at (datetime, updated on every successful login)
→ many-to-many: groups
```

### Group
```
id, name (unique)
→ many-to-many: users, tiles
```

### Tile
```
id, name, slug (unique), meta_launch_url, meta_icon,
meta_description, quick_panel ('roster'|'time'|'date'|null), created_at
→ many-to-many: groups
```

### RefreshToken
```
id, user_id (FK), token (unique), expires_at, created_at
```

### Roster (MySQL — automation_flow DB)
```
roster_automation_flow_roster:
  id, engineer_id (FK), shift_type ('A'|'B'|'G'|'WO'|'Leave'), date

roster_automation_flow_engineers:
  id, name, phone, email, role ('engineer'|'sme')
```

---

## 6. API Reference

### TSG Auth Service — `http://192.168.1.174:8000`

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| GET | `/health` | None | Health check |
| POST | `/auth/login` | None | Login → returns access_token + refresh_token |
| POST | `/auth/refresh` | None | Refresh access token |
| POST | `/auth/logout` | None | Revoke refresh token |
| POST | `/auth/forgot-password` | None | Email temporary password to user (202 always) |
| POST | `/auth/change-password` | Bearer | Change own password (clears must_change flag) |
| GET | `/me` | Bearer | Current user profile + groups |
| GET | `/me/tiles` | Bearer | Tiles visible to current user |
| GET | `/admin/users` | Bearer (manager+) | List all users |
| POST | `/admin/users` | Bearer (manager+) | Create user |
| PATCH | `/admin/users/{pk}` | Bearer (manager+) | Update user |
| DELETE | `/admin/users/{pk}` | Bearer (manager+) | Delete user |
| POST | `/admin/users/{pk}/reset-password` | Bearer (manager+) | Generate temp password and email to user |
| GET | `/admin/groups` | Bearer (manager+) | List all groups |
| POST | `/admin/groups` | Bearer (manager+) | Create group |
| PATCH | `/admin/groups/{pk}` | Bearer (manager+) | Update group |
| DELETE | `/admin/groups/{pk}` | Bearer (manager+) | Delete group |
| POST | `/admin/groups/{pk}/tiles` | Bearer (manager+) | Assign tiles to group |
| POST | `/admin/groups/{pk}/users` | Bearer (manager+) | Assign users to group |
| GET | `/admin/tiles` | Bearer (manager+) | List all tiles |
| POST | `/admin/tiles` | Bearer (manager+) | Create tile |
| PATCH | `/admin/tiles/{slug}` | Bearer (manager+) | Update tile |
| DELETE | `/admin/tiles/{slug}` | Bearer (manager+) | Delete tile |

### n8n Roster Webhook — `http://192.168.1.174:5555`

| Method | Endpoint | Description |
|---|---|---|
| GET | `/webhook/tsglauncher?apikey=e03fc53524454ab8b65d91b23c669cc5&symbol=ROSTER` | Returns today's roster |

**Response:**
```json
{
  "symbol": "ROSTER",
  "name": "Daily-Roster",
  "datetime": "2026-04-28T08:00:00.000Z",
  "engineers": [
    { "id": 101, "employee_name": "Deepa Menon", "role": "engineer", "shift": "A", "date": "2026-04-28" }
  ]
}
```

---

## 7. Infrastructure & Configuration

### Environment Variables (`.env` at project root)

```env
# MySQL
MYSQL_ROOT_PASSWORD=CHANGE_ME_mysql_root_password
MYSQL_DATABASE=automation_flow
MYSQL_USER=n8n_user
MYSQL_PASSWORD=n8n_password

# PostgreSQL — n8n internal
POSTGRES_N8N_USER=n8n_user
POSTGRES_N8N_PASSWORD=n8n_password
POSTGRES_N8N_DB=n8n_db

# PostgreSQL — TSG Auth
TSG_AUTH_PG_USER=tsg_auth
TSG_AUTH_PG_PASSWORD=<secret>
TSG_AUTH_PG_DB=tsg_auth

# TSG Auth service
TSG_AUTH_JWT_SECRET=<secret>
TSG_AUTH_INIT_SUPERADMIN_USERNAME=superadmin
TSG_AUTH_INIT_SUPERADMIN_PASSWORD=<secret>
TSG_AUTH_INIT_SUPERADMIN_EMAIL=superadmin@tsg.local

# SMTP (Gmail App Password — NOT your regular Gmail password)
TSG_AUTH_SMTP_PASSWORD=<gmail-app-password>

# Timezone
TZ=Asia/Calcutta
```

> **SMTP note:** `TSG_AUTH_SMTP_PASSWORD` must be a Gmail **App Password** (16 chars, no spaces),
> generated at https://myaccount.google.com/apppasswords. Regular Gmail passwords are rejected by Google (SMTP 535).

### Flutter App Configuration
File: `tsg_launcher/lib/core/auth/auth_service.dart`
```dart
class AppConfig {
  static const String tsgAuthBaseUrl = 'http://192.168.1.174:8000';
}
```
> Update this IP when deploying to a different server.

### JWT Token Settings (tsg_auth)
- **Access token expiry:** 60 minutes
- **Refresh token expiry:** 30 days
- **Algorithm:** HS256

---

## 8. Common Commands

### 8.1 Docker — Start / Stop All Services

```powershell
# Start all services
cd D:\Neel\ElectronProject\TSG_Application
docker compose up -d

# Stop all services
docker compose down

# View running containers and health
docker compose ps

# View logs for a specific service
docker compose logs -f tsg_auth
docker compose logs -f n8n
```

### 8.2 TSG Auth Backend — Rebuild & Restart

```powershell
cd D:\Neel\ElectronProject\TSG_Application

# Rebuild and restart only the auth service (after code changes)
docker compose up -d --build tsg_auth

# View live logs
docker compose logs -f tsg_auth

# Run database migration manually (add new column etc.)
docker exec tsg_auth python -c "from app.database import engine, Base; from app import models; Base.metadata.create_all(bind=engine)"
```

### 8.3 Flutter App — Build & Install

```powershell
cd D:\Neel\ElectronProject\TSG_Application\tsg_launcher

# Get / update dependencies
flutter pub get

# Build debug APK
flutter build apk --debug

# Build release APK (requires signing config)
flutter build apk --release

# Install directly to connected device / emulator
flutter install

# Run in development mode (hot reload)
flutter run -d emulator-5554

# Run on a real connected device
flutter run -d <device-id>

# List available devices
flutter devices

# APK output path
# build\app\outputs\flutter-apk\app-debug.apk
# build\app\outputs\flutter-apk\app-release.apk
```

### 8.4 Sideload APK to Android Device

```powershell
# Via ADB (USB or WiFi-ADB)
adb install build\app\outputs\flutter-apk\app-debug.apk

# Force reinstall (keeps data)
adb install -r build\app\outputs\flutter-apk\app-debug.apk

# Install over WiFi (after enabling wireless debugging on device)
adb connect <device-ip>:5555
adb install -r build\app\outputs\flutter-apk\app-debug.apk

# List connected ADB devices
adb devices
```

### 8.5 MySQL — Roster Data

```powershell
# Open MySQL shell in container
docker exec -it n8n_mysql mysql -u root -pCHANGE_ME_mysql_root_password automation_flow

# Quick query — today's roster
docker exec n8n_mysql mysql -u root -pCHANGE_ME_mysql_root_password automation_flow \
  -e "SELECT e.name, r.shift_type FROM roster_automation_flow_roster r JOIN roster_automation_flow_engineers e ON e.id = r.engineer_id WHERE r.date = CURDATE() ORDER BY r.shift_type;"

# Copy and run a SQL seed file
docker cp "C:\Temp\seed.sql" n8n_mysql:/tmp/seed.sql
docker exec n8n_mysql mysql -u root -pCHANGE_ME_mysql_root_password automation_flow -e "source /tmp/seed.sql"
```

### 8.6 PostgreSQL — TSG Auth Database

```powershell
# Open psql shell
docker exec -it postgres_tsg_auth psql -U tsg_auth -d tsg_auth

# Quick queries
docker exec postgres_tsg_auth psql -U tsg_auth -d tsg_auth -c "\dt"
docker exec postgres_tsg_auth psql -U tsg_auth -d tsg_auth -c "SELECT username, is_superadmin FROM users;"
docker exec postgres_tsg_auth psql -U tsg_auth -d tsg_auth -c "SELECT name FROM groups;"
docker exec postgres_tsg_auth psql -U tsg_auth -d tsg_auth -c "SELECT name, slug, quick_panel FROM tiles;"
```

### 8.7 Test Webhook

```powershell
# Test ROSTER webhook
Invoke-RestMethod -Uri "http://192.168.1.174:5555/webhook/tsglauncher?apikey=e03fc53524454ab8b65d91b23c669cc5&symbol=ROSTER" | ConvertTo-Json -Depth 4

# Test TSG Auth health
Invoke-RestMethod -Uri "http://192.168.1.174:8000/health"
```

### 8.8 Generate App Icons (after design change)

```powershell
# Requires Python + Pillow
pip install Pillow
python C:\Temp\gen_tsg_icon.py
# Icons written directly to all mipmap-* folders
```

---

## 9. File Structure

```
TSG_Application/
├── docker-compose.yml           ← All services defined here
├── .env                         ← Secrets & env vars (not committed)
├── volumes/                     ← Docker persistent data
│   ├── mysql/
│   ├── postgres_n8n/
│   ├── postgres_tsg_auth/
│   ├── n8n/
│   └── redis/
│
├── tsg_auth/                    ← FastAPI backend
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/
│       ├── main.py              ← FastAPI app entry point
│       ├── models.py            ← SQLAlchemy ORM (User/Group/Tile/Token)
│       ├── schemas.py           ← Pydantic request/response schemas
│       ├── security.py          ← JWT + bcrypt
│       ├── config.py            ← Settings from env vars
│       ├── database.py          ← DB session factory
│       ├── deps.py              ← Auth dependencies + role guards
│       └── routers/
│           ├── auth.py          ← /auth/login, /auth/refresh, /auth/logout
│           ├── me.py            ← /me, /me/tiles
│           └── admin.py         ← /admin/users, /admin/groups, /admin/tiles
│
└── tsg_launcher/                ← Flutter Android app
    ├── pubspec.yaml
    ├── android/
    │   └── app/src/main/
    │       ├── AndroidManifest.xml   ← App name = "TSG"
    │       └── res/mipmap-*/         ← App icons (all sizes)
    └── lib/
        ├── main.dart
        ├── app.dart             ← MaterialApp + Riverpod root
        ├── core/
        │   ├── auth/
        │   │   ├── auth_provider.dart    ← Riverpod auth state machine
        │   │   ├── auth_service.dart     ← AppConfig (server IP)
        │   │   └── biometric_service.dart
        │   ├── models/
        │   │   ├── tile_model.dart
        │   │   ├── user_model.dart
        │   │   └── role.dart            ← Role enum + level hierarchy
        │   ├── routing/
        │   │   └── router.dart          ← GoRouter + auth guards
        │   └── tsg_auth/
        │       └── tsg_auth_service.dart ← HTTP client for all API calls
        └── features/
            ├── auth/
            │   ├── login_screen.dart          ← Login UI + "Forgot Password?" link
            │   ├── forgot_password_screen.dart ← Self-service password reset
            │   ├── change_password_screen.dart ← Forced/expired password change
            │   └── biometric_lock_screen.dart
            ├── tiles/
            │   ├── tiles_screen.dart     ← Masonry grid home screen
            │   ├── tiles_provider.dart   ← FutureProvider for tile list
            │   ├── tile_card.dart        ← Tile widget (default/roster/time/date)
            │   └── tile_quickinfo_provider.dart  ← n8n webhook provider
            ├── admin/
            │   ├── admin_panel.dart      ← 3-tab admin UI
            │   ├── tile_form.dart        ← Create/edit tile form
            │   ├── user_management.dart  ← User CRUD
            │   └── admin_providers.dart
            └── webview/
                └── webview_screen.dart   ← In-app browser for tiles
```

---

## 10. Known Constraints & Notes

| Item | Detail |
|---|---|
| **LAN only** | Backend is accessible on `192.168.1.174` only within the office network. Change `AppConfig.tsgAuthBaseUrl` and rebuild APK for any IP change. |
| **Roster refresh** | Roster data fetches once per app session. Manual refresh via pull-to-refresh on tile screen. |
| **No Play Store** | App is distributed via ADB sideload. Enable "Install from unknown sources" on target devices. |
| **Debug APK** | Current builds are debug-signed. For production, configure `android/key.properties` and `build.gradle` signing config. |
| **Gradle warning** | Build prints `Support for AndX...` deprecation warning — this is a cosmetic Gradle warning, not a compile error. |
| **n8n SET timezone** | MySQL queries in n8n use `SET time_zone = '+05:30'; SELECT ...` — the Code node filters out null-id rows to avoid crashes. |
| **Icon generation** | Requires Python 3 + Pillow. Run `gen_tsg_icon.py` after any icon design change. |
| **Gmail App Password** | `TSG_AUTH_SMTP_PASSWORD` must be a Gmail App Password (not regular password). Google rejects standard passwords via SMTP (535 BadCredentials). |
| **DB migrations** | No Alembic — migrations run as raw `ALTER TABLE IF NOT EXISTS` SQL at backend startup in `main.py`. |
| **APScheduler timezone** | Inactivity sweep job runs at midnight IST (`Asia/Calcutta`). Job is registered in `main.py` startup. |
