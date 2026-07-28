#!/usr/bin/env bash
# Reconfigure an already-installed Branch Heartbeat Agent.
# Usage: sudo ./configure-agent.sh --device-id DEVICE_ID [--api-url URL]
set -euo pipefail

CONF_DIR="/etc/branch-heartbeat-agent"
CONF_FILE="$CONF_DIR/agent.conf"
KEY_FILE="$CONF_DIR/device.key"
SERVICE_NAME="branch-heartbeat-agent"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

if [[ ! -f "$CONF_FILE" ]]; then
  echo "Agent is not installed ($CONF_FILE not found). Run install-agent.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONF_FILE"
DEVICE_ID="$DEVICE_ID"
API_URL="$API_URL"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-id)
      DEVICE_ID="$2"; shift 2 ;;
    --api-url)
      API_URL="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64 ;;
  esac
done

if [[ ! "$DEVICE_ID" =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
  echo "Device ID may contain only letters, numbers, dot, underscore, and dash." >&2
  exit 64
fi

cat > "$CONF_FILE" <<EOF
API_URL="$API_URL"
DEVICE_ID="$DEVICE_ID"
INTERVAL_SECONDS=${INTERVAL_SECONDS:-60}
RETRY_SECONDS=${RETRY_SECONDS:-15}
REQUEST_TIMEOUT_SECONDS=${REQUEST_TIMEOUT_SECONDS:-15}
EOF
chmod 644 "$CONF_FILE"

read -r -s -p "Device Key (leave empty to keep the current one): " DEVICE_KEY
echo
if [[ -n "$DEVICE_KEY" ]]; then
  printf '%s' "$DEVICE_KEY" > "$KEY_FILE"
  chmod 600 "$KEY_FILE"
  chown root:root "$KEY_FILE"
fi
unset DEVICE_KEY

systemctl restart "$SERVICE_NAME"
echo "Reconfigured and restarted $SERVICE_NAME."
