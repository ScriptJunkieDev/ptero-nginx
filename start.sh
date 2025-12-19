#!/bin/ash

# Colors for output
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

log_success() { echo -e "${GREEN}[SUCCESS] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARNING] $1${RESET}"; }
log_error()   { echo -e "${RED}[ERROR] $1${RESET}"; }
log_info()    { echo -e "[INFO] $1"; }

# Clean up temp directory
log_info "Cleaning up temporary files..."
rm -rf /home/container/tmp/* || { log_error "Failed to remove temporary files."; exit 1; }
log_success "Temporary files removed successfully."

# ----------------------------
# Composer install (Laravel deps)
# ----------------------------
cd /home/container/webroot || { log_error "webroot not found"; exit 1; }

# ----------------------------
# Auto-update from Git on startup (optional)
# ----------------------------
if [ "${AUTO_UPDATE:-0}" = "1" ] || [ "${AUTO_UPDATE:-false}" = "true" ]; then
  if [ -n "${GIT_ADDRESS}" ]; then
    log_info "AUTO_UPDATE enabled. Syncing from git..."

    # Normalize URL (optional)
    case "${GIT_ADDRESS}" in
      git@*) REPO_URL="${GIT_ADDRESS}" ;;                  # ssh form
      http://*|https://*) REPO_URL="${GIT_ADDRESS}" ;;
      *) REPO_URL="https://${GIT_ADDRESS}" ;;
    esac

    # Add .git if missing (optional)
    [ "${REPO_URL##*.}" != "git" ] && REPO_URL="${REPO_URL}.git"

    # If using https + token auth, inject creds
    if [ -n "${USERNAME}" ] && [ -n "${ACCESS_TOKEN}" ]; then
      REPO_URL="https://${USERNAME}:${ACCESS_TOKEN}@${REPO_URL#https://}"
    fi

    if [ -d .git ]; then
      # Ensure origin matches and pull
      git remote set-url origin "${REPO_URL}" 2>/dev/null || true
      git fetch --all --prune || log_warning "git fetch failed"

      if [ -n "${BRANCH}" ]; then
        git checkout "${BRANCH}" 2>/dev/null || true
        git pull --ff-only origin "${BRANCH}" || log_warning "git pull failed"
      else
        git pull --ff-only || log_warning "git pull failed"
      fi
    else
      # If empty, clone; if not empty, don't stomp user files
      if [ -z "$(ls -A . 2>/dev/null)" ]; then
        log_info "webroot empty; cloning repo..."
        if [ -n "${BRANCH}" ]; then
          git clone --single-branch --branch "${BRANCH}" "${REPO_URL}" . || log_warning "git clone failed"
        else
          git clone "${REPO_URL}" . || log_warning "git clone failed"
        fi
      else
        log_warning "AUTO_UPDATE is on but webroot is not a git repo; skipping pull."
      fi
    fi
  else
    log_warning "AUTO_UPDATE enabled but GIT_ADDRESS is empty; skipping."
  fi
fi

if [ "${RUN_COMPOSER_INSTALL:-true}" = "true" ] || [ "${RUN_COMPOSER_INSTALL:-1}" = "1" ]; then
  if [ -f composer.json ]; then
    if [ ! -f vendor/autoload.php ]; then
      log_info "Running composer install..."
      composer install --no-interaction --prefer-dist ${COMPOSER_FLAGS:---no-dev --optimize-autoloader} \
        || { log_error "composer install failed"; exit 1; }
      log_success "Composer install completed."
    else
      log_success "vendor/autoload.php exists; skipping composer install."
    fi
  else
    log_warning "composer.json not found in /home/container/webroot; skipping composer."
  fi
else
  log_warning "RUN_COMPOSER_INSTALL disabled; skipping composer."
fi

# Ensure .env exists
if [ ! -f .env ] && [ -f .env.example ]; then
cp .env.example .env
fi

# Generate APP_KEY if missing
if [ -f artisan ] && [ -f .env ] && ! grep -q '^APP_KEY=base64:' .env; then
  php artisan key:generate --force || true
fi

if [ "${RUN_MIGRATIONS:-0}" = "1" ] || [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  if [ -f artisan ]; then
    log_info "Running migrations..."
    php artisan migrate --force || log_warning "migrate failed"
  fi
fi

# ----------------------------
# Custom command(s) on startup
# ----------------------------
if [ -n "${RUN_ON_START}" ]; then
  log_warning "RUN_ON_START is enabled: ${RUN_ON_START}"
  log_info "RUN_ON_START set; executing..."
  cd /home/container/webroot || exit 1

  # Run exactly what the user provided (can be multiple commands separated by ; or newlines)
  sh -lc "${RUN_ON_START}" || log_warning "RUN_ON_START command failed"
fi

if [ "${RUN_OPTIMIZE_CLEAR:-1}" = "1" ] || [ "${RUN_OPTIMIZE_CLEAR:-true}" = "true" ]; then
  if [ -f artisan ]; then
    log_info "Running php artisan optimize:clear..."
    php artisan optimize:clear || true
  fi
fi

log_info "Starting PHP-FPM..."
php-fpm --fpm-config /home/container/php-fpm/php-fpm.conf --daemonize \
  || { log_error "Failed to start PHP-FPM."; exit 1; }
log_success "PHP-FPM started successfully."

log_info "Starting NGINX..."
echo "[SUCCESS] Web server is running. All services started successfully."
exec /usr/sbin/nginx -c /home/container/nginx/nginx.conf -p /home/container/