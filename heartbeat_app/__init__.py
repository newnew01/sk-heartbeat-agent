import hashlib
import hmac
import ipaddress
import json
import os
import re
import secrets
import sqlite3
import subprocess
from datetime import datetime, timedelta, timezone
from functools import wraps
from pathlib import Path

import click
from flask import (
    Flask,
    abort,
    flash,
    g,
    jsonify,
    redirect,
    render_template,
    request,
    session,
    url_for,
)
from werkzeug.security import check_password_hash, generate_password_hash


DEVICE_CODE_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")
BANGKOK_TIMEZONE = timezone(timedelta(hours=7))


def utc_now():
    return datetime.now(timezone.utc)


def iso_utc(value):
    return value.astimezone(timezone.utc).isoformat(timespec="seconds")


def format_bangkok_time(value):
    if not value:
        return "—"
    try:
        parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(BANGKOK_TIMEZONE).strftime("%d/%m/%Y %H:%M:%S")
    except (TypeError, ValueError):
        return str(value)


def create_app(test_config=None):
    app = Flask(__name__, instance_relative_config=False)
    app.config.from_mapping(
        SECRET_KEY=os.environ.get("HEARTBEAT_SECRET_KEY", ""),
        DATABASE=os.environ.get(
            "HEARTBEAT_DATABASE", "/var/lib/branch-heartbeat/heartbeat.db"
        ),
        IPSET_NAME=os.environ.get("HEARTBEAT_IPSET_NAME", "branch_sql_allow_v4"),
        LEASE_SECONDS=int(os.environ.get("HEARTBEAT_LEASE_SECONDS", "600")),
        TRUSTED_PROXY=os.environ.get("HEARTBEAT_TRUSTED_PROXY", "127.0.0.1"),
        SESSION_COOKIE_SECURE=True,
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Strict",
        PERMANENT_SESSION_LIFETIME=timedelta(minutes=30),
        MAX_CONTENT_LENGTH=16 * 1024,
    )
    if test_config:
        app.config.update(test_config)
    if not app.config["SECRET_KEY"]:
        raise RuntimeError("HEARTBEAT_SECRET_KEY is required")

    Path(app.config["DATABASE"]).parent.mkdir(parents=True, exist_ok=True)

    @app.teardown_appcontext
    def close_database(_error=None):
        database = g.pop("database", None)
        if database is not None:
            database.close()

    def database():
        if "database" not in g:
            conn = sqlite3.connect(app.config["DATABASE"], timeout=10)
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA foreign_keys = ON")
            conn.execute("PRAGMA journal_mode = WAL")
            g.database = conn
        return g.database

    def initialize_database():
        schema = Path(__file__).with_name("schema.sql").read_text(encoding="utf-8")
        database().executescript(schema)
        database().commit()

    def audit(action, target_type=None, target_id=None, details=None):
        actor = session.get("admin_username", "device")
        database().execute(
            """
            INSERT INTO audit_logs
                (actor, action, target_type, target_id, details, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                actor,
                action,
                target_type,
                target_id,
                json.dumps(details or {}, ensure_ascii=False),
                iso_utc(utc_now()),
            ),
        )

    def update_ipset_member(source_ip, desired_expires, comment):
        now = utc_now()
        furthest_expires = desired_expires
        rows = database().execute(
            """
            SELECT d.expires_at
            FROM devices d
            JOIN branches b ON b.id = d.branch_id
            WHERE d.observed_ip = ?
              AND d.enabled = 1
              AND b.enabled = 1
              AND d.expires_at > ?
            UNION ALL
            SELECT expires_at
            FROM emergency_ip_allowances
            WHERE ip_address = ?
              AND revoked_at IS NULL
              AND expires_at > ?
            """,
            (source_ip, iso_utc(now), source_ip, iso_utc(now)),
        ).fetchall()
        for row in rows:
            try:
                candidate = datetime.fromisoformat(
                    row["expires_at"].replace("Z", "+00:00")
                )
                if candidate.tzinfo is None:
                    candidate = candidate.replace(tzinfo=timezone.utc)
                furthest_expires = max(furthest_expires, candidate)
            except (AttributeError, TypeError, ValueError):
                app.logger.warning("Ignoring invalid expires_at value in database")

        timeout_seconds = max(1, int((furthest_expires - now).total_seconds()))
        subprocess.run(
            [
                "/usr/sbin/ipset",
                "-exist",
                "add",
                app.config["IPSET_NAME"],
                source_ip,
                "timeout",
                str(timeout_seconds),
                "comment",
                comment[:255],
            ],
            check=True,
            capture_output=True,
            text=True,
            timeout=3,
        )

    def delete_ipset_member_if_unused(source_ip, excluding_device_id=None):
        if not source_ip:
            return
        query = """
            SELECT 1
            FROM devices d
            JOIN branches b ON b.id = d.branch_id
            WHERE d.observed_ip = ?
              AND d.enabled = 1
              AND b.enabled = 1
              AND d.expires_at > ?
        """
        params = [source_ip, iso_utc(utc_now())]
        if excluding_device_id is not None:
            query += " AND d.id != ?"
            params.append(excluding_device_id)
        device_still_uses_ip = database().execute(query, params).fetchone()
        allowance_still_uses_ip = database().execute(
            """
            SELECT 1
            FROM emergency_ip_allowances
            WHERE ip_address = ?
              AND revoked_at IS NULL
              AND expires_at > ?
            """,
            (source_ip, iso_utc(utc_now())),
        ).fetchone()
        if device_still_uses_ip or allowance_still_uses_ip:
            try:
                update_ipset_member(source_ip, utc_now(), "active-lease")
            except (subprocess.SubprocessError, OSError):
                app.logger.exception("Unable to refresh shared IP in ipset")
            return
        try:
            subprocess.run(
                [
                    "/usr/sbin/ipset",
                    "-exist",
                    "del",
                    app.config["IPSET_NAME"],
                    source_ip,
                ],
                check=True,
                capture_output=True,
                text=True,
                timeout=3,
            )
        except (subprocess.SubprocessError, OSError):
            app.logger.exception("Unable to remove IP from ipset")

    def csrf_token():
        token = session.get("csrf_token")
        if not token:
            token = secrets.token_urlsafe(32)
            session["csrf_token"] = token
        return token

    app.jinja_env.globals["csrf_token"] = csrf_token
    app.jinja_env.filters["bangkok_time"] = format_bangkok_time

    def require_csrf():
        expected = session.get("csrf_token", "")
        supplied = request.form.get("csrf_token", "")
        if not expected or not hmac.compare_digest(expected, supplied):
            abort(400, "Invalid CSRF token")

    def login_required(view):
        @wraps(view)
        def wrapped(*args, **kwargs):
            if not session.get("admin_id"):
                return redirect(url_for("login", next=request.path))
            return view(*args, **kwargs)

        return wrapped

    @app.cli.command("init-db")
    def init_db_command():
        initialize_database()
        click.echo("Database initialized.")

    @app.cli.command("create-admin")
    @click.option("--username", prompt=True)
    @click.option(
        "--password-file",
        type=click.Path(exists=True, dir_okay=False, path_type=Path),
        help="Read the initial password from a protected file instead of prompting.",
    )
    def create_admin_command(username, password_file):
        initialize_database()
        username = username.strip()
        if not username:
            raise click.ClickException("Username is required")
        if password_file:
            password = password_file.read_text(encoding="utf-8").strip()
        else:
            password = click.prompt(
                "Password", hide_input=True, confirmation_prompt=True
            )
        if len(password) < 12:
            raise click.ClickException("Password must contain at least 12 characters")
        try:
            database().execute(
                """
                INSERT INTO admins (username, password_hash, created_at)
                VALUES (?, ?, ?)
                """,
                (username, generate_password_hash(password), iso_utc(utc_now())),
            )
            database().commit()
        except sqlite3.IntegrityError as exc:
            raise click.ClickException("Username already exists") from exc
        click.echo(f"Admin {username!r} created.")

    @app.get("/healthz")
    def healthz():
        return jsonify(status="ok")

    @app.route("/login", methods=["GET", "POST"])
    def login():
        initialize_database()
        if request.method == "POST":
            require_csrf()
            username = request.form.get("username", "").strip()
            password = request.form.get("password", "")
            admin = database().execute(
                "SELECT * FROM admins WHERE username = ?", (username,)
            ).fetchone()
            if admin and check_password_hash(admin["password_hash"], password):
                session.clear()
                session.permanent = True
                session["admin_id"] = admin["id"]
                session["admin_username"] = admin["username"]
                session["csrf_token"] = secrets.token_urlsafe(32)
                return redirect(url_for("dashboard"))
            flash("ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง", "error")
        return render_template("login.html")

    @app.post("/logout")
    @login_required
    def logout():
        require_csrf()
        session.clear()
        return redirect(url_for("login"))

    @app.get("/admin")
    @login_required
    def dashboard():
        initialize_database()
        branches = database().execute(
            """
            SELECT b.*,
                   COUNT(d.id) AS device_count,
                   SUM(CASE WHEN b.enabled = 1
                             AND d.enabled = 1
                             AND d.expires_at > ? THEN 1 ELSE 0 END) AS online_count
            FROM branches b
            LEFT JOIN devices d ON d.branch_id = b.id
            GROUP BY b.id
            ORDER BY b.code
            """,
            (iso_utc(utc_now()),),
        ).fetchall()
        devices = database().execute(
            """
            SELECT d.*, b.code AS branch_code, b.name AS branch_name,
                   CASE WHEN b.enabled = 1
                              AND d.enabled = 1
                              AND d.expires_at > ?
                        THEN 1 ELSE 0 END AS is_online
            FROM devices d
            JOIN branches b ON b.id = d.branch_id
            ORDER BY b.code, d.code
            """,
            (iso_utc(utc_now()),),
        ).fetchall()
        logs = database().execute(
            "SELECT * FROM audit_logs ORDER BY id DESC LIMIT 25"
        ).fetchall()
        emergency_allowances = database().execute(
            """
            SELECT *
            FROM emergency_ip_allowances
            WHERE revoked_at IS NULL AND expires_at > ?
            ORDER BY expires_at
            """,
            (iso_utc(utc_now()),),
        ).fetchall()
        online_total = sum((branch["online_count"] or 0) for branch in branches)
        return render_template(
            "dashboard.html",
            branches=branches,
            devices=devices,
            logs=logs,
            emergency_allowances=emergency_allowances,
            online_total=online_total,
            now=iso_utc(utc_now()),
        )

    @app.post("/admin/emergency-ip-allowances")
    @login_required
    def create_emergency_ip_allowance():
        require_csrf()
        supplied_ip = request.form.get("ip_address", "").strip()
        note = request.form.get("note", "").strip()
        try:
            duration_minutes = int(request.form.get("duration_minutes", ""))
            address = ipaddress.ip_address(supplied_ip)
        except (TypeError, ValueError):
            flash("IP หรือระยะเวลาไม่ถูกต้อง", "error")
            return redirect(url_for("dashboard"))
        if address.version != 4:
            flash("รองรับเฉพาะ IPv4", "error")
            return redirect(url_for("dashboard"))
        if not 1 <= duration_minutes <= 1440:
            flash("ระยะเวลาต้องอยู่ระหว่าง 1 ถึง 1,440 นาที", "error")
            return redirect(url_for("dashboard"))
        if len(note) > 200:
            flash("หมายเหตุต้องไม่เกิน 200 ตัวอักษร", "error")
            return redirect(url_for("dashboard"))

        source_ip = str(address)
        created_at = utc_now()
        expires = created_at + timedelta(minutes=duration_minutes)
        try:
            update_ipset_member(source_ip, expires, "emergency-admin")
        except (subprocess.SubprocessError, OSError):
            app.logger.exception("Unable to add emergency IP allowance")
            flash("เพิ่ม IP ใน firewall ไม่สำเร็จ", "error")
            return redirect(url_for("dashboard"))

        cursor = database().execute(
            """
            INSERT INTO emergency_ip_allowances
                (ip_address, note, created_by, created_at, expires_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                source_ip,
                note,
                session["admin_username"],
                iso_utc(created_at),
                iso_utc(expires),
            ),
        )
        audit(
            "emergency_ip.create",
            "emergency_ip",
            cursor.lastrowid,
            {
                "ip": source_ip,
                "durationMinutes": duration_minutes,
                "expiresAt": iso_utc(expires),
                "note": note,
            },
        )
        database().commit()
        flash(f"อนุญาต {source_ip} ชั่วคราวแล้ว", "success")
        return redirect(url_for("dashboard"))

    @app.post("/admin/emergency-ip-allowances/<int:allowance_id>/revoke")
    @login_required
    def revoke_emergency_ip_allowance(allowance_id):
        require_csrf()
        allowance = database().execute(
            """
            SELECT * FROM emergency_ip_allowances
            WHERE id = ? AND revoked_at IS NULL
            """,
            (allowance_id,),
        ).fetchone()
        if not allowance:
            abort(404)
        revoked_at = iso_utc(utc_now())
        database().execute(
            "UPDATE emergency_ip_allowances SET revoked_at = ? WHERE id = ?",
            (revoked_at, allowance_id),
        )
        audit(
            "emergency_ip.revoke",
            "emergency_ip",
            allowance_id,
            {"ip": allowance["ip_address"]},
        )
        database().commit()
        delete_ipset_member_if_unused(allowance["ip_address"])
        flash(f"ยกเลิกสิทธิ์ {allowance['ip_address']} แล้ว", "success")
        return redirect(url_for("dashboard"))

    @app.post("/admin/branches")
    @login_required
    def create_branch():
        require_csrf()
        code = request.form.get("code", "").strip().lower()
        name = request.form.get("name", "").strip()
        if not DEVICE_CODE_RE.fullmatch(code) or not name:
            flash("รหัสหรือชื่อสาขาไม่ถูกต้อง", "error")
            return redirect(url_for("dashboard"))
        try:
            cursor = database().execute(
                """
                INSERT INTO branches (code, name, enabled, created_at)
                VALUES (?, ?, 1, ?)
                """,
                (code, name, iso_utc(utc_now())),
            )
            audit("branch.create", "branch", cursor.lastrowid, {"code": code})
            database().commit()
            flash("เพิ่มสาขาแล้ว", "success")
        except sqlite3.IntegrityError:
            flash("รหัสสาขานี้มีอยู่แล้ว", "error")
        return redirect(url_for("dashboard"))

    @app.post("/admin/branches/<int:branch_id>/toggle")
    @login_required
    def toggle_branch(branch_id):
        require_csrf()
        branch = database().execute(
            "SELECT * FROM branches WHERE id = ?", (branch_id,)
        ).fetchone()
        if not branch:
            abort(404)
        enabled = 0 if branch["enabled"] else 1
        branch_ips = [
            row["observed_ip"]
            for row in database().execute(
                """
                SELECT DISTINCT observed_ip FROM devices
                WHERE branch_id = ? AND observed_ip IS NOT NULL
                """,
                (branch_id,),
            ).fetchall()
        ]
        database().execute(
            "UPDATE branches SET enabled = ? WHERE id = ?", (enabled, branch_id)
        )
        audit("branch.toggle", "branch", branch_id, {"enabled": bool(enabled)})
        database().commit()
        if not enabled:
            for source_ip in branch_ips:
                delete_ipset_member_if_unused(source_ip)
        flash("อัปเดตสถานะสาขาแล้ว", "success")
        return redirect(url_for("dashboard"))

    @app.post("/admin/branches/<int:branch_id>/devices")
    @login_required
    def create_device(branch_id):
        require_csrf()
        branch = database().execute(
            "SELECT * FROM branches WHERE id = ?", (branch_id,)
        ).fetchone()
        if not branch:
            abort(404)
        code = request.form.get("code", "").strip().lower()
        if not DEVICE_CODE_RE.fullmatch(code):
            flash("รหัสอุปกรณ์ไม่ถูกต้อง", "error")
            return redirect(url_for("dashboard"))
        device_uid = secrets.token_urlsafe(18)
        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        try:
            cursor = database().execute(
                """
                INSERT INTO devices
                    (branch_id, code, device_uid, token_hash, enabled, created_at)
                VALUES (?, ?, ?, ?, 1, ?)
                """,
                (
                    branch_id,
                    code,
                    device_uid,
                    token_hash,
                    iso_utc(utc_now()),
                ),
            )
            audit(
                "device.create",
                "device",
                cursor.lastrowid,
                {"branch": branch["code"], "code": code},
            )
            database().commit()
        except sqlite3.IntegrityError:
            flash("รหัสอุปกรณ์นี้มีอยู่แล้วในสาขา", "error")
            return redirect(url_for("dashboard"))
        return render_template(
            "device_secret.html",
            branch=branch,
            device_code=code,
            device_uid=device_uid,
            token=token,
        )

    @app.post("/admin/devices/<int:device_id>/rotate")
    @login_required
    def rotate_device(device_id):
        require_csrf()
        device = database().execute(
            """
            SELECT d.*, b.code AS branch_code, b.name AS branch_name
            FROM devices d JOIN branches b ON b.id = d.branch_id
            WHERE d.id = ?
            """,
            (device_id,),
        ).fetchone()
        if not device:
            abort(404)
        token = secrets.token_urlsafe(32)
        token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        database().execute(
            "UPDATE devices SET token_hash = ? WHERE id = ?",
            (token_hash, device_id),
        )
        audit("device.rotate", "device", device_id, {"code": device["code"]})
        database().commit()
        return render_template(
            "device_secret.html",
            branch={"code": device["branch_code"], "name": device["branch_name"]},
            device_code=device["code"],
            device_uid=device["device_uid"],
            token=token,
        )

    @app.post("/admin/devices/<int:device_id>/rename")
    @login_required
    def rename_device(device_id):
        require_csrf()
        device = database().execute(
            "SELECT * FROM devices WHERE id = ?", (device_id,)
        ).fetchone()
        if not device:
            abort(404)

        new_code = request.form.get("code", "").strip().lower()
        if not DEVICE_CODE_RE.fullmatch(new_code):
            flash("ชื่ออุปกรณ์ไม่ถูกต้อง", "error")
            return redirect(url_for("dashboard"))
        if new_code == device["code"]:
            flash("ชื่ออุปกรณ์ไม่มีการเปลี่ยนแปลง", "success")
            return redirect(url_for("dashboard"))

        try:
            database().execute(
                "UPDATE devices SET code = ? WHERE id = ?",
                (new_code, device_id),
            )
            audit(
                "device.rename",
                "device",
                device_id,
                {"oldCode": device["code"], "newCode": new_code},
            )
            database().commit()
        except sqlite3.IntegrityError:
            database().rollback()
            flash("ชื่ออุปกรณ์นี้มีอยู่แล้วในสาขา", "error")
            return redirect(url_for("dashboard"))

        flash("แก้ไขชื่ออุปกรณ์แล้ว", "success")
        return redirect(url_for("dashboard"))

    @app.post("/admin/devices/<int:device_id>/toggle")
    @login_required
    def toggle_device(device_id):
        require_csrf()
        device = database().execute(
            "SELECT * FROM devices WHERE id = ?", (device_id,)
        ).fetchone()
        if not device:
            abort(404)
        enabled = 0 if device["enabled"] else 1
        database().execute(
            "UPDATE devices SET enabled = ? WHERE id = ?", (enabled, device_id)
        )
        audit("device.toggle", "device", device_id, {"enabled": bool(enabled)})
        database().commit()
        if not enabled:
            delete_ipset_member_if_unused(device["observed_ip"], device_id)
        flash("อัปเดตสถานะอุปกรณ์แล้ว", "success")
        return redirect(url_for("dashboard"))

    def observed_ipv4():
        peer = request.remote_addr or ""
        candidate = peer
        if peer == app.config["TRUSTED_PROXY"]:
            candidate = request.headers.get("X-Real-IP", "")
        try:
            address = ipaddress.ip_address(candidate)
        except ValueError:
            abort(400, "Invalid source IP")
        if address.version != 4:
            abort(400, "IPv4 is required")
        return str(address)

    @app.post("/api/v1/heartbeat")
    def heartbeat():
        initialize_database()
        device_uid = request.headers.get("X-Device-ID", "").strip()
        authorization = request.headers.get("Authorization", "")
        if not authorization.startswith("Bearer "):
            return jsonify(error="unauthorized"), 401
        token = authorization[7:].strip()
        if not device_uid or not token:
            return jsonify(error="unauthorized"), 401
        device = database().execute(
            """
            SELECT d.*, b.enabled AS branch_enabled, b.code AS branch_code
            FROM devices d JOIN branches b ON b.id = d.branch_id
            WHERE d.device_uid = ?
            """,
            (device_uid,),
        ).fetchone()
        supplied_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
        if (
            not device
            or not hmac.compare_digest(device["token_hash"], supplied_hash)
            or not device["enabled"]
            or not device["branch_enabled"]
        ):
            return jsonify(error="unauthorized"), 401

        source_ip = observed_ipv4()
        lease_seconds = app.config["LEASE_SECONDS"]
        expires = utc_now() + timedelta(seconds=lease_seconds)
        try:
            update_ipset_member(
                source_ip,
                expires,
                f"{device['branch_code']}-{device['code']}",
            )
        except (subprocess.SubprocessError, OSError):
            app.logger.exception("Unable to update ipset")
            return jsonify(error="firewall_update_failed"), 503

        previous_ip = device["observed_ip"]
        database().execute(
            """
            UPDATE devices
            SET observed_ip = ?, last_seen = ?, expires_at = ?
            WHERE id = ?
            """,
            (
                source_ip,
                iso_utc(utc_now()),
                iso_utc(expires),
                device["id"],
            ),
        )
        if previous_ip != source_ip:
            audit(
                "device.ip_changed",
                "device",
                device["id"],
                {"oldIp": previous_ip, "newIp": source_ip},
            )
        database().commit()
        return jsonify(
            status="ok",
            branch=device["branch_code"],
            device=device["code"],
            observedIp=source_ip,
            allowedUntil=iso_utc(expires),
        )

    return app
