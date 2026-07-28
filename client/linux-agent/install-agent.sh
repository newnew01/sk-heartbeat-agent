#!/usr/bin/env bash
# Install the Branch Heartbeat Agent as a systemd service.
# Usage: sudo ./install-agent.sh --device-id DEVICE_ID [--api-url URL]
set -euo pipefail

INSTALL_DIR="/opt/branch-heartbeat-agent"
CONF_DIR="/etc/branch-heartbeat-agent"
CONF_FILE="$CONF_DIR/agent.conf"
KEY_FILE="$CONF_DIR/device.key"
DATA_DIR="/var/lib/branch-heartbeat-agent"
UNIT_FILE="/etc/systemd/system/branch-heartbeat-agent.service"
SERVICE_NAME="branch-heartbeat-agent"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command '$cmd' is not installed. Install it first (e.g. apt-get install -y curl jq)." >&2
    exit 1
  fi
done

DEVICE_ID=""
API_URL="https://heartbeat.184184184.xyz/api/v1/heartbeat"
INTERVAL_SECONDS=60
RETRY_SECONDS=15
REQUEST_TIMEOUT_SECONDS=15

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-id)
      DEVICE_ID="$2"; shift 2 ;;
    --api-url)
      API_URL="$2"; shift 2 ;;
    --interval-seconds)
      INTERVAL_SECONDS="$2"; shift 2 ;;
    --retry-seconds)
      RETRY_SECONDS="$2"; shift 2 ;;
    --timeout-seconds)
      REQUEST_TIMEOUT_SECONDS="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 64 ;;
  esac
done

if [[ -z "$DEVICE_ID" ]]; then
  echo "Usage: sudo ./install-agent.sh --device-id DEVICE_ID [--api-url URL]" >&2
  exit 64
fi

if [[ ! "$DEVICE_ID" =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
  echo "Device ID may contain only letters, numbers, dot, underscore, and dash." >&2
  exit 64
fi

echo "Installing binary to $INSTALL_DIR ..."
install -d -m 0755 "$INSTALL_DIR"
install -m 0755 "$SCRIPT_DIR/branch-heartbeat-agent.sh" "$INSTALL_DIR/branch-heartbeat-agent.sh"
install -m 0755 "$SCRIPT_DIR/get-agent-status.sh" "$INSTALL_DIR/get-agent-status.sh"
install -m 0755 "$SCRIPT_DIR/configure-agent.sh" "$INSTALL_DIR/configure-agent.sh"
install -m 0755 "$SCRIPT_DIR/uninstall-agent.sh" "$INSTALL_DIR/uninstall-agent.sh"

echo "Writing configuration to $CONF_DIR ..."
install -d -m 0755 "$CONF_DIR"
cat > "$CONF_FILE" <<EOF
API_URL="$API_URL"
DEVICE_ID="$DEVICE_ID"
INTERVAL_SECONDS=$INTERVAL_SECONDS
RETRY_SECONDS=$RETRY_SECONDS
REQUEST_TIMEOUT_SECONDS=$REQUEST_TIMEOUT_SECONDS
EOF
chmod 644 "$CONF_FILE"

read -r -s -p "Device Key: " DEVICE_KEY
echo
if [[ -z "$DEVICE_KEY" ]]; then
  echo "Device Key was not provided." >&2
  exit 64
fi
printf '%s' "$DEVICE_KEY" > "$KEY_FILE"
unset DEVICE_KEY
chmod 600 "$KEY_FILE"
chown root:root "$KEY_FILE"

install -d -m 0700 "$DATA_DIR"

echo "Installing systemd unit ..."
install -m 0644 "$SCRIPT_DIR/branch-heartbeat-agent.service" "$UNIT_FILE"

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo "Installed and started $SERVICE_NAME."
echo "Check status with: $INSTALL_DIR/get-agent-status.sh"
