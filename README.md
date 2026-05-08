# Th4der

Th4der is a messenger client built with Flutter and backed by a Python server.

## Stack

- Flutter (client)
- Python + Flask + SQLite + JWT (server API + database + auth)

## Run server

```bash
cd server
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

Server starts on `http://0.0.0.0:8000`.
SQLite database is created automatically at `server/th4der.db`.

## Run Flutter client

Install dependencies:

```bash
flutter pub get
```

Android emulator:

```bash
flutter run --dart-define API_BASE_URL=http://10.0.2.2:8000
```

Physical Android phone (same Wi-Fi network as PC):

```bash
flutter run --dart-define API_BASE_URL=http://<YOUR_PC_IP>:8000
```

## Auth

- Register and login are available in UI.
- Seed users are disabled.
- Create accounts via registration in the app UI.

Run a second client as another user (second device/emulator):

```bash
flutter run --dart-define API_BASE_URL=http://<YOUR_PC_IP>:8000
```

## Calls (WebRTC)

- Open any direct chat and tap the phone icon in the chat header.
- Incoming call appears as a dialog on the other device.
- Audio/video stream is inside the app via WebRTC signaling through the Python API.
- Default ICE config uses public STUN/TURN (`stun.l.google.com` + `openrelay.metered.ca`).
- For stable production calls, pass your own TURN credentials:

```bash
flutter run ^
  --dart-define API_BASE_URL=http://<YOUR_PC_IP>:8000 ^
  --dart-define WEBRTC_TURN_URL=turn:your-turn-host:3478?transport=udp ^
  --dart-define WEBRTC_TURN_USERNAME=<TURN_USER> ^
  --dart-define WEBRTC_TURN_CREDENTIAL=<TURN_PASSWORD> ^
  --dart-define WEBRTC_FORCE_RELAY=true
```
