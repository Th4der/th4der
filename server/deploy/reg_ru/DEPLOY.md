# REG.RU VPS Deploy (Ubuntu)

This guide is for `server/app.py` from this repository.

## 1. Server requirements

- Ubuntu `22.04 LTS` (or `26.04 LTS`)
- `2 vCPU / 2 GB RAM / 20 GB SSD`
- Public IP attached in REG.RU panel

## 2. Base packages

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip nginx postgresql postgresql-contrib certbot python3-certbot-nginx
```

## 3. App user and directories

```bash
sudo useradd --system --create-home --shell /bin/bash th4der || true
sudo mkdir -p /opt/th4der
sudo chown -R th4der:www-data /opt/th4der
```

Upload project to `/opt/th4der` (git clone or rsync), then:

```bash
cd /opt/th4der/server
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements-prod.txt
```

## 4. PostgreSQL setup

```bash
sudo -u postgres psql
```

Inside psql:

```sql
CREATE USER th4der WITH PASSWORD 'CHANGE_ME_STRONG_PASSWORD';
CREATE DATABASE th4der OWNER th4der;
\q
```

## 5. Environment file

```bash
cd /opt/th4der/server
cp .env.example .env
nano .env
```

Set at least:

```env
TH4DER_DEBUG=0
TH4DER_HOST=127.0.0.1
TH4DER_PORT=8000
TH4DER_JWT_SECRET=YOUR_LONG_RANDOM_SECRET
TH4DER_DATABASE_URL=postgresql+psycopg://th4der:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/th4der
```

## 6. Systemd service

```bash
sudo cp /opt/th4der/server/deploy/reg_ru/systemd/th4der.service.example /etc/systemd/system/th4der.service
sudo systemctl daemon-reload
sudo systemctl enable th4der
sudo systemctl restart th4der
sudo systemctl status th4der --no-pager
```

Logs:

```bash
journalctl -u th4der -f
```

## 7. Nginx reverse proxy

```bash
sudo cp /opt/th4der/server/deploy/reg_ru/nginx/th4der.conf.example /etc/nginx/sites-available/th4der
sudo nano /etc/nginx/sites-available/th4der
```

Replace `your-domain.example` with your real domain, then:

```bash
sudo ln -s /etc/nginx/sites-available/th4der /etc/nginx/sites-enabled/th4der
sudo nginx -t
sudo systemctl reload nginx
```

## 8. SSL certificate

```bash
sudo certbot --nginx -d your-domain.example -d www.your-domain.example
```

## 9. Firewall (if ufw enabled)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw enable
sudo ufw status
```

## 10. Health check

```bash
curl http://127.0.0.1:8000/health
curl https://your-domain.example/health
```

## 11. SQLite -> PostgreSQL migration (recommended)

If you already have data in `server/th4der.db`, migrate it once with `pgloader`.

On your server:

```bash
sudo apt install -y pgloader
```

Put `th4der.db` in `/opt/th4der/server/th4der.db`, then:

```bash
pgloader /opt/th4der/server/th4der.db postgresql://th4der:CHANGE_ME_STRONG_PASSWORD@127.0.0.1:5432/th4der
```

After migration:

1. Keep `TH4DER_DATABASE_URL` pointed to PostgreSQL.
2. Restart app: `sudo systemctl restart th4der`.
3. Verify chats/users in app.

## 12. Client config

Use the same backend URL in Flutter:

```bash
--dart-define=API_BASE_URL=https://your-domain.example/
--dart-define=WEBRTC_USE_AIORTC=false
--dart-define=WEBRTC_STUN_URLS=stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302
```

