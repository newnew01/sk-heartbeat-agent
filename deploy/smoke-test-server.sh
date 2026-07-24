#!/bin/sh
set -eu

APP_DIR=/opt/branch-heartbeat
DATABASE=/var/lib/branch-heartbeat/heartbeat.db
IPSET_NAME=branch_sql_allow_v4
DEVICE_UID="deployment-smoke-$$"
DEVICE_TOKEN="$(openssl rand -hex 32)"
TOKEN_HASH="$(printf '%s' "$DEVICE_TOKEN" | sha256sum | awk '{print $1}')"
PYTHON="$APP_DIR/venv/bin/python"

device_id="$(
    runuser -u branch-heartbeat -- env \
        DATABASE="$DATABASE" \
        DEVICE_UID="$DEVICE_UID" \
        TOKEN_HASH="$TOKEN_HASH" \
        "$PYTHON" -c '
import datetime
import os
import sqlite3

now = datetime.datetime.now(datetime.timezone.utc).isoformat()
conn = sqlite3.connect(os.environ["DATABASE"])
cursor = conn.execute(
    "INSERT INTO branches(code,name,enabled,created_at) VALUES(?,?,1,?)",
    (os.environ["DEVICE_UID"], "Deployment smoke test", now),
)
branch_id = cursor.lastrowid
cursor = conn.execute(
    """INSERT INTO devices
       (branch_id,code,device_uid,token_hash,enabled,created_at)
       VALUES(?,?,?,?,1,?)""",
    (branch_id, "smoke-device", os.environ["DEVICE_UID"], os.environ["TOKEN_HASH"], now),
)
conn.commit()
print(cursor.lastrowid)
'
)"

cleanup() {
    runuser -u branch-heartbeat -- env \
        DATABASE="$DATABASE" \
        DEVICE_UID="$DEVICE_UID" \
        DEVICE_ID="$device_id" \
        "$PYTHON" -c '
import os
import sqlite3

conn = sqlite3.connect(os.environ["DATABASE"])
conn.execute("DELETE FROM audit_logs WHERE target_type = ? AND target_id = ?", ("device", int(os.environ["DEVICE_ID"])))
conn.execute("DELETE FROM branches WHERE code = ?", (os.environ["DEVICE_UID"],))
conn.commit()
' || true
    if [ -n "${observed_ip:-}" ]; then
        ipset -exist del "$IPSET_NAME" "$observed_ip" || true
    fi
}
trap cleanup EXIT

response="$(
    curl -fsS \
        -X POST \
        -H "Authorization: Bearer $DEVICE_TOKEN" \
        -H "X-Device-ID: $DEVICE_UID" \
        https://heartbeat.184184184.xyz/api/v1/heartbeat
)"

observed_ip="$(
    printf '%s' "$response" |
        "$PYTHON" -c 'import json,sys; print(json.load(sys.stdin)["observedIp"])'
)"

ipset test "$IPSET_NAME" "$observed_ip"
printf '%s\n' "$response"
