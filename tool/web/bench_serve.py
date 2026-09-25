#!/usr/bin/env python3
"""Serve a built Flutter web app with the request recorder injected.

Three deviations from plain static hosting, each deliberate:

* ``recorder.js`` is injected as the first script in ``<head>`` so it wraps
  ``fetch`` and ``XMLHttpRequest`` before any app or KDF code can capture a
  reference to the originals.
* The service worker is neutered. A registered worker would serve the app shell
  from its own cache, which is exactly how a previous investigation ended up
  measuring a build that was no longer deployed.
* Optionally rewrites the coins config so every EVM node points at a local
  instrument instead of the real endpoint. That turns the browser arm from an
  observation of production into a controlled experiment - same page, same
  KDF, a node whose rate limit and CORS behaviour we choose.
"""

from __future__ import annotations

import argparse
import http.server
import json
import os
import posixpath
import re
import socketserver
import sys
import threading
import urllib.parse

RECORDER = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "bench_recorder.js"
)
COINS_ASSET = "/assets/packages/komodo_defi_framework/assets/config/coins_config.json"


def build_handler(root: str, node_rewrite: str | None, chains: set[str] | None):
    with open(RECORDER, "rb") as handle:
        recorder_body = handle.read()

    class Handler(http.server.SimpleHTTPRequestHandler):
        # `SimpleHTTPRequestHandler` guesses types from the system mime table,
        # which on macOS has no `.wasm` entry. Serving the 33MB KDF module as
        # `application/octet-stream` makes `WebAssembly.instantiateStreaming`
        # reject and fall back to buffering the whole thing - a materially
        # slower startup than Firebase serves, so the arm would be measuring
        # the server rather than the app.
        extensions_map = {
            **http.server.SimpleHTTPRequestHandler.extensions_map,
            ".wasm": "application/wasm",
        }

        def __init__(self, *a, **kw):
            super().__init__(*a, directory=root, **kw)

        def log_message(self, *a):  # quiet
            pass

        def end_headers(self):
            self.send_header("Cache-Control", "no-store, max-age=0")
            super().end_headers()

        def _send(self, body: bytes, ctype: str, status: int = 200):
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):  # noqa: N802
            path = urllib.parse.urlparse(self.path).path

            if path == "/__bench/recorder.js":
                return self._send(recorder_body, "application/javascript")

            if path == "/flutter_service_worker.js":
                # A no-op worker that unregisters itself, so a previously
                # installed one cannot keep serving an older build.
                body = (
                    b"self.addEventListener('install',e=>self.skipWaiting());\n"
                    b"self.addEventListener('activate',e=>{self.registration.unregister();});\n"
                )
                return self._send(body, "application/javascript")

            if path in ("/", "/index.html"):
                with open(os.path.join(root, "index.html"), "rb") as handle:
                    html = handle.read().decode("utf-8")
                if "__bench/recorder.js" not in html:
                    html = re.sub(
                        r"(<head[^>]*>)",
                        r'\1\n  <script src="/__bench/recorder.js"></script>',
                        html,
                        count=1,
                    )
                return self._send(html.encode("utf-8"), "text/html; charset=utf-8")

            if path == COINS_ASSET and node_rewrite:
                with open(os.path.join(root, path.lstrip("/")), "rb") as handle:
                    coins = json.loads(handle.read())
                rewritten = 0
                for ticker, coin in coins.items():
                    if chains and ticker not in chains:
                        continue
                    nodes = coin.get("nodes")
                    if not isinstance(nodes, list):
                        continue
                    for node in nodes:
                        if "url" in node:
                            node["url"] = node_rewrite
                            node.pop("ws_url", None)
                            rewritten += 1
                body = json.dumps(coins).encode()
                print(f"[serve] rewrote {rewritten} EVM node urls -> {node_rewrite}",
                      file=sys.stderr)
                return self._send(body, "application/json")

            return super().do_GET()

    return Handler


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--rewrite-nodes", default=None,
                        help="replace every EVM node url with this one")
    parser.add_argument("--chains", default=None,
                        help="comma-separated tickers to rewrite; default all")
    args = parser.parse_args()

    chains = set(args.chains.split(",")) if args.chains else None
    handler = build_handler(args.root, args.rewrite_nodes, chains)

    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True

    with Server(("127.0.0.1", args.port), handler) as server:
        print(f"[serve] {args.root} on http://127.0.0.1:{args.port}", file=sys.stderr,
              flush=True)
        server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
