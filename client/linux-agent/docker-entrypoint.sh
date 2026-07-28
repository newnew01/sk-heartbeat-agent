#!/usr/bin/env bash
# Writes agent.conf / device.key from environment variables (or Docker
# secrets) then hands off to branch-heartbeat-agent.sh.
set -euo pipefail

CONF_DIR="/etc/branch-heartbeat-agent"
mkdir -p "$CONF_DIR"

: "${API_URL:=https://heartbeat.184184184.xyz/api/v1/heartbeat}"
: "${DEVICE_ID:?DEVICE_ID environment variable is required}"
: "${INTERVAL_SECONDS:=60}"
: "${RETRY_SECONDS:=15}"
: "${REQUEST_TIMEOUT_SECONDS:=15}"

if [[ -z "${DEVICE_KEY:-}" && -z "${DEVICE_KEY_FILE:-}" ]]; then
  echo "Set DEVICE_KEY or DEVICE_KEY_FILE (e.g. a Docker secret path)." >&2
  exit 64
fi

cat > "$CONF_DIR/agent.conf" <<EOF
API_URL="$API_URL"
DEVICE_ID="$DEVICE_ID"
INTERVAL_SECONDS=$INTERVAL_SECONDS
RETRY_SECONDS=$RETRY_SECONDS
REQUEST_TIMEOUT_SECONDS=$REQUEST_TIMEOUT_SECONDS
EOF
chmod 600 "$CONF_DIR/agent.conf"

if [[ -n "${DEVICE_KEY_FILE:-}" ]]; then
  cp "$DEVICE_KEY_FILE" "$CONF_DIR/device.key"
else
  printf '%s' "$DEVICE_KEY" > "$CONF_DIR/device.key"
fi
chmod 600 "$CONF_DIR/device.key"
unset DEVICE_KEY

exec /usr/local/bin/branch-heartbeat-agent.sh
