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

## Flutter connection

For Android emulator:

```bash
flutter run --dart-define API_BASE_URL=http://10.0.2.2:8000
```

For a physical Android phone use your PC LAN IP:

```bash
flutter run --dart-define API_BASE_URL=http://<YOUR_PC_IP>:8000
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
