#!/bin/sh
set -eu

TEMPLATE_START="/usr/local/share/ptero/start.sh"
TEMPLATE_NGINX_DIR="/usr/local/share/ptero/templates/nginx"
TEMPLATE_PHPFPM_DIR="/usr/local/share/ptero/templates/php-fpm"

# Default if Pterodactyl doesn't provide one
TARGET_START="${STARTUP_CMD:-/home/container/start.sh}"

seed_missing_files() {
  src_dir="$1"
  dest_dir="$2"
  label="$3"

  [ -d "${src_dir}" ] || return 0
  mkdir -p "${dest_dir}"

  find "${src_dir}" -type f | while IFS= read -r src; do
    rel="${src#${src_dir}/}"
    dest="${dest_dir}/${rel}"
    if [ ! -f "${dest}" ]; then
      mkdir -p "$(dirname "${dest}")"
      cp -f "${src}" "${dest}"
      echo "[ptero] ${label}: added ${rel}"
    fi
  done
}

echo "[ptero] Boot seed starting..."
echo "[ptero] TARGET_START=${TARGET_START}"

# --- Always reseed start.sh from image (overwrite every boot) ---
# Update start.sh in this repo and rebuild/publish the image for changes to apply.
mkdir -p "$(dirname "${TARGET_START}")"
cp -f "${TEMPLATE_START}" "${TARGET_START}"
chmod +x "${TARGET_START}"

# --- Seed nginx/php-fpm: fill in any files missing from image templates ---
seed_missing_files "${TEMPLATE_NGINX_DIR}" /home/container/nginx "nginx"
seed_missing_files "${TEMPLATE_PHPFPM_DIR}" /home/container/php-fpm "php-fpm"

# Ownership (ignore if not running as root)
chown -R container:container /home/container 2>/dev/null || true

echo "[ptero] Boot seed complete. Launching startup..."
exec /bin/sh "${TARGET_START}"
