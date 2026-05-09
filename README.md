# TSG Launcher

An internal Android mobile application for telecom support teams. TSG Launcher aggregates internal web tools, dashboards, and NOC apps into a secure, role-aware tile-based home screen — with live data panels for real-time operational information such as the daily engineer roster.

> **Distribution:** Sideloaded via ADB. Not on Play Store.

---

## Features

- **Secure login** with JWT authentication (access + refresh tokens)
- **Biometric lock** — fingerprint/face re-auth when app resumes from background
- **Forced password change** on first login and after 90-day expiry
- **Self-service password reset** via email (Gmail SMTP)
- **Inactivity auto-disable** — accounts inactive for 30+ days are disabled nightly
- **Tile grid home screen** — role-filtered, masonry layout, pull-to-refresh
- **Quick panels** — live Roster, Clock, and Date widgets embedded in tiles
- **In-app WebView** — internal tools open in an embedded browser (SSO-aware)
- **Admin panel** — full CRUD for tiles, groups, and users (role-gated)

---

## Architecture

```
Flutter App (Android)
    │
    │  HTTP (LAN — 192.168.1.174)
    ▼
┌──────────────┐   ┌──────────────┐   ┌───────────────┐
│  tsg_auth    │   │     n8n      │   │  n8n_mysql    │
│  FastAPI     │   │  Workflow    │   │  MySQL 8.0    │
│  :8000       │   │  Engine      │   │  :3306        │
└──────┬───────┘   │  :5555       │   └───────────────┘
       │           └──────────────┘
┌──────▼───────┐   ┌──────────────┐   ┌───────────────┐
│  postgres_   │   │  postgres_   │   │  redis_cache  │
│  tsg_auth    │   │  n8n         │   │  :6379        │
│  :5435       │   │  :5433       │   └───────────────┘
└──────────────┘   └──────────────┘
```

All services run via Docker Compose on a single on-premises host.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile | Flutter (Dart SDK ^3.8.1), Riverpod 2.6.1, GoRouter 14.8.1 |
| HTTP | Dio 5.8.0 |
| WebView | flutter_inappwebview 6.1.5 |
| Storage | flutter_secure_storage 9.2.4 |
| Biometrics | local_auth 2.3.0 |
| Backend | FastAPI 0.115.6, Python 3.12 |
| Database | PostgreSQL 16 (auth), MySQL 8.0 (roster) |
| Auth | JWT HS256 (python-jose), bcrypt |
| Scheduler | APScheduler 3.10.4 |
| Workflow | n8n (self-hosted) |
| Cache | Redis 7 |

---

## Project Structure

```
TSG_Application/
├── docker-compose.yml       ← All backend services
├── .env                     ← Secrets (NOT committed — see .env.example)
├── tsg_auth/                ← FastAPI backend
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app/
│       ├── main.py          ← App entry, DB migrations, APScheduler
│       ├── models.py        ← SQLAlchemy ORM
│       ├── schemas.py       ← Pydantic schemas
│       ├── security.py      ← JWT, bcrypt, email
│       ├── config.py        ← Settings from env vars
│       ├── database.py      ← DB session factory
│       ├── deps.py          ← Auth dependencies + RBAC guards
│       └── routers/
│           ├── auth.py      ← /auth/* endpoints
│           ├── me.py        ← /me/* endpoints
│           └── admin.py     ← /admin/* endpoints
├── tsg_launcher/            ← Flutter Android app
│   ├── pubspec.yaml
│   └── lib/
│       ├── main.dart
│       ├── app.dart
│       ├── core/
│       │   ├── auth/        ← Auth state (Riverpod), biometrics
│       │   ├── models/      ← Tile, User, Role models
│       │   ├── routing/     ← GoRouter + auth guards
│       │   └── tsg_auth/    ← API client (all HTTP calls)
│       └── features/
│           ├── auth/        ← Login, ForgotPassword, ChangePassword, Biometric screens
│           ├── tiles/       ← Tile grid, quick panels
│           ├── admin/       ← Admin panel (users/groups/tiles)
│           ├── roster_upload/ ← Photo-based roster OCR upload
│           └── webview/     ← In-app browser
└── Backup_n8n/              ← n8n workflow JSON exports
```

---

## Getting Started

### Prerequisites

- Docker Desktop
- Flutter SDK (3.x)
- ADB (for device install)

### 1. Configure Environment

Copy `.env.example` to `.env` and fill in secrets:

```bash
cp .env.example .env
```

Key values to set:
- `TSG_AUTH_PG_PASSWORD` — PostgreSQL password for tsg_auth
- `TSG_AUTH_JWT_SECRET` — random secret string for JWT signing
- `TSG_AUTH_INIT_SUPERADMIN_PASSWORD` — initial superadmin password
- `TSG_AUTH_SMTP_PASSWORD` — Gmail **App Password** (from https://myaccount.google.com/apppasswords)

> **Important:** `TSG_AUTH_SMTP_PASSWORD` must be a Gmail App Password, not your regular Gmail password. Enable 2-Step Verification first, then generate an App Password.

### 2. Start Backend Services

```powershell
cd D:\Neel\ElectronProject\TSG_Application
docker compose up -d
docker compose ps        # verify all services are healthy
docker compose logs -f tsg_auth  # watch auth service logs
```

### 3. Configure Flutter App

Edit `tsg_launcher/lib/core/auth/auth_service.dart`:
```dart
static const String tsgAuthBaseUrl = 'http://192.168.1.174:8000';
```
Replace with your server's IP address.

### 4. Run / Build Flutter App

```powershell
cd tsg_launcher
flutter pub get

# Run on emulator
flutter run -d emulator-5554

# Build debug APK for sideloading
flutter build apk --debug
# Output: build\app\outputs\flutter-apk\app-debug.apk
```

### 5. Sideload APK to Device

```powershell
adb install -r build\app\outputs\flutter-apk\app-debug.apk
```

---

## API Overview

Base URL: `http://<host>:8000`

| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/auth/login` | — | Login → JWT tokens |
| POST | `/auth/refresh` | — | Refresh access token |
| POST | `/auth/logout` | — | Revoke refresh token |
| POST | `/auth/forgot-password` | — | Email temp password |
| POST | `/auth/change-password` | Bearer | Change password |
| GET | `/me/tiles` | Bearer | Tiles for current user |
| GET | `/admin/users` | Bearer (head+) | List users |
| POST | `/admin/users/{pk}/reset-password` | Bearer (head+) | Admin reset password |
| GET | `/admin/tiles` | Bearer (head+) | List all tiles |
| GET | `/admin/groups` | Bearer (head+) | List all groups |

Full API reference: see [PRD.md](PRD.md#6-api-reference)

---

## Security Notes

- Secrets are stored in `.env` (never committed)
- Passwords hashed with bcrypt
- JWT tokens expire: access = 60 min, refresh = 30 days
- Refresh tokens are revoked server-side on logout
- Accounts inactive for 30+ days are auto-disabled nightly
- Passwords expire after 90 days

---

## Role Hierarchy

| Role | Level | Access |
|---|---|---|
| `superadmin` | 7 | Full access |
| `admin` | 6 | Admin panel, cannot modify superadmin |
| `head` | 5 | Manage tiles, groups, users |
| `supervisor` | 4 | Manage engineers/trainees |
| `sme` | 3 | Manage engineers/trainees |
| `engineer` | 2 | Tile access only |
| `trainee` | 1 | Tile access only |

---

## License

Internal use only. Not for public distribution.
