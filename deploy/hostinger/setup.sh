#!/usr/bin/env bash
# Hostinger VPS bootstrap for StudyNation (Ubuntu 24.04/26.04, Python 3.12+).
#
# Run as root on the VPS:
#   export DOMAIN=yourdomain.com
#   export VPS_IP=x.x.x.x
#   export REPO_URL=https://github.com/studynation04/StudyNation.git
#   bash deploy/hostinger/setup.sh
#
# Optional:
#   export APP_DIR=/var/www/studynation
#   export DB_ENGINE=mysql    # mysql (default) or postgres
#   export SKIP_NGINX=1       # if using OpenLiteSpeed instead of Nginx
set -euo pipefail

DOMAIN="${DOMAIN:-}"
VPS_IP="${VPS_IP:-}"
REPO_URL="${REPO_URL:-https://github.com/studynation04/StudyNation.git}"
APP_DIR="${APP_DIR:-/var/www/studynation}"
DB_ENGINE="${DB_ENGINE:-mysql}"
SKIP_NGINX="${SKIP_NGINX:-0}"
BRANCH="${BRANCH:-main}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root (Hostinger Browser terminal is already root)."
  exit 1
fi

if [ -z "$DOMAIN" ]; then
  echo "Set DOMAIN first, e.g. export DOMAIN=studynation.com"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends \
  python3 python3-venv python3-pip python3-dev \
  build-essential pkg-config \
  git nginx curl ca-certificates \
  libxml2-dev libxslt1-dev \
  libjpeg-dev zlib1g-dev libpng-dev libpq-dev \
  libreoffice-writer-nogui fonts-dejavu-core fonts-liberation

if [ "$DB_ENGINE" = "postgres" ]; then
  apt-get install -y --no-install-recommends postgresql postgresql-contrib
else
  apt-get install -y --no-install-recommends mariadb-server libmariadb-dev
fi

mkdir -p "$APP_DIR"
git config --global --add safe.directory "$APP_DIR" 2>/dev/null || true
if [ ! -d "$APP_DIR/.git" ]; then
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
else
  git -C "$APP_DIR" fetch origin
  git -C "$APP_DIR" checkout "$BRANCH"
  git -C "$APP_DIR" pull --ff-only origin "$BRANCH"
fi

cd "$APP_DIR"

if [ ! -d venv ]; then
  python3 -m venv venv
fi
# shellcheck disable=SC1091
source venv/bin/activate
if pkg-config --exists mariadb; then
  export MYSQLCLIENT_CFLAGS
  MYSQLCLIENT_CFLAGS="$(pkg-config --cflags mariadb)"
  export MYSQLCLIENT_LDFLAGS
  MYSQLCLIENT_LDFLAGS="$(pkg-config --libs mariadb)"
elif pkg-config --exists mysqlclient; then
  export MYSQLCLIENT_CFLAGS
  MYSQLCLIENT_CFLAGS="$(pkg-config --cflags mysqlclient)"
  export MYSQLCLIENT_LDFLAGS
  MYSQLCLIENT_LDFLAGS="$(pkg-config --libs mysqlclient)"
fi
pip install --upgrade pip
pip install -r requirements.txt

SECRET_VALUE="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(50))
PY
)"

DB_NAME="${DB_NAME:-studynation}"
DB_USER="${DB_USER:-studynation}"
DB_PASSWORD="${DB_PASSWORD:-$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(18))
PY
)}"

if [ ! -f .env ]; then
  if [ "$DB_ENGINE" = "postgres" ]; then
    sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
SQL
    DB_URL="postgres://${DB_USER}:${DB_PASSWORD}@127.0.0.1:5432/${DB_NAME}"
    DB_ENGINE_LINE="django.db.backends.postgresql"
    DB_PORT=5432
  else
    mysql -u root <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
    DB_URL="mysql://${DB_USER}:${DB_PASSWORD}@127.0.0.1:3306/${DB_NAME}"
    DB_ENGINE_LINE="django.db.backends.mysql"
    DB_PORT=3306
  fi

  cat > .env <<EOF
DEBUG=False
SECRET_KEY=${SECRET_VALUE}
SITE_DOMAIN=${DOMAIN}
VPS_IP=${VPS_IP}
ALLOWED_HOSTS=${DOMAIN},www.${DOMAIN}${VPS_IP:+,${VPS_IP}},127.0.0.1
CSRF_TRUSTED_ORIGINS=https://${DOMAIN},https://www.${DOMAIN}
SECURE_SSL_REDIRECT=False
CORS_ALLOW_ALL_ORIGINS=False
DATABASE_URL=${DB_URL}
DATABASE_ENGINE=${DB_ENGINE_LINE}
DATABASE_NAME=${DB_NAME}
DATABASE_USER=${DB_USER}
DATABASE_PASSWORD=${DB_PASSWORD}
DATABASE_HOST=127.0.0.1
DATABASE_PORT=${DB_PORT}
LOG_LEVEL=INFO
EOF
  chmod 600 .env
  echo "Wrote ${APP_DIR}/.env (keep this file private)."
  echo "Database password stored only in .env"
fi

python manage.py migrate --noinput
python manage.py collectstatic --noinput
python manage.py ensure_schema || true

chown -R www-data:www-data "$APP_DIR"
chmod -R u+rwX,g+rX "$APP_DIR"
chmod 600 "$APP_DIR/.env"

if [ "$SKIP_NGINX" != "1" ]; then
  SERVICE_SRC="$APP_DIR/deploy/hostinger/gunicorn.service"
  NGINX_SRC="$APP_DIR/deploy/hostinger/nginx.conf"
  sed "s|/var/www/studynation|${APP_DIR}|g" "$SERVICE_SRC" > /etc/systemd/system/studynation.service
  sed -e "s|SITE_DOMAIN|${DOMAIN}|g" \
      -e "s|VPS_IP|${VPS_IP}|g" \
      -e "s|/var/www/studynation|${APP_DIR}|g" \
      "$NGINX_SRC" > /etc/nginx/sites-available/studynation
  ln -sfn /etc/nginx/sites-available/studynation /etc/nginx/sites-enabled/studynation
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl daemon-reload
  systemctl enable --now studynation
  systemctl reload nginx
  echo "Gunicorn + Nginx are running."
  echo "After DNS points to this VPS, issue SSL with:"
  echo "  apt-get install -y certbot python3-certbot-nginx"
  echo "  certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
  echo "Then set SECURE_SSL_REDIRECT=True in ${APP_DIR}/.env and:"
  echo "  systemctl restart studynation"
else
  chown -R nobody:nogroup "$APP_DIR"
  chmod 600 "$APP_DIR/.env"
  echo "Skipped Nginx/Gunicorn. Configure OpenLiteSpeed using:"
  echo "  ${APP_DIR}/deploy/hostinger/openlitespeed-context.txt"
  echo "  killall lswsgi || true"
  echo "  systemctl restart lsws"
fi

echo
echo "Create an admin user:"
echo "  cd ${APP_DIR} && source venv/bin/activate && python manage.py createsuperuser"
echo "Health check: http://${DOMAIN}/healthz/  or  http://${VPS_IP}/healthz/"
