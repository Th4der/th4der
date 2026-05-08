# Th4der Python API

## Run locally

```bash
cd server
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

The API listens on `http://0.0.0.0:8000`.
The SQLite database is stored at `server/th4der.db`.

## Production-ready server run

`app.py` now supports env-based DB/port config:

- `TH4DER_DATABASE_URL` (or `DATABASE_URL`)
- `PORT` / `TH4DER_PORT`

If no DB env is set, server falls back to SQLite (`server/th4der.db`).

Gunicorn command (from `server/`):

```bash
gunicorn -c gunicorn.conf.py wsgi:app
```

## Deploy to REG.RU VPS

Ready deployment files are in:

- `server/deploy/reg_ru/DEPLOY.md`
- `server/deploy/reg_ru/systemd/th4der.service.example`
- `server/deploy/reg_ru/nginx/th4der.conf.example`
- `server/.env.example`
- `server/requirements-prod.txt`

## Flutter connection

For Android emulator:

```bash
flutter run --dart-define API_BASE_URL=http://10.0.2.2:8000 --dart-define WEBRTC_USE_AIORTC=true
```

For a physical Android phone use your PC LAN IP:

```bash
flutter run --dart-define API_BASE_URL=http://<YOUR_PC_IP>:8000 --dart-define WEBRTC_USE_AIORTC=true
```

For tunnel/Internet testing:

```bash
flutter run --dart-define API_BASE_URL=https://<YOUR_TUNNEL_HOST> --dart-define WEBRTC_USE_AIORTC=true
```

Custom STUN list:

```bash
flutter run --dart-define API_BASE_URL=https://q5kxq8pd-8000.euw.devtunnels.ms/ --dart-define WEBRTC_USE_AIORTC=false --dart-define WEBRTC_STUN_URLS=stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302
```

Optional TURN (for direct P2P mode):

```bash
flutter run --dart-define API_BASE_URL=https://q5kxq8pd-8000.euw.devtunnels.ms/ --dart-define WEBRTC_USE_AIORTC=false --dart-define WEBRTC_TURN_URL=turn:host:3478 --dart-define WEBRTC_TURN_USERNAME=<USER> --dart-define WEBRTC_TURN_CREDENTIAL=<PASS> --dart-define WEBRTC_FORCE_RELAY=true
```

## Auth endpoints

- `POST /api/auth/register`
- `POST /api/auth/login`
- `GET /api/auth/me`

Seed users are disabled.
Register users via `POST /api/auth/register` or from the Flutter UI.

Create direct chat:

```bash
POST /api/conversations/direct
{
  "partner_user_id": 2
}
```

## Call signaling endpoints

- `POST /api/calls/start`
- `GET /api/calls/incoming`
- `POST /api/calls/<call_id>/accept`
- `POST /api/calls/<call_id>/reject`
- `POST /api/calls/<call_id>/end`
- `POST /api/calls/<call_id>/signal` (`offer`, `answer`, `ice`)
- `GET /api/calls/<call_id>/signals?since_id=0`
