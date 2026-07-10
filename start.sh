#!/bin/ash
set -eu

# Composer cache (must be set before any composer command, including create-project)
export COMPOSER_HOME="${COMPOSER_HOME:-/home/container/.composer}"
export COMPOSER_CACHE_DIR="${COMPOSER_CACHE_DIR:-/home/container/.composer/cache}"
mkdir -p "${COMPOSER_CACHE_DIR}" 2>/dev/null || true

is_true() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

webroot_has_content() {
  [ -n "$(ls -A /home/container/webroot 2>/dev/null)" ]
}

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
RESET="\033[0m"

log_success() { echo -e "${GREEN}[SUCCESS] $1${RESET}"; }
log_warning() { echo -e "${YELLOW}[WARNING] $1${RESET}"; }
log_error()   { echo -e "${RED}[ERROR] $1${RESET}"; }
log_info()    { echo -e "[INFO] $1"; }

log_info "Cleaning up temporary files..."
rm -rf /home/container/tmp/* || { log_error "Failed to remove temporary files."; exit 1; }
log_success "Temporary files removed successfully."

cd /home/container/webroot || { log_error "webroot not found"; exit 1; }

# Defaults used by INIT_LARAVEL scaffolding
LARAVEL_PACKAGE="${LARAVEL_PACKAGE:-laravel/laravel}"
LARAVEL_VERSION="${LARAVEL_VERSION:-}"

# ----------------------------
# Optional full rebuild (explicit)
# ----------------------------
LARAVEL_INIT_MARKER="${LARAVEL_INIT_MARKER:-.laravel_auto_initialized}"
if is_true "${REBUILD_SITE:-0}"; then
  log_warning "REBUILD_SITE enabled: wiping /home/container/webroot..."
  rm -rf -- /home/container/webroot/* /home/container/webroot/.[!.]* /home/container/webroot/..?* 2>/dev/null
  rm -f "/home/container/webroot/${LARAVEL_INIT_MARKER}" 2>/dev/null || true
  log_success "webroot wiped."
fi

if is_true "${INIT_LARAVEL:-0}"; then
  if webroot_has_content; then
    log_warning "INIT_LARAVEL ignored: webroot is not empty (won't overwrite deployed site)."
  else
    log_info "INIT_LARAVEL: empty webroot, creating Laravel project..."

    log_info "Creating Laravel project via composer..."
    if [ -n "${LARAVEL_VERSION}" ]; then
      composer create-project --no-interaction --prefer-dist "${LARAVEL_PACKAGE}" /home/container/webroot "${LARAVEL_VERSION}" \
        || { log_error "composer create-project failed"; exit 1; }
    else
      composer create-project --no-interaction --prefer-dist "${LARAVEL_PACKAGE}" /home/container/webroot \
        || { log_error "composer create-project failed"; exit 1; }
    fi

    chmod -R 775 /home/container/webroot/storage /home/container/webroot/bootstrap/cache 2>/dev/null || true

    touch "/home/container/webroot/${LARAVEL_INIT_MARKER}" || true
    log_success "Laravel initialized. Marker created: ${LARAVEL_INIT_MARKER}"
  fi
fi

# ----------------------------
# Git deploy (site repo)
# ----------------------------
if [ -n "${GIT_ADDRESS:-}" ]; then
  case "${GIT_ADDRESS}" in
    git@*) REPO_URL="${GIT_ADDRESS}" ;;
    http://*|https://*) REPO_URL="${GIT_ADDRESS}" ;;
    *) REPO_URL="https://${GIT_ADDRESS}" ;;
  esac

  while [ "${REPO_URL%/}" != "${REPO_URL}" ]; do REPO_URL="${REPO_URL%/}"; done

  case "${REPO_URL}" in
    https://*@*) REPO_URL="$(printf '%s' "${REPO_URL}" | sed -E 's#^https://[^/@]+@#https://#')" ;;
  esac

  GIT_EXTRAHEADER=""
  if [ -n "${USERNAME:-}" ] && [ -n "${ACCESS_TOKEN:-}" ]; then
    case "${REPO_URL}" in
      https://*)
        AUTH_B64="$(printf '%s:%s' "${USERNAME}" "${ACCESS_TOKEN}" | base64 | tr -d '\n')"
        GIT_EXTRAHEADER="AUTHORIZATION: Basic ${AUTH_B64}"
        export GIT_TERMINAL_PROMPT=0
        ;;
    esac
  fi

  git_with_auth() {
    if [ -n "${GIT_EXTRAHEADER}" ]; then
      git -c "http.extraHeader=${GIT_EXTRAHEADER}" "$@"
    else
      git "$@"
    fi
  }

  if [ -d .git ]; then
    CURRENT_ORIGIN="$(git remote get-url origin 2>/dev/null || true)"
    if [ -n "${CURRENT_ORIGIN}" ] && [ "${CURRENT_ORIGIN}" != "${REPO_URL}" ]; then
      log_info "Updating origin URL to match GIT_ADDRESS..."
      git remote set-url origin "${REPO_URL}" 2>/dev/null || true
    fi

    if is_true "${AUTO_UPDATE:-0}"; then
      log_info "AUTO_UPDATE enabled. Fetching & pulling..."
      git_with_auth fetch --all --prune || log_warning "git fetch failed"

      if [ -n "${BRANCH:-}" ]; then
        git checkout "${BRANCH}" 2>/dev/null || log_warning "git checkout failed"
        git_with_auth pull --ff-only origin "${BRANCH}" || log_warning "git pull failed"
      else
        git_with_auth pull --ff-only || log_warning "git pull failed"
      fi
    else
      log_info "AUTO_UPDATE disabled; not pulling."
    fi
  else
    if [ -z "$(ls -A . 2>/dev/null)" ]; then
      log_info "webroot empty; cloning site..."
      if [ -n "${BRANCH:-}" ]; then
        git_with_auth clone --single-branch --branch "${BRANCH}" "${REPO_URL}" . || { log_error "git clone failed"; exit 1; }
      else
        git_with_auth clone "${REPO_URL}" . || { log_error "git clone failed"; exit 1; }
      fi
      log_success "Site cloned."
    else
      log_warning "webroot not empty and not a git repo; refusing to overwrite."
    fi
  fi
fi

# ----------------------------
# Composer install (optional)
# RUN_COMPOSER_INSTALL=1 runs every boot when composer.json exists.
# Set RUN_COMPOSER_INSTALL_ONLY_IF_MISSING=1 to restore old behavior (vendor missing only).
# ----------------------------
if [ "${RUN_COMPOSER_INSTALL:-0}" = "1" ] || [ "${RUN_COMPOSER_INSTALL:-false}" = "true" ]; then
  if [ -f composer.json ]; then
    if [ ! -f composer.lock ]; then
      log_error "composer.lock is missing. composer install was skipped."
      log_error "Deploy a project with a lock file, or run composer update manually in webroot."
      exit 1
    fi
    if [ ! -f vendor/autoload.php ] || ! is_true "${RUN_COMPOSER_INSTALL_ONLY_IF_MISSING:-0}"; then
      log_info "Running composer install..."
      COMPOSER_FLAGS_EFFECTIVE="${COMPOSER_FLAGS:---no-dev --optimize-autoloader}"
      # shellcheck disable=SC2086
      composer install --no-interaction --prefer-dist ${COMPOSER_FLAGS_EFFECTIVE} \
        || { log_error "composer install failed"; exit 1; }
      log_success "Composer install completed."
    else
      log_info "vendor/autoload.php present; RUN_COMPOSER_INSTALL_ONLY_IF_MISSING=1, skipping composer install."
    fi
  fi
fi

if [ ! -f .env ] && [ -f .env.example ]; then
  cp .env.example .env
fi

if [ -f artisan ] && [ -f .env ] && ! grep -q '^APP_KEY=base64:' .env; then
  php artisan key:generate --force || true
fi

if [ "${RUN_MIGRATIONS:-0}" = "1" ] || [ "${RUN_MIGRATIONS:-false}" = "true" ]; then
  if [ -f artisan ]; then
    log_info "Running migrations..."
    php artisan migrate --force || log_warning "migrate failed"
  fi
fi

if [ -n "${RUN_ON_START:-}" ]; then
  log_info "RUN_ON_START executing..."
  sh -lc "${RUN_ON_START}" || log_warning "RUN_ON_START failed"
fi

if [ "${RUN_OPTIMIZE_CLEAR:-0}" = "1" ] || [ "${RUN_OPTIMIZE_CLEAR:-false}" = "true" ]; then
  if [ -f artisan ]; then
    php artisan optimize:clear || true
  fi
fi

log_info "Starting PHP-FPM..."
php-fpm --fpm-config /home/container/php-fpm/php-fpm.conf --daemonize \
  || { log_error "Failed to start PHP-FPM."; exit 1; }
log_success "PHP-FPM started."

log_info "Starting NGINX..."
echo "[SUCCESS] Web server is running. All services started successfully."
exec /usr/sbin/nginx -c /home/container/nginx/nginx.conf -p /home/container/
