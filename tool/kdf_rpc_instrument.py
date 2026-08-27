#!/usr/bin/env python3
"""Stand the instrument up on its own, for the browser arm.

The native benchmark drives KDF directly, so it can start the instrument in
process. The browser arm cannot: the page has to be pointed at a URL that
already exists. This runs the same Instrument on a fixed port, mocking the
GLEEC chain, so `web/bench_serve.py --rewrite-nodes` can aim the app at it.

Mode `cors-strip` is the one that matters: it answers a rate-limited request
with 429 and *no* `Access-Control-Allow-Origin`, and refuses the OPTIONS
preflight the same way - which is what Cloudflare's edge does in front of
evm-rpc.gleec.com, and what turns a readable 429 into an opaque browser error.
"""
import argparse
import importlib.util
import json
import os
import signal
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "bench", os.path.join(HERE, "kdf_rpc_burst_bench.py")
)
bench = importlib.util.module_from_spec(spec)
sys.modules["bench"] = bench
spec.loader.exec_module(bench)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8850)
    parser.add_argument("--mode", default="unlimited",
                        choices=["unlimited", "limited", "cors-strip"])
    parser.add_argument("--rate", type=float, default=20.0)
    parser.add_argument("--latency-ms", type=float, default=0.0)
    parser.add_argument("--chain-id", type=int, default=11169)
    parser.add_argument("--dump", default=None)
    args = parser.parse_args()

    upstreams = bench.Upstreams()
    instrument = bench.Instrument(
        mode=args.mode,
        upstreams=upstreams,
        rate=(None if args.mode == "unlimited" else args.rate),
        burst=int(args.rate),
        chain_id=args.chain_id,
        latency_s=args.latency_ms / 1000.0,
    )
    # Fixed port instead of the ephemeral one Instrument.start() picks.
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *_a):
            pass

        def do_OPTIONS(self):  # noqa: N802
            allowed = instrument._preflight_allowed()
            with instrument.events_lock:
                instrument.events.append(bench.Event(
                    t_start=time.monotonic() - instrument.t0,
                    t_end=time.monotonic() - instrument.t0,
                    slot="preflight", upstream="OPTIONS",
                    methods=["<preflight>"], addresses=[],
                    status=204 if allowed else 429, batch_size=1, body_bytes=0,
                ))
            self.send_response(204 if allowed else 429)
            if allowed or instrument.mode != "cors-strip":
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Access-Control-Allow-Headers", "*")
                self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
            self.send_header("Content-Length", "0")
            self.end_headers()

        def do_POST(self):  # noqa: N802
            instrument._handle(self)

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    instrument.server = server
    instrument.port = args.port

    def report(*_a):
        metrics = instrument.metrics()
        text = json.dumps(metrics, indent=1)
        if args.dump:
            with open(args.dump, "w") as handle:
                handle.write(text)
        print(text[:4000], flush=True)

    signal.signal(signal.SIGUSR1, lambda *a: report())
    print(f"[instrument] mode={args.mode} rate={args.rate}/s on "
          f"http://127.0.0.1:{args.port}  (SIGUSR1 to dump)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    report()


if __name__ == "__main__":
    main()
