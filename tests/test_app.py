import os
import tempfile
import unittest
from unittest.mock import patch

from heartbeat_app import create_app, format_bangkok_time


class HeartbeatAppTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.database = os.path.join(self.tempdir.name, "test.db")
        self.app = create_app(
            {
                "TESTING": True,
                "SECRET_KEY": "test-secret",
                "DATABASE": self.database,
                "SESSION_COOKIE_SECURE": False,
                "TRUSTED_PROXY": "127.0.0.1",
            }
        )
        self.client = self.app.test_client()
        runner = self.app.test_cli_runner()
        result = runner.invoke(args=["init-db"])
        self.assertEqual(result.exit_code, 0, result.output)

    def tearDown(self):
        self.tempdir.cleanup()

    def test_health(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json["status"], "ok")

    def test_formats_utc_time_as_bangkok_time(self):
        self.assertEqual(
            format_bangkok_time("2026-07-24T18:30:00+00:00"),
            "25/07/2026 01:30:00",
        )
        self.assertEqual(format_bangkok_time(None), "—")

    def test_create_admin_from_password_file(self):
        password_file = os.path.join(self.tempdir.name, "admin-password")
        with open(password_file, "w", encoding="utf-8") as handle:
            handle.write("A-secure-test-password-2026")
        runner = self.app.test_cli_runner()
        result = runner.invoke(
            args=[
                "create-admin",
                "--username",
                "admin",
                "--password-file",
                password_file,
            ]
        )
        self.assertEqual(result.exit_code, 0, result.output)

    def test_heartbeat_requires_token(self):
        response = self.client.post("/api/v1/heartbeat")
        self.assertEqual(response.status_code, 401)

    def test_admin_can_create_branch_and_device(self):
        with self.client.session_transaction() as user_session:
            user_session["admin_id"] = 1
            user_session["admin_username"] = "admin"
            user_session["csrf_token"] = "test-csrf"

        response = self.client.post(
            "/admin/branches",
            data={
                "csrf_token": "test-csrf",
                "code": "branch-001",
                "name": "Test Branch",
            },
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("branch-001", response.get_data(as_text=True))

        import sqlite3

        conn = sqlite3.connect(self.database)
        branch_id = conn.execute("SELECT id FROM branches").fetchone()[0]
        conn.close()
        response = self.client.post(
            f"/admin/branches/{branch_id}/devices",
            data={"csrf_token": "test-csrf", "code": "pos-01"},
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("Device Key", response.get_data(as_text=True))

    def test_admin_can_rename_device_without_changing_identity(self):
        import sqlite3
        from datetime import datetime, timezone

        conn = sqlite3.connect(self.database)
        conn.execute(
            "INSERT INTO branches(code,name,enabled,created_at) VALUES(?,?,1,?)",
            ("branch-001", "Test", datetime.now(timezone.utc).isoformat()),
        )
        branch_id = conn.execute("SELECT id FROM branches").fetchone()[0]
        conn.execute(
            """
            INSERT INTO devices(
                branch_id,code,device_uid,token_hash,enabled,created_at
            ) VALUES(?,?,?,?,1,?)
            """,
            (
                branch_id,
                "pos-01",
                "stable-device-uid",
                "stable-token-hash",
                datetime.now(timezone.utc).isoformat(),
            ),
        )
        device_id = conn.execute("SELECT id FROM devices").fetchone()[0]
        conn.commit()
        conn.close()

        with self.client.session_transaction() as user_session:
            user_session["admin_id"] = 1
            user_session["admin_username"] = "admin"
            user_session["csrf_token"] = "test-csrf"

        response = self.client.post(
            f"/admin/devices/{device_id}/rename",
            data={"csrf_token": "test-csrf", "code": "front-counter"},
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn('value="front-counter"', response.get_data(as_text=True))

        conn = sqlite3.connect(self.database)
        device = conn.execute(
            "SELECT code, device_uid, token_hash FROM devices WHERE id = ?",
            (device_id,),
        ).fetchone()
        rename_log = conn.execute(
            """
            SELECT details FROM audit_logs
            WHERE action = 'device.rename' AND target_id = ?
            """,
            (device_id,),
        ).fetchone()
        conn.close()
        self.assertEqual(
            device,
            ("front-counter", "stable-device-uid", "stable-token-hash"),
        )
        self.assertIn('"oldCode": "pos-01"', rename_log[0])
        self.assertIn('"newCode": "front-counter"', rename_log[0])

    def test_renaming_device_rejects_duplicate_name_in_branch(self):
        import sqlite3
        from datetime import datetime, timezone

        now = datetime.now(timezone.utc).isoformat()
        conn = sqlite3.connect(self.database)
        conn.execute(
            "INSERT INTO branches(code,name,enabled,created_at) VALUES(?,?,1,?)",
            ("branch-001", "Test", now),
        )
        branch_id = conn.execute("SELECT id FROM branches").fetchone()[0]
        for code, uid in (("pos-01", "device-1"), ("pos-02", "device-2")):
            conn.execute(
                """
                INSERT INTO devices(
                    branch_id,code,device_uid,token_hash,enabled,created_at
                ) VALUES(?,?,?,?,1,?)
                """,
                (branch_id, code, uid, f"hash-{uid}", now),
            )
        device_id = conn.execute(
            "SELECT id FROM devices WHERE code = 'pos-02'"
        ).fetchone()[0]
        conn.commit()
        conn.close()

        with self.client.session_transaction() as user_session:
            user_session["admin_id"] = 1
            user_session["admin_username"] = "admin"
            user_session["csrf_token"] = "test-csrf"

        response = self.client.post(
            f"/admin/devices/{device_id}/rename",
            data={"csrf_token": "test-csrf", "code": "pos-01"},
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)

        conn = sqlite3.connect(self.database)
        code = conn.execute(
            "SELECT code FROM devices WHERE id = ?", (device_id,)
        ).fetchone()[0]
        log_count = conn.execute(
            """
            SELECT COUNT(*) FROM audit_logs
            WHERE action = 'device.rename' AND target_id = ?
            """,
            (device_id,),
        ).fetchone()[0]
        conn.close()
        self.assertEqual(code, "pos-02")
        self.assertEqual(log_count, 0)

    def test_dashboard_shows_online_and_offline_device_status(self):
        import sqlite3
        from datetime import datetime, timedelta, timezone

        now = datetime.now(timezone.utc)
        conn = sqlite3.connect(self.database)
        conn.execute(
            "INSERT INTO branches(code,name,enabled,created_at) VALUES(?,?,1,?)",
            ("branch-001", "Test", now.isoformat()),
        )
        branch_id = conn.execute("SELECT id FROM branches").fetchone()[0]
        for code, device_uid, expires_at in (
            ("online-device", "online-device-uid", now + timedelta(minutes=5)),
            ("offline-device", "offline-device-uid", now - timedelta(minutes=5)),
        ):
            conn.execute(
                """
                INSERT INTO devices(
                    branch_id,code,device_uid,token_hash,enabled,
                    observed_ip,last_seen,expires_at,created_at
                ) VALUES(?,?,?,?,1,?,?,?,?)
                """,
                (
                    branch_id,
                    code,
                    device_uid,
                    "unused",
                    "203.0.113.7",
                    now.isoformat(),
                    expires_at.isoformat(),
                    now.isoformat(),
                ),
            )
        conn.commit()
        conn.close()
        with self.client.session_transaction() as user_session:
            user_session["admin_id"] = 1
            user_session["admin_username"] = "admin"

        response = self.client.get("/admin")
        page = response.get_data(as_text=True)
        self.assertEqual(response.status_code, 200)
        self.assertIn('data-status="online"', page)
        self.assertIn('data-status="offline"', page)
        self.assertIn("ออนไลน์", page)
        self.assertIn("ออฟไลน์", page)
        self.assertIn(format_bangkok_time(now.isoformat()), page)
        self.assertNotIn(now.isoformat(), page)

    @patch("heartbeat_app.subprocess.run")
    def test_revoking_device_removes_unshared_ip(self, run):
        import sqlite3
        from datetime import datetime, timedelta, timezone

        now = datetime.now(timezone.utc)
        conn = sqlite3.connect(self.database)
        conn.execute(
            "INSERT INTO branches(code,name,enabled,created_at) VALUES(?,?,1,?)",
            ("branch-001", "Test", now.isoformat()),
        )
        branch_id = conn.execute("SELECT id FROM branches").fetchone()[0]
        conn.execute(
            """
            INSERT INTO devices(
                branch_id,code,device_uid,token_hash,enabled,
                observed_ip,last_seen,expires_at,created_at
            ) VALUES(?,?,?,?,1,?,?,?,?)
            """,
            (
                branch_id,
                "pos-01",
                "device-uid",
                "unused",
                "203.0.113.7",
                now.isoformat(),
                (now + timedelta(minutes=5)).isoformat(),
                now.isoformat(),
            ),
        )
        device_id = conn.execute("SELECT id FROM devices").fetchone()[0]
        conn.commit()
        conn.close()
        with self.client.session_transaction() as user_session:
            user_session["admin_id"] = 1
            user_session["admin_username"] = "admin"
            user_session["csrf_token"] = "test-csrf"

        response = self.client.post(
            f"/admin/devices/{device_id}/toggle",
            data={"csrf_token": "test-csrf"},
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)
        command = run.call_args.args[0]
        self.assertEqual(command[2], "del")
        self.assertIn("203.0.113.7", command)

    @patch("heartbeat_app.subprocess.run")
    def test_heartbeat_updates_ipset(self, run):
        import hashlib
        import sqlite3
        from datetime import datetime, timezone

        token = "unit-test-token"
        conn = sqlite3.connect(self.database)
        conn.execute(
            "INSERT INTO branches(code,name,enabled,created_at) VALUES(?,?,1,?)",
            ("branch-001", "Test", datetime.now(timezone.utc).isoformat()),
        )
        branch_id = conn.execute("SELECT id FROM branches").fetchone()[0]
        conn.execute(
            """
            INSERT INTO devices(branch_id,code,device_uid,token_hash,enabled,created_at)
            VALUES(?,?,?,?,1,?)
            """,
            (
                branch_id,
                "pos-01",
                "device-uid",
                hashlib.sha256(token.encode()).hexdigest(),
                datetime.now(timezone.utc).isoformat(),
            ),
        )
        conn.commit()
        conn.close()

        response = self.client.post(
            "/api/v1/heartbeat",
            headers={
                "Authorization": f"Bearer {token}",
                "X-Device-ID": "device-uid",
                "X-Real-IP": "203.0.113.7",
            },
            environ_base={"REMOTE_ADDR": "127.0.0.1"},
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertEqual(response.json["observedIp"], "203.0.113.7")
        command = run.call_args.args[0]
        self.assertEqual(command[0], "/usr/sbin/ipset")
        self.assertIn("203.0.113.7", command)

        response = self.client.post(
            "/api/v1/heartbeat",
            headers={
                "Authorization": f"Bearer {token}",
                "X-Device-ID": "device-uid",
                "X-Real-IP": "203.0.113.7",
            },
            environ_base={"REMOTE_ADDR": "127.0.0.1"},
        )
        self.assertEqual(response.status_code, 200)
        import sqlite3

        conn = sqlite3.connect(self.database)
        log_count = conn.execute(
            "SELECT COUNT(*) FROM audit_logs WHERE action = 'device.ip_changed'"
        ).fetchone()[0]
        conn.close()
        self.assertEqual(log_count, 1)

    @patch("heartbeat_app.subprocess.run")
    def test_admin_can_add_and_revoke_temporary_ip_allowance(self, run):
        import sqlite3

        with self.client.session_transaction() as user_session:
            user_session["admin_id"] = 1
            user_session["admin_username"] = "admin"
            user_session["csrf_token"] = "test-csrf"

        response = self.client.post(
            "/admin/emergency-ip-allowances",
            data={
                "csrf_token": "test-csrf",
                "ip_address": "8.8.8.8",
                "duration_minutes": "60",
                "note": "Emergency support",
            },
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("8.8.8.8", response.get_data(as_text=True))
        add_command = run.call_args.args[0]
        self.assertEqual(add_command[2], "add")
        self.assertIn("8.8.8.8", add_command)
        self.assertIn("timeout", add_command)

        conn = sqlite3.connect(self.database)
        allowance = conn.execute(
            """
            SELECT id, note, revoked_at
            FROM emergency_ip_allowances
            WHERE ip_address = ?
            """,
            ("8.8.8.8",),
        ).fetchone()
        create_log_count = conn.execute(
            """
            SELECT COUNT(*) FROM audit_logs
            WHERE action = 'emergency_ip.create'
            """
        ).fetchone()[0]
        conn.close()
        self.assertEqual(allowance[1], "Emergency support")
        self.assertIsNone(allowance[2])
        self.assertEqual(create_log_count, 1)

        run.reset_mock()
        response = self.client.post(
            f"/admin/emergency-ip-allowances/{allowance[0]}/revoke",
            data={"csrf_token": "test-csrf"},
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)
        delete_command = run.call_args.args[0]
        self.assertEqual(delete_command[2], "del")
        self.assertIn("8.8.8.8", delete_command)

        conn = sqlite3.connect(self.database)
        revoked_at = conn.execute(
            "SELECT revoked_at FROM emergency_ip_allowances WHERE id = ?",
            (allowance[0],),
        ).fetchone()[0]
        revoke_log_count = conn.execute(
            """
            SELECT COUNT(*) FROM audit_logs
            WHERE action = 'emergency_ip.revoke'
            """
        ).fetchone()[0]
        conn.close()
        self.assertIsNotNone(revoked_at)
        self.assertEqual(revoke_log_count, 1)

    @patch("heartbeat_app.subprocess.run")
    def test_temporary_ip_allowance_rejects_invalid_duration(self, run):
        with self.client.session_transaction() as user_session:
            user_session["admin_id"] = 1
            user_session["admin_username"] = "admin"
            user_session["csrf_token"] = "test-csrf"

        response = self.client.post(
            "/admin/emergency-ip-allowances",
            data={
                "csrf_token": "test-csrf",
                "ip_address": "8.8.8.8",
                "duration_minutes": "1441",
            },
            follow_redirects=True,
        )
        self.assertEqual(response.status_code, 200)
        run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
