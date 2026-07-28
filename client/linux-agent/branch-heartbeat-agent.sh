#!/usr/bin/env bash
# Branch Heartbeat Agent for Linux.
# Sends a heartbeat to the server every $INTERVAL_SECONDS so the branch's
# current public IPv4 stays allow-listed. Meant to run under systemd
# (see branch-heartbeat-agent.service), which restarts it on any exit.
set -uo pipefail

CONF_FILE="/etc/branch-heartbeat-agent/agent.conf"
KEY_FILE="/etc/branch-heartbeat-agent/device.key"
STATUS_DIR="/var/lib/branch-heartbeat-agent"
STATUS_FILE="$STATUS_DIR/status.json"

for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command '$cmd' is not installed." >&2
    exit 1
  fi
done

if [[ ! -f "$CONF_FILE" ]]; then
  echo "Missing $CONF_FILE. Run install-agent.sh first." >&2
  exit 1
fi
if [[ ! -f "$KEY_FILE" ]]; then
  echo "Missing $KEY_FILE. Run install-agent.sh first." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONF_FILE"
: "${API_URL:?API_URL is not set in $CONF_FILE}"
: "${DEVICE_ID:?DEVICE_ID is not set in $CONF_FILE}"
INTERVAL_SECONDS="${INTERVAL_SECONDS:-60}"
RETRY_SECONDS="${RETRY_SECONDS:-15}"
REQUEST_TIMEOUT_SECONDS="${REQUEST_TIMEOUT_SECONDS:-15}"

mkdir -p "$STATUS_DIR"
chmod 700 "$STATUS_DIR"

LAST_SUCCESS_AT=""

write_status() {
  local state="$1" observed_ip="$2" allowed_until="$3" last_error="$4"
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "$state" == "healthy" ]]; then
    LAST_SUCCESS_AT="$now"
  fi

  local tmp="$STATUS_FILE.tmp"
  jq -n \
    --arg state "$state" \
    --arg updatedAt "$now" \
    --arg lastSuccessAt "$LAST_SUCCESS_AT" \
    --arg observedIp "$observed_ip" \
    --arg allowedUntil "$allowed_until" \
    --arg lastError "$last_error" \
    '{
      state: $state,
      updatedAt: $updatedAt,
      lastSuccessAt: (if $lastSuccessAt == "" then null else $lastSuccessAt end),
      observedIp: (if $observedIp == "" then null else $observedIp end),
      allowedUntil: (if $allowedUntil == "" then null else $allowedUntil end),
      lastError: (if $lastError == "" then null else $lastError end)
    }' > "$tmp"
  mv "$tmp" "$STATUS_FILE"
  chmod 600 "$STATUS_FILE"
}

echo "Branch Heartbeat Agent starting. Device $DEVICE_ID -> $API_URL"

while true; do
  device_key="$(cat "$KEY_FILE")"
  response_file="$(mktemp)"
  error_file="$(mktemp)"

  http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
    --max-time "$REQUEST_TIMEOUT_SECONDS" \
    -X POST "$API_URL" \
    -H "Authorization: Bearer $device_key" \
    -H "X-Device-ID: $DEVICE_ID" \
    -H 'User-Agent: BranchHeartbeat-Agent-Linux/1.0' \
    2>"$error_file")"
  curl_exit=$?
  unset device_key

  sleep_seconds="$RETRY_SECONDS"

  if [[ $curl_exit -ne 0 ]]; then
    error_message="curl exit $curl_exit: $(tr '\n' ' ' < "$error_file" | cut -c1-300)"
    echo "Heartbeat failed: $error_message" >&2
    write_status "error" "" "" "$error_message"
  elif [[ "$http_code" != "200" ]]; then
    error_message="Heartbeat API returned HTTP $http_code"
    echo "Heartbeat failed: $error_message" >&2
    write_status "error" "" "" "$error_message"
  else
    status_value="$(jq -r '.status // empty' "$response_file" 2>/dev/null)"
    if [[ "$status_value" != "ok" ]]; then
      error_message="Heartbeat API response is invalid"
      echo "Heartbeat failed: $error_message" >&2
      write_status "error" "" "" "$error_message"
    else
      observed_ip="$(jq -r '.observedIp // empty' "$response_file")"
      allowed_until="$(jq -r '.allowedUntil // empty' "$response_file")"
      echo "Heartbeat succeeded. Public IP $observed_ip; allowed until $allowed_until."
      write_status "healthy" "$observed_ip" "$allowed_until" ""
      sleep_seconds="$INTERVAL_SECONDS"
    fi
  fi

  rm -f "$response_file" "$error_file"
  sleep "$sleep_seconds"
done
