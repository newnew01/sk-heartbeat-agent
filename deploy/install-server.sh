#!/bin/sh
set -eu

APP_DIR=/opt/branch-heartbeat
CONFIG_DIR=/etc/branch-heartbeat
STATE_DIR=/var/lib/branch-heartbeat
ENV_FILE="$CONFIG_DIR/heartbeat.env"
PASSWORD_FILE="$CONFIG_DIR/initial-admin-password"
INITIAL_CREDENTIALS=/root/branch-heartbeat-initial-admin.txt

if ! id branch-heartbeat >/dev/null 2>&1; then
    useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin branch-heartbeat
fi

install -d -o root -g branch-heartbeat -m 0750 "$APP_DIR" "$CONFIG_DIR"
install -d -o branch-heartbeat -g branch-heartbeat -m 0750 "$STATE_DIR"

if [ ! -x "$APP_DIR/venv/bin/python" ]; then
    python3 -m venv "$APP_DIR/venv"
fi
"$APP_DIR/venv/bin/pip" install --upgrade pip
"$APP_DIR/venv/bin/pip" install -r "$APP_DIR/requirements.txt"

if [ ! -f "$ENV_FILE" ]; then
    secret_key="$(openssl rand -hex 32)"
    umask 027
    {
        printf 'HEARTBEAT_SECRET_KEY=%s\n' "$secret_key"
        printf 'HEARTBEAT_DATABASE=%s\n' "$STATE_DIR/heartbeat.db"
        printf 'HEARTBEAT_IPSET_NAME=branch_sql_allow_v4\n'
        printf 'HEARTBEAT_LEASE_SECONDS=600\n'
        printf 'HEARTBEAT_TRUSTED_PROXY=127.0.0.1\n'
    } > "$ENV_FILE"
    chown root:branch-heartbeat "$ENV_FILE"
    chmod 0640 "$ENV_FILE"
fi

install -o root -g root -m 0644 \
    "$APP_DIR/deploy/branch-heartbeat.service" \
    /etc/systemd/system/branch-heartbeat.service

if [ ! -f "$STATE_DIR/heartbeat.db" ]; then
    admin_password="$(openssl rand -base64 24 | tr -d '\r\n')"
    umask 027
    printf '%s\n' "$admin_password" > "$PASSWORD_FILE"
    chown root:branch-heartbeat "$PASSWORD_FILE"
    chmod 0640 "$PASSWORD_FILE"

    set -a
    . "$ENV_FILE"
    set +a
    cd "$APP_DIR"
    runuser -u branch-heartbeat -- \
        "$APP_DIR/venv/bin/flask" --app wsgi create-admin \
        --username admin \
        --password-file "$PASSWORD_FILE"

    umask 077
    {
        printf 'URL=https://heartbeat.184184184.xyz/admin\n'
        printf 'username=admin\n'
        printf 'password=%s\n' "$admin_password"
    } > "$INITIAL_CREDENTIALS"
    chmod 0600 "$INITIAL_CREDENTIALS"
    rm -f "$PASSWORD_FILE"
fi

systemctl daemon-reload
systemctl enable --now branch-heartbeat.service
