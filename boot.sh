#!/bin/sh
# Railway boot for wallabag.
#
# Refuses to start without strong secrets, maps Railway's variables onto upstream's entrypoint (PostgreSQL driver, public
# address, listen port), puts the data directory on the volume, and holds nginx back until the bootstrap has replaced the default
# wallabag/wallabag login and created the API client, so no request is ever served while the default login works.
set -u
fail() { echo "[railway] $1" >&2; exit 1; }
need() { eval "val=\${$1:-}"; [ -n "$val" ] || fail "$1 is not set"; }

need ADMIN_PASSWORD
[ "${#ADMIN_PASSWORD}" -ge 12 ] || fail "ADMIN_PASSWORD must be at least 12 characters"
APP_SECRET="${APP_SECRET:-}"
[ "${#APP_SECRET}" -ge 32 ] || fail "APP_SECRET must be set and at least 32 characters"
API_CLIENT_ID="${API_CLIENT_ID:-}"; API_CLIENT_SECRET="${API_CLIENT_SECRET:-}"
[ "${#API_CLIENT_ID}" -ge 24 ] || fail "API_CLIENT_ID must be set and at least 24 characters"
[ "${#API_CLIENT_SECRET}" -ge 32 ] || fail "API_CLIENT_SECRET must be set and at least 32 characters"
for v in POSTGRES_HOST POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB WALLABAG_DB_PASSWORD; do need "$v"; done
case "${PORT:=8080}" in ''|*[!0-9]*) fail "PORT must be a number, got '$PORT'";; esac
if [ -z "${APP_URL:-}" ]; then
  [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ] || fail "neither APP_URL nor RAILWAY_PUBLIC_DOMAIN is set"
  APP_URL="https://$RAILWAY_PUBLIC_DOMAIN"
fi

# upstream's entrypoint reads these; POSTGRES_USER/POSTGRES_PASSWORD (the superuser) create the wallabag role and database once
# upstream connects as the superuser with no database name, which psql takes from the user name; point it at the maintenance database
export PGDATABASE="$POSTGRES_DB"
export SYMFONY__ENV__DATABASE_DRIVER=pdo_pgsql
export SYMFONY__ENV__DATABASE_HOST="$POSTGRES_HOST"
export SYMFONY__ENV__DATABASE_PORT=5432
export SYMFONY__ENV__DATABASE_NAME=wallabag
export SYMFONY__ENV__DATABASE_USER=wallabag
export SYMFONY__ENV__DATABASE_PASSWORD="$WALLABAG_DB_PASSWORD"
export SYMFONY__ENV__DOMAIN_NAME="$APP_URL"
export SYMFONY__ENV__SECRET="$APP_SECRET"
export SYMFONY__ENV__FOSUSER_REGISTRATION=false
export SYMFONY__ENV__SERVER_NAME="${SYMFONY__ENV__SERVER_NAME:-Wallabag}"

# nginx listens on 80 in upstream's config; Railway's healthcheck dials the injected PORT, so follow it
sed -i "s/listen \[::\]:80 ipv6only=off;/listen [::]:$PORT ipv6only=off;/" /etc/nginx/nginx.conf
grep -q "listen \[::\]:$PORT ipv6only=off;" /etc/nginx/nginx.conf || fail "nginx listen line not rewritten to port $PORT"

# nginx starts only after the bootstrap wrote this marker
MARK=/run/railway-ready
rm -f "$MARK"
cat > /etc/s6/nginx/run <<'RUN'
#!/bin/sh
until [ -f /run/railway-ready ]; do sleep 1; done
exec nginx -c /etc/nginx/nginx.conf
RUN
chmod 0755 /etc/s6/nginx/run

# Railway mounts the volume owned by root: create the layout wallabag expects and hand it to upstream's user
D=/var/www/wallabag/data
echo "[railway] wallabag on :$PORT as $APP_URL, postgres $POSTGRES_HOST, data owner before=$(stat -c %u:%g $D)"
mkdir -p "$D/db" "$D/assets" "$D/images"
if [ ! -L /var/www/wallabag/web/assets/images ]; then
  rm -rf /var/www/wallabag/web/assets/images
  ln -s ../../data/images /var/www/wallabag/web/assets/images
fi
chown -R nobody:nobody "$D"
echo "[railway] data owner after=$(stat -c %u:%g $D)"

run_app() { su -s /bin/sh nobody -c "cd /var/www/wallabag && $1"; }

(
  export API_CLIENT_ID API_CLIENT_SECRET
  # wait until upstream's entrypoint has installed the schema and handed over to s6
  n=0
  until pgrep s6-svscan >/dev/null 2>&1 && PGPASSWORD="$WALLABAG_DB_PASSWORD" psql -qAt -h "$POSTGRES_HOST" -U wallabag -d wallabag \
      -c "SELECT 1 FROM wallabag_user WHERE username='wallabag'" 2>/dev/null | grep -q 1; do
    n=$((n + 1)); [ "$n" -le 240 ] || { echo "[railway] schema never became ready, bootstrap aborted" >&2; exit 1; }
    sleep 2
  done
  if [ ! -f "$D/.railway-bootstrapped" ]; then
    run_app "php bin/console fos:user:change-password wallabag \"\$ADMIN_PASSWORD\" --env=prod" >/dev/null 2>&1 \
      || { echo "[railway] could not replace the default login, nginx stays down" >&2; exit 1; }
    echo "[railway] default login replaced"
  fi
  run_app "php bin/console doctrine:migrations:migrate --env=prod --no-interaction" >/dev/null 2>&1 || echo "[railway] migrations step failed" >&2
  if run_app "php /railway-api-client.php" >/dev/null 2>&1; then echo "[railway] API client ready"; else echo "[railway] API client not created" >&2; exit 1; fi
  touch "$D/.railway-bootstrapped"; chown nobody:nobody "$D/.railway-bootstrapped"
  touch "$MARK"
  echo "[railway] bootstrap done, serving"
) &

exec /entrypoint.sh "$@"
