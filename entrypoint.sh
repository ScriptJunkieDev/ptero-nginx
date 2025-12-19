#!/bin/bash
sleep 1

cd /home/container || exit 1

# Default if STARTUP is empty
STARTUP="${STARTUP:-start.sh}"

# Expand {{VAR}} -> ${VAR} and evaluate
MODIFIED_STARTUP=$(eval echo "$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')")

echo ":/home/container$ ${MODIFIED_STARTUP}"

# If it's a shell script path/name, run with bash
case "${MODIFIED_STARTUP}" in
  *.sh|./*.sh|/*.sh)
    exec /bin/bash "${MODIFIED_STARTUP}"
    ;;
  *)
    # Run arbitrary commands reliably (handles args/quotes)
    exec /bin/sh -lc "${MODIFIED_STARTUP}"
    ;;
esac
