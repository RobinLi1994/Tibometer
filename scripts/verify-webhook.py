#!/usr/bin/env python3
"""Exercise URLSession with synthetic payloads and a loopback HTTP receiver."""
import base64
import hashlib
import hmac
import http.server
import json
import os
from pathlib import Path
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[1]
subprocess.run(["swift", "build", "--product", "tibometer-probe"], cwd=ROOT, check=True)
bin_dir = subprocess.check_output(["swift", "build", "--show-bin-path"], cwd=ROOT, text=True).strip()
requests = []


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        requests.append((self.path, dict(self.headers), raw))
        if self.path == "/redirect":
            self.send_response(307)
            self.send_header("Location", "/must-not-receive")
            self.end_headers()
            return
        status = {"/unauthorized": 401, "/unavailable": 503}.get(self.path, 200)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"code": 999 if self.path == "/bot-rejected" else 0, "errcode": 0}).encode())

    def log_message(self, *_):
        pass


server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
environment = os.environ.copy()
environment["TIBOMETER_WEBHOOK_SECRET"] = "fixture-secret"
environment["TIBOMETER_WEBHOOK_TOKEN"] = "fixture-token"


def send(path, fmt="json", success=True):
    result = subprocess.run(
        [str(Path(bin_dir) / "tibometer-probe"), "--webhook-test", f"http://127.0.0.1:{server.server_port}{path}", "--format", fmt],
        env=environment, text=True, capture_output=True, timeout=25,
    )
    assert (result.returncode == 0) == success, (path, result.stdout, result.stderr)
    assert "fixture-secret" not in result.stdout + result.stderr
    assert "fixture-token" not in result.stdout + result.stderr
    return requests[-1]


try:
    for fmt in ["json", "slack", "discord", "feishu", "wecom"]:
        path, headers, raw = send("/" + fmt, fmt)
        body = json.loads(raw)
        lower_headers = {k.lower(): v for k, v in headers.items()}
        assert lower_headers["authorization"] == "Bearer fixture-token"
        assert lower_headers["idempotency-key"] == lower_headers["x-tibometer-event-id"]
        if fmt == "json":
            timestamp = lower_headers["x-tibometer-timestamp"]
            expected = hmac.new(b"fixture-secret", timestamp.encode() + b"." + raw, hashlib.sha256).hexdigest()
            assert lower_headers["x-tibometer-signature"] == "sha256=" + expected
            assert body["event"] == "codex.webhook.test"
            assert "account_id" not in body
        if fmt == "feishu":
            expected = base64.b64encode(hmac.new((body["timestamp"] + "\nfixture-secret").encode(), b"", hashlib.sha256).digest()).decode()
            assert body["sign"] == expected
        print("PASS loopback delivery:", fmt)
    send("/unauthorized", success=False)
    send("/unavailable", success=False)
    send("/bot-rejected", fmt="feishu", success=False)
    before = len(requests)
    send("/redirect", success=False)
    assert len(requests) == before + 1
    assert not any(path == "/must-not-receive" for path, _, _ in requests)
    print("PASS HTTP errors, bot rejection, and redirect refusal")
    print("9 loopback HTTP scenarios passed")
finally:
    server.shutdown()
    server.server_close()
