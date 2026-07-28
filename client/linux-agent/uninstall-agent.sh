#!/usr/bin/env bash
# Remove the Branch Heartbeat Agent service, binary, and configuration.
# Usage: sudo ./uninstall-agent.sh [--purge-data]
set -euo pipefail

INSTALL_DIR="/opt/branch-heartbeat-agent"
CONF_DIR="/etc/branch-heartbeat-agent"
DATA_DIR="/var/lib/branch-heartbeat-agent"
UNIT_FILE="/etc/systemd/system/branch-heartbeat-agent.service"
SERVICE_NAME="branch-heartbeat-agent"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "This script must be run as root (sudo)." >&2
  exit 1
fi

PURGE_DATA="false"
if [[ "${1:-}" == "--purge-data" ]]; then
  PURGE_DATA="true"
fi

systemctl stop "$SERVICE_NAME" 2>/dev/null || true
systemctl disable "$SERVICE_NAME" 2>/dev/null || true

rm -f "$UNIT_FILE"
systemctl daemon-reload

rm -rf "$INSTALL_DIR"

if [[ "$PURGE_DATA" == "true" ]]; then
  echo "Removing configuration and Device Key at $CONF_DIR and $DATA_DIR ..."
  rm -rf "$CONF_DIR" "$DATA_DIR"
else
  echo "Configuration kept at $CONF_DIR and $DATA_DIR (pass --purge-data to remove them too)."
fi

echo "Uninstalled $SERVICE_NAME."
