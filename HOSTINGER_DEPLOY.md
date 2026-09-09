# Deploy StudyNation on Hostinger

Django is **not supported on Hostinger Web or Cloud (shared) hosting**. Use a **Hostinger VPS** (KVM 1 or larger) with Ubuntu **24.04 or 26.04** and **Python 3.12+** (required by Django 6). A plain Ubuntu VPS uses Path B (Nginx + Gunicorn).

Repo: `https://github.com/studynation04/StudyNation.git`

## Which path to use

| Hostinger setup | Use this |
| --- | --- |
| VPS template **OpenLiteSpeed with Django** | Path A |
| Plain Ubuntu VPS (or you prefer Nginx) | Path B (scripted) |

Path B is the default in `deploy/hostinger/setup.sh`.

## Before you start

1. Buy / open a Hostinger **VPS**.
2. Point DNS A records for `yourdomain.com` and `www.yourdomain.com` to the VPS IP.
3. In hPanel → VPS → **Browser terminal** (already logged in as root), or SSH:

   ```bash
   ssh root@YOUR_VPS_IP
   ```

## Path B — Nginx + Gunicorn (recommended if you do not need OpenLiteSpeed)

On the VPS:

```bash
export DOMAIN=yourdomain.com
export VPS_IP=YOUR_VPS_IP
export REPO_URL=https://github.com/studynation04/StudyNation.git
export BRANCH=main

apt-get update -y && apt-get install -y git
git clone --branch "$BRANCH" "$REPO_URL" /var/www/studynation
bash /var/www/studynation/deploy/hostinger/setup.sh
```

The script will:

- install Python 3, Nginx, MariaDB, LibreOffice (for `.doc` uploads)
- clone/update the repo into `/var/www/studynation`
- create a venv and install `requirements.txt`
- write a production `.env` with a generated `SECRET_KEY` and DB password
- run `migrate` + `collectstatic`
- enable systemd `studynation` (Gunicorn) and Nginx

Create an admin user:

```bash
cd /var/www/studynation
source venv/bin/activate
python manage.py createsuperuser
```

Check: `http://YOUR_VPS_IP/healthz/` then `http://yourdomain.com/`

### HTTPS

After DNS is live:

```bash
apt-get install -y certbot python3-certbot-nginx
certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

Then in `/var/www/studynation/.env` set:

```
SECURE_SSL_REDIRECT=True
```

```bash
systemctl restart studynation
```

## Path A — OpenLiteSpeed Django template

1. hPanel → VPS → **OS & Panel → Operating System → Application → OpenLiteSpeed with Django**.
2. Changing OS **wipes the VPS**. Do this on a new/empty server.
3. Finish the first-login domain / Let's Encrypt prompts.
4. Clone this project (do not use the demo app):

```bash
export DOMAIN=yourdomain.com
export VPS_IP=YOUR_VPS_IP
export SKIP_NGINX=1
git clone https://github.com/studynation04/StudyNation.git /var/www/studynation
bash /var/www/studynation/deploy/hostinger/setup.sh
chown -R nobody:nogroup /var/www/studynation
```

5. Open LiteSpeed WebAdmin: `https://YOUR_VPS_IP:7080`  
   Password: `cat ~/.litespeed_password` (or `/usr/local/lsws/admin/misc/admpass.sh`).
6. Apply the context values in `deploy/hostinger/openlitespeed-context.txt`.
7. Restart Python workers:

```bash
killall lswsgi || true
systemctl restart lsws
```

Python version in `PYTHONPATH` must match the venv (often `python3.12` on Ubuntu 24.04). Check with:

```bash
/var/www/studynation/venv/bin/python -c "import sys; print(sys.version)"
```

## Environment variables (server `.env`)

Never commit `.env`. On the VPS it lives at `/var/www/studynation/.env`.

| Key | Production value |
| --- | --- |
| `DEBUG` | `False` |
| `SECRET_KEY` | long random string |
| `SITE_DOMAIN` | `yourdomain.com` |
| `VPS_IP` | VPS public IP |
| `ALLOWED_HOSTS` | `yourdomain.com,www.yourdomain.com,VPS_IP` |
| `CSRF_TRUSTED_ORIGINS` | `https://yourdomain.com,https://www.yourdomain.com` |
| `SECURE_SSL_REDIRECT` | `False` until SSL works, then `True` |
| `DATABASE_URL` | `mysql://user:pass@127.0.0.1:3306/studynation` or Postgres URL |
| `CORS_ALLOW_ALL_ORIGINS` | `False` |

SQLite is only for local development. Use MariaDB/MySQL or PostgreSQL on Hostinger.

## Update the live site after a git push

```bash
cd /var/www/studynation
git pull origin main
source venv/bin/activate
pip install -r requirements.txt
python manage.py migrate --noinput
python manage.py collectstatic --noinput
```

Nginx path:

```bash
systemctl restart studynation
```

OpenLiteSpeed path:

```bash
killall lswsgi || true
systemctl restart lsws
```

## App URLs

- Site: `/`
- Admin panel: `/admin-panel/`
- Django admin: `/admin/`
- API: `/api/`
- Health: `/healthz/`

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `DisallowedHost` | Set `SITE_DOMAIN` and `VPS_IP` (or `ALLOWED_HOSTS`) in `.env`, restart |
| CSRF failed | Set `CSRF_TRUSTED_ORIGINS` to `https://yourdomain.com,https://www.yourdomain.com` |
| 502 Bad Gateway | `systemctl status studynation` and `journalctl -u studynation -n 80` |
| Static/CSS missing | `python manage.py collectstatic --noinput`; confirm Nginx `/static/` alias |
| Media uploads 404 | `chown -R www-data:www-data /var/www/studynation/media` (Nginx) or `nobody:nogroup` (OLS) |
| SSL redirect loop | Keep `SECURE_SSL_REDIRECT=False` until certbot succeeds |
| `.doc` upload fails | LibreOffice is installed by `setup.sh`; otherwise upload `.docx` |
| Shared hosting error | Move the site to a **VPS** — Python/Django cannot run on Hostinger Web/Cloud |

## Production notes

- Uploaded files live on the VPS disk under `media/` (persistent, unlike Render).
- WhiteNoise still serves `/static/` if Nginx/OLS static aliases are missing.
- Gunicorn timeout is 120s so Word question imports can finish.
- After SSL is confirmed, keep `DEBUG=False` and `SECURE_SSL_REDIRECT=True`.
