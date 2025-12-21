#!/bin/ash
set -eu

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

# ----------------------------
# Optional full rebuild (explicit)
# ----------------------------
LARAVEL_INIT_MARKER="${LARAVEL_INIT_MARKER:-.laravel_auto_initialized}"
if [ "${REBUILD_SITE:-0}" = "1" ] || [ "${REBUILD_SITE:-false}" = "true" ]; then
  log_warning "REBUILD_SITE enabled: wiping /home/container/webroot..."
  rm -rf -- /home/container/webroot/* /home/container/webroot/.[!.]* /home/container/webroot/..?* 2>/dev/null
  rm -f "/home/container/webroot/${LARAVEL_INIT_MARKER}" 2>/dev/null || true
  log_success "webroot wiped."
fi

# ----------------------------
# INIT_LARAVEL (one-time scaffold; only if no git site)
# ----------------------------
LARAVEL_PACKAGE="${LARAVEL_PACKAGE:-laravel/laravel}"
LARAVEL_VERSION="${LARAVEL_VERSION:-}"

if [ "${AUTO_UPDATE:-0}" = "1" ] || [ "${AUTO_UPDATE:-false}" = "true" ]; then
  if [ -n "${GIT_ADDRESS}" ]; then
    log_info "AUTO_UPDATE enabled. Syncing from git..."

    # Normalize URL
    case "${GIT_ADDRESS}" in
      git@*) REPO_URL="${GIT_ADDRESS}" ;;
      http://*|https://*) REPO_URL="${GIT_ADDRESS}" ;;
      *) REPO_URL="https://${GIT_ADDRESS}" ;;
    esac

    # Trim trailing slashes
    while [ "${REPO_URL%/}" != "${REPO_URL}" ]; do REPO_URL="${REPO_URL%/}"; done

    # Strip https userinfo (https://user@host/...) that breaks some git/curl builds
    case "${REPO_URL}" in
      https://*@*) REPO_URL="$(printf '%s' "${REPO_URL}" | sed -E 's#^https://[^/@]+@#https://#')" ;;
    esac

    # Do not force .git; also strip it if someone provided it
    case "${REPO_URL}" in
      *.git) REPO_URL="${REPO_URL%.git}" ;;
    esac

    # Build Basic auth header for HTTPS token auth (GitHub + Azure DevOps)
    GIT_EXTRAHEADER=""
    if [ -n "${USERNAME}" ] && [ -n "${ACCESS_TOKEN}" ]; then
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
      # Self-heal: sanitize whatever origin is currently set to
      ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"

      if [ -n "${ORIGIN_URL}" ]; then
        FIXED_URL="${ORIGIN_URL}"

        # trim trailing slashes
        while [ "${FIXED_URL%/}" != "${FIXED_URL}" ]; do FIXED_URL="${FIXED_URL%/}"; done
        # remove userinfo
        case "${FIXED_URL}" in
          https://*@*) FIXED_URL="$(printf '%s' "${FIXED_URL}" | sed -E 's#^https://[^/@]+@#https://#')" ;;
        esac
        # remove .git suffix if present
        case "${FIXED_URL}" in
          *.git) FIXED_URL="${FIXED_URL%.git}" ;;
        esac

        if [ "${FIXED_URL}" != "${ORIGIN_URL}" ]; then
          log_info "Fixing origin URL..."
          git remote set-url origin "${FIXED_URL}" 2>/dev/null || true
        fi
      fi

      # Ensure origin matches the configured repo URL (clean)
      git remote set-url origin "${REPO_URL}" 2>/dev/null || true

      log_info "AUTO_UPDATE enabled. Pulling..."
      git_with_auth fetch --all --prune || log_warning "git fetch failed"

      if [ -n "${BRANCH}" ]; then
        git checkout "${BRANCH}" 2>/dev/null || true
        git_with_auth pull --ff-only origin "${BRANCH}" || log_warning "git pull failed"
      else
        git_with_auth pull --ff-only || log_warning "git pull failed"
      fi
    else
      if [ -z "$(ls -A . 2>/dev/null)" ]; then
        log_info "webroot empty; cloning repo..."
        if [ -n "${BRANCH}" ]; then
          git_with_auth clone --single-branch --branch "${BRANCH}" "${REPO_URL}" . || log_warning "git clone failed"
        else
          git_with_auth clone "${REPO_URL}" . || log_warning "git clone failed"
        fi
      else
        log_warning "AUTO_UPDATE is on but webroot is not a git repo; skipping pull."
      fi
    fi
  else
    log_warning "AUTO_UPDATE enabled but GIT_ADDRESS is empty; skipping."
  fi
fi



# ----------------------------
# Git deploy (site repo)
# - clone if webroot is empty (first boot)
# - pull only if AUTO_UPDATE=1 (optional)
# ----------------------------
if [ -n "${GIT_ADDRESS:-}" ]; then
  case "${GIT_ADDRESS}" in
    git@*) REPO_URL="${GIT_ADDRESS}" ;;
    http://*|https://*) REPO_URL="${GIT_ADDRESS}" ;;
    *) REPO_URL="https://${GIT_ADDRESS}" ;;
  esac

  [ "${REPO_URL##*.}" != "git" ] && REPO_URL="${REPO_URL}.git"

  if [ -n "${USERNAME:-}" ] && [ -n "${ACCESS_TOKEN:-}" ]; then
    REPO_URL="https://${USERNAME}:${ACCESS_TOKEN}@${REPO_URL#https://}"
  fi

  if [ -d .git ]; then
    if [ "${AUTO_UPDATE:-0}" = "1" ] || [ "${AUTO_UPDATE:-false}" = "true" ]; then
      log_info "AUTO_UPDATE enabled. Pulling..."
      git remote set-url origin "${REPO_URL}" 2>/dev/null || true
      git fetch --all --prune || log_warning "git fetch failed"
      if [ -n "${BRANCH:-}" ]; then
        git checkout "${BRANCH}" 2>/dev/null || true
        git pull --ff-only origin "${BRANCH}" || log_warning "git pull failed"
      else
        git pull --ff-only || log_warning "git pull failed"
      fi
    else
      log_info "AUTO_UPDATE disabled; not pulling."
    fi
  else
    if [ -z "$(ls -A . 2>/dev/null)" ]; then
      log_info "webroot empty; cloning site..."
      if [ -n "${BRANCH:-}" ]; then
        git clone --single-branch --branch "${BRANCH}" "${REPO_URL}" . || { log_error "git clone failed"; exit 1; }
      else
        git clone "${REPO_URL}" . || { log_error "git clone failed"; exit 1; }
      fi
      log_success "Site cloned."
    else
      log_warning "webroot not empty and not a git repo; refusing to overwrite."
    fi
  fi
fi

# ----------------------------
# Composer install (optional)
# ----------------------------
if [ "${RUN_COMPOSER_INSTALL:-0}" = "1" ] || [ "${RUN_COMPOSER_INSTALL:-false}" = "true" ]; then
  if [ -f composer.json ] && [ ! -f vendor/autoload.php ]; then
    log_info "Running composer install..."
    COMPOSER_FLAGS_EFFECTIVE="${COMPOSER_FLAGS:-"--no-dev --optimize-autoloader"}"
    composer install --no-interaction --prefer-dist ${COMPOSER_FLAGS_EFFECTIVE} \
      || { log_error "composer install failed"; exit 1; }
    log_success "Composer install completed."
  fi
fi

# Ensure .env exists if Laravel scaffold or repo includes .env.example
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
