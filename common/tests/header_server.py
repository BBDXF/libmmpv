#!/usr/bin/env python3
"""Static file server on 127.0.0.1 that logs every request's headers as JSON lines.
usage: header_server.py DIR PORT LOGFILE"""
import http.server, json, os, sys, functools

root, port, logf = sys.argv[1], int(sys.argv[2]), sys.argv[3]
log = open(logf, "a", buffering=1)

class H(http.server.SimpleHTTPRequestHandler):
    def _rec(self):
        log.write(json.dumps({"method": self.command, "path": self.path,
                              "headers": {k: v for k, v in self.headers.items()}}) + "\n")
    def do_GET(self):  self._rec(); super().do_GET()
    def do_HEAD(self): self._rec(); super().do_HEAD()
    def log_message(self, *a): pass

http.server.ThreadingHTTPServer(("127.0.0.1", port),
    functools.partial(H, directory=root)).serve_forever()
