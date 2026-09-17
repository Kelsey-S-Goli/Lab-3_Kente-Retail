#!/usr/bin/env python3
"""Stand-in for the internal upstream service: answers /ping with 200.
Runs on the same server, port 9090. The app reaches it by hostname."""
from http.server import BaseHTTPRequestHandler, HTTPServer

class Ping(BaseHTTPRequestHandler):
    def do_GET(self):
        code = 200 if self.path == "/ping" else 404
        self.send_response(code); self.end_headers()
        self.wfile.write(b"pong\n" if code == 200 else b"")
    def log_message(self, *a):
        pass

HTTPServer(("127.0.0.1", 9090), Ping).serve_forever()
