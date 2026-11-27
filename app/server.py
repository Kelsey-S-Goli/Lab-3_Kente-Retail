#!/usr/bin/env python3
"""Tiny web app for the business storefront. Standard library only.

GET /        -> storefront page listing items from DATA_DIR/catalog.json
GET /health  -> 200 if the upstream service answers, 503 if it does not
Every request is written to LOG_DIR/access.log, one line per request.
"""
import json, os, sys, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONF_FILE = os.environ.get("APP_CONF", os.path.join(os.path.dirname(__file__), "..", "config", "app.conf"))

def load_conf(path):
    conf = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                conf[key.strip()] = value.strip()
    return conf

CONF = load_conf(CONF_FILE)
LOG_PATH = os.path.join(CONF["LOG_DIR"], "access.log")

def upstream_ok():
    try:
        with urllib.request.urlopen(CONF["UPSTREAM_URL"], timeout=2) as resp:
            return resp.status == 200, "ok"
    except Exception as exc:  # name not resolving, timeout, refused...
        # The note must be ONE log field (policy 6.1): replace every space,
        # including the one after the colon (was splitting lines into 9 fields).
        return False, (type(exc).__name__ + ": " + str(exc)).replace(" ", "_")[:80]
        
class Handler(BaseHTTPRequestHandler):
    def _send(self, status, body, ctype="text/plain"):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        return status

    def do_GET(self):
        start = time.time()
        note = "-"
        if self.path == "/health":
            ok, note = upstream_ok()
            status = self._send(200 if ok else 503, "ok\n" if ok else "upstream unreachable\n")
        elif self.path == "/":
            try:
                with open(os.path.join(CONF["DATA_DIR"], "catalog.json")) as fh:
                    items = json.load(fh)
                rows = "".join(f"<li>{i['name']}</li>" for i in items)
                status = self._send(200, f"<h1>{CONF['BUSINESS']}</h1><ul>{rows}</ul>", "text/html")
            except Exception as exc:
                note = type(exc).__name__
                status = self._send(500, "internal error\n")
        else:
            status = self._send(404, "not found\n")
        ms = int((time.time() - start) * 1000)
        # Log format: date time client method path status ms note
        with open(LOG_PATH, "a") as log:
            log.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {self.client_address[0]} "
                      f"GET {self.path} {status} {ms}ms {note}\n")

    def log_message(self, *args):  # silence the default stderr logging
        pass

if __name__ == "__main__":
    port = int(CONF.get("PORT", "8080"))
    print(f"listening on :{port}", file=sys.stderr)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
