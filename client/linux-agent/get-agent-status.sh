#!/usr/bin/env bash
# Print the Branch Heartbeat Agent status and systemd unit state.
set -uo pipefail

STATUS_FILE="/var/lib/branch-heartbeat-agent/status.json"
SERVICE_NAME="branch-heartbeat-agent"

if [[ -f "$STATUS_FILE" ]]; then
  if command -v jq >/dev/null 2>&1; then
    jq . "$STATUS_FILE"
    state="$(jq -r '.state' "$STATUS_FILE")"
  else
    cat "$STATUS_FILE"
    state="unknown"
  fi
else
  echo '{"state":"not-started"}'
  state="not-started"
fi

echo
systemctl status "$SERVICE_NAME" --no-pager || true

case "$state" in
  healthy) exit 0 ;;
  not-started) exit 2 ;;
  *) exit 1 ;;
esac
