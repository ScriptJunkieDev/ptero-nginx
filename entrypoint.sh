#!/bin/sh
set -eu

TEMPLATE_START="/usr/local/share/ptero/start.sh"
TEMPLATE_NGINX_DIR="/usr/local/share/ptero/templates/nginx"
TEMPLATE_PHPFPM_DIR="/usr/local/share/ptero/templates/php-fpm"

# Default if Pterodactyl doesn't provide one
TARGET_START="${STARTUP_CMD:-/home/container/start.sh}"

echo "[ptero] Boot seed starting..."
echo "[ptero] TARGET_START=${TARGET_START}"

# --- Always reseed start.sh (overwrite every boot) ---
mkdir -p "$(dirname "${TARGET_START}")"
cp -f "${TEMPLATE_START}" "${TARGET_START}"
chmod +x "${TARGET_START}"

# --- Seed nginx/php-fpm only if missing ---
if [ -d /home/container/nginx ] && [ "$(ls -A /home/container/nginx 2>/dev/null || true)" ]; then
  echo "[ptero] nginx/ exists; skipping seed"
else
  echo "[ptero] nginx/ missing/empty; seeding from image"
  mkdir -p /home/container/nginx
  cp -a "${TEMPLATE_NGINX_DIR}/." /home/container/nginx/
fi

if [ -d /home/container/php-fpm ] && [ "$(ls -A /home/container/php-fpm 2>/dev/null || true)" ]; then
  echo "[ptero] php-fpm/ exists; skipping seed"
else
  echo "[ptero] php-fpm/ missing/empty; seeding from image"
  mkdir -p /home/container/php-fpm
  cp -a "${TEMPLATE_PHPFPM_DIR}/." /home/container/php-fpm/
fi

# Ownership (ignore if not running as root)
chown -R container:container /home/container 2>/dev/null || true

echo "[ptero] Boot seed complete. Launching startup..."
exec /bin/sh "${TARGET_START}"
