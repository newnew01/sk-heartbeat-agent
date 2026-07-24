import os
import sqlite3
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

from heartbeat_app import create_app


preview_dir = Path(tempfile.gettempdir()) / "branch-heartbeat-preview"
preview_dir.mkdir(parents=True, exist_ok=True)
database_path = preview_dir / "preview.db"
if database_path.exists():
    database_path.unlink()

app = create_app(
    {
        "TESTING": True,
        "SECRET_KEY": "preview-secret",
        "DATABASE": str(database_path),
        "SESSION_COOKIE_SECURE": False,
    }
)
client = app.test_client()
client.get("/login")

now = datetime.now(timezone.utc)
conn = sqlite3.connect(database_path)
conn.execute(
    "INSERT INTO admins(username,password_hash,created_at) VALUES(?,?,?)",
    ("admin", "unused", now.isoformat()),
)
conn.execute(
    "INSERT INTO branches(code,name,enabled,created_at) VALUES(?,?,1,?)",
    ("branch-001", "สาขาสีลม", now.isoformat()),
)
branch_id = conn.execute("SELECT id FROM branches").fetchone()[0]
conn.execute(
    """
    INSERT INTO devices(
        branch_id, code, device_uid, token_hash, enabled,
        observed_ip, last_seen, expires_at, created_at
    ) VALUES(?,?,?,?,1,?,?,?,?)
    """,
    (
        branch_id,
        "pos-01",
        "wG4m9qV4ExampleDevice",
        "unused",
        "203.0.113.24",
        now.isoformat(timespec="seconds"),
        (now + timedelta(minutes=8)).isoformat(timespec="seconds"),
        now.isoformat(),
    ),
)
conn.commit()
conn.close()

with client.session_transaction() as user_session:
    user_session["admin_id"] = 1
    user_session["admin_username"] = "admin"
    user_session["csrf_token"] = "preview-csrf"

html = client.get("/admin").get_data(as_text=True)
css_uri = (Path(__file__).parents[1] / "heartbeat_app" / "static" / "app.css").as_uri()
html = html.replace("/static/app.css", css_uri)
(preview_dir / "dashboard.html").write_text(html, encoding="utf-8")
print((preview_dir / "dashboard.html").as_uri())
