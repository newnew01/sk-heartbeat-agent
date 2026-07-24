import os
import tempfile
import unittest
from unittest.mock import patch

from heartbeat_app import create_app


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


if __name__ == "__main__":
    unittest.main()
