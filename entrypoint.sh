#!/bin/sh
set -eu

sleep 1
cd /home/container || exit 1

# Pterodactyl egg uses STARTUP_CMD (your egg's env variable)
# Fallbacks keep it compatible if you ever rename it.
RAW_STARTUP="${STARTUP_CMD:-${STARTUP:-./start.sh}}"

# Expand {{VAR}} -> ${VAR} and evaluate (ptero-style templates)
TEMPLATED="$(printf '%s' "${RAW_STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')"
MODIFIED_STARTUP="$(eval "echo \"${TEMPLATED}\"")"

echo ":/home/container$ ${MODIFIED_STARTUP}"

# If MODIFIED_STARTUP looks like a script path, seed it if missing then exec it
case "${MODIFIED_STARTUP}" in
  *.sh|./*.sh|/*.sh)
    # Normalize relative paths to /home/container
    case "${MODIFIED_STARTUP}" in
      /*)  TARGET="${MODIFIED_STARTUP}" ;;
      ./*) TARGET="/home/container/${MODIFIED_STARTUP#./}" ;;
      *)   TARGET="/home/container/${MODIFIED_STARTUP}" ;;
    esac

    # Seed only if missing
    if [ ! -f "${TARGET}" ]; then
      echo "[INFO] Startup script not found at ${TARGET}. Seeding default..."
      cp /usr/local/share/ptero/default-startup.sh "${TARGET}"
      chmod +x "${TARGET}" 2>/dev/null || true
      chown container:container "${TARGET}" 2>/dev/null || true
      echo "[SUCCESS] Seeded ${TARGET}"
    else
      echo "[INFO] Using existing startup script at ${TARGET} (not overwriting)."
    fi

    # Run it directly (respects shebang: /bin/sh, /bin/ash, /bin/bash, etc.)
    exec "${TARGET}"
    ;;
  *)
    # Not a script path: treat as a command string
    exec /bin/sh -lc "${MODIFIED_STARTUP}"
    ;;
esac
