#!/usr/bin/env python3
"""Does every ``ws_url`` in the coins config actually answer JSON-RPC?

Why this exists
---------------
The SDK sends each EVM node's ``ws_url`` to KDF as a second node entry alongside
its ``https://`` one. A dead ws entry is not free: KDF's ``try_every_node``
allots ``TRY_RPC_NODE_TIMEOUT_S`` = 10s per node, and the websocket path has no
fast fail — ``send_request`` parks on an unbounded channel while
``attempt_to_establish_socket_connection`` burns three attempts at 1/2/4s and
then simply returns, leaving the caller to time out. So a ws node that never
answers costs a real activation ten seconds and buys nothing.

This opens each endpoint the way KDF's transport does — a real WebSocket, TLS,
one JSON-RPC frame — and records whether an answer came back and how quickly.

Every endpoint is probed twice, and the pair is the point
---------------------------------------------------------
Once sending an ``Origin`` header and once not, because that one header decides
the verdict and the two platforms differ on it:

* **native** — KDF uses ``tokio_tungstenite``, which sends no ``Origin``.
* **web** — KDF uses ``tokio_tungstenite_wasm``, i.e. the browser's own
  ``WebSocket``. The browser stamps the page's ``Origin`` on every handshake and
  Rust cannot suppress it.

Measured 2026-08-07: ``wss://rpc.energyweb.org/ws`` answers 101 with no
``Origin`` and **403 with any ``Origin`` at all**. It is a working native
endpoint and an unusable web one. A single-setting probe calls that "dead" and
permanently strips a chain of a node that works — hence both.

**Python 3 standard library only.** No ``websockets``, no ``pip install``. The
handshake and framing are implemented here (RFC 6455) precisely so this runs
unchanged on a CI box, a fresh clone, or someone else's laptop a year from now.
Same discipline as ``tool/kdf_latency_probe.py``.

Usage
-----
::

    python3 tool/evm_ws_probe.py                        # probe every ws_url, print the table
    python3 tool/evm_ws_probe.py --json out.json        # and archive the raw result
    python3 tool/evm_ws_probe.py --repeat 3             # best-of-N per setting
    python3 tool/evm_ws_probe.py --only GLEEC,ETH       # a subset, by platform ticker
    python3 tool/evm_ws_probe.py --url wss://host/path  # ad-hoc, no config read
    python3 tool/evm_ws_probe.py --baseline docs/assets/evm_ws_probe/evm_ws_probe_2026-08-07.json

Exit codes
----------
Without ``--baseline``: 0 if every endpoint answered on at least one setting, 1
otherwise. With ``--baseline``: 0 unless an endpoint **regressed** against the
committed result — which is what makes this re-runnable as a gate once the
permanently-dead endpoints are known and dropped.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import socket
import ssl
import struct
import sys
import time
from dataclasses import asdict, dataclass, field
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urlparse

REPO_ROOT = os.environ.get(
    "WALLET_REPO",
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
)
COINS_CONFIG = os.path.join(
    REPO_ROOT,
    "sdk",
    "packages",
    "komodo_defi_framework",
    "assets",
    "config",
    "coins_config.json",
)

# The probe payload. ``net_version`` is what KDF's own websocket keepalive sends
# (mm2src/coins/eth/web3_transport/websocket_transport.rs), so an endpoint that
# answers this answers the thing KDF will actually ask it every 10s.
PROBE_REQUEST = {"jsonrpc": "2.0", "method": "net_version", "params": [], "id": 0}

DEFAULT_ORIGIN = "https://app.gleec.com"

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

OP_CONT = 0x0
OP_TEXT = 0x1
OP_BINARY = 0x2
OP_CLOSE = 0x8
OP_PING = 0x9
OP_PONG = 0xA


# --------------------------------------------------------------------------
# A minimal RFC 6455 client. Enough to open a socket, send one frame and read
# one answer. Deliberately not a general-purpose library.
# --------------------------------------------------------------------------


class WsError(Exception):
    """Any failure that means "this endpoint did not answer"."""


class _PrefixedSocket:
    """A socket with bytes pushed back in front of it.

    The HTTP upgrade read is greedy and can swallow the first websocket frame.
    Without this, an endpoint that answers immediately looks like one that never
    answers — which is exactly backwards.
    """

    def __init__(self, sock: Any, prefix: bytes) -> None:
        self._sock = sock
        self._prefix = bytearray(prefix)

    def recv(self, count: int) -> bytes:
        if self._prefix:
            taken = bytes(self._prefix[:count])
            del self._prefix[: len(taken)]
            return taken
        return self._sock.recv(count)

    def sendall(self, data: bytes) -> None:
        self._sock.sendall(data)

    def close(self) -> None:
        self._sock.close()


def _recv_exactly(sock: Any, count: int) -> bytes:
    buf = bytearray()
    while len(buf) < count:
        chunk = sock.recv(count - len(buf))
        if not chunk:
            raise WsError(f"connection closed after {len(buf)}/{count} bytes")
        buf.extend(chunk)
    return bytes(buf)


def _read_http_headers(sock: Any) -> bytes:
    """Read up to and including the blank line ending the status+header block."""
    buf = bytearray()
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            raise WsError("connection closed during the HTTP upgrade")
        buf.extend(chunk)
        if len(buf) > 65536:
            raise WsError("HTTP upgrade response exceeded 64KiB")
    return bytes(buf)


def _encode_frame(opcode: int, payload: bytes) -> bytes:
    """Client frames must be masked (RFC 6455 section 5.3)."""
    head = bytearray()
    head.append(0x80 | opcode)  # FIN + opcode
    length = len(payload)
    if length < 126:
        head.append(0x80 | length)
    elif length < (1 << 16):
        head.append(0x80 | 126)
        head.extend(struct.pack("!H", length))
    else:
        head.append(0x80 | 127)
        head.extend(struct.pack("!Q", length))
    mask = os.urandom(4)
    head.extend(mask)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return bytes(head) + masked


def _read_frame(sock: Any) -> Tuple[bool, int, bytes]:
    """Return (fin, opcode, payload) for one server frame. Servers do not mask."""
    b0, b1 = _recv_exactly(sock, 2)
    fin = bool(b0 & 0x80)
    opcode = b0 & 0x0F
    masked = bool(b1 & 0x80)
    length = b1 & 0x7F
    if length == 126:
        (length,) = struct.unpack("!H", _recv_exactly(sock, 2))
    elif length == 127:
        (length,) = struct.unpack("!Q", _recv_exactly(sock, 8))
    if length > (8 << 20):
        raise WsError(f"server frame of {length} bytes is implausible")
    mask = _recv_exactly(sock, 4) if masked else b""
    payload = _recv_exactly(sock, length) if length else b""
    if masked:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return fin, opcode, payload


@dataclass
class Attempt:
    """One handshake at one ``Origin`` setting."""

    origin: Optional[str]
    ok: bool = False
    error: Optional[str] = None
    http_status: Optional[int] = None
    connect_ms: Optional[float] = None
    tls_ms: Optional[float] = None
    upgrade_ms: Optional[float] = None
    rpc_ms: Optional[float] = None
    total_ms: Optional[float] = None
    net_version: Optional[str] = None
    server: Optional[str] = None
    tries: int = 0


@dataclass
class Endpoint:
    """One ``ws_url``, probed with and without ``Origin``."""

    url: str
    tickers: List[str] = field(default_factory=list)
    browser: Optional[Attempt] = None  # with Origin  -> what web gets
    native: Optional[Attempt] = None  # without Origin -> what native gets

    @property
    def browser_ok(self) -> bool:
        return bool(self.browser and self.browser.ok)

    @property
    def native_ok(self) -> bool:
        return bool(self.native and self.native.ok)

    @property
    def verdict(self) -> str:
        if self.browser_ok and self.native_ok:
            return "both"
        if self.native_ok:
            return "native-only"
        if self.browser_ok:
            return "web-only"
        return "dead"


def probe_once(url: str, origin: Optional[str], timeout: float = 10.0) -> Attempt:
    """Open [url], send one ``net_version``, and record what came back.

    Every failure mode is caught and recorded rather than raised: a probe that
    crashes on one dead host tells you nothing about the other twenty-three.
    """
    result = Attempt(origin=origin)
    parsed = urlparse(url)
    if parsed.scheme not in ("ws", "wss"):
        result.error = f"not a websocket scheme: {parsed.scheme!r}"
        return result

    host = parsed.hostname or ""
    port = parsed.port or (443 if parsed.scheme == "wss" else 80)
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"

    sock: Any = None
    started = time.monotonic()
    try:
        t0 = time.monotonic()
        sock = socket.create_connection((host, port), timeout=timeout)
        sock.settimeout(timeout)
        result.connect_ms = round((time.monotonic() - t0) * 1000, 1)

        if parsed.scheme == "wss":
            t0 = time.monotonic()
            context = ssl.create_default_context()
            sock = context.wrap_socket(sock, server_hostname=host)
            result.tls_ms = round((time.monotonic() - t0) * 1000, 1)

        key = base64.b64encode(os.urandom(16)).decode("ascii")
        # Host carries the port only when it is non-default, or some CDNs
        # (Cloudflare among them) answer 400 rather than upgrading.
        host_header = host if parsed.port in (None, 443, 80) else f"{host}:{port}"
        lines = [
            f"GET {path} HTTP/1.1",
            f"Host: {host_header}",
            "Upgrade: websocket",
            "Connection: Upgrade",
            f"Sec-WebSocket-Key: {key}",
            "Sec-WebSocket-Version: 13",
            "User-Agent: gleec-evm-ws-probe/1",
        ]
        if origin is not None:
            lines.append(f"Origin: {origin}")
        request = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii")

        t0 = time.monotonic()
        sock.sendall(request)
        raw = _read_http_headers(sock)
        result.upgrade_ms = round((time.monotonic() - t0) * 1000, 1)

        head, _, tail = raw.partition(b"\r\n\r\n")
        header_lines = head.decode("latin-1").split("\r\n")
        status_line = header_lines[0] if header_lines else ""
        parts = status_line.split(" ", 2)
        if len(parts) >= 2 and parts[1].isdigit():
            result.http_status = int(parts[1])
        headers = {}
        for line in header_lines[1:]:
            name, _, value = line.partition(":")
            headers[name.strip().lower()] = value.strip()
        result.server = headers.get("server")

        if result.http_status != 101:
            raise WsError(f"HTTP {result.http_status} rather than 101")

        expected = base64.b64encode(
            hashlib.sha1((key + WS_GUID).encode("ascii")).digest()
        ).decode("ascii")
        if headers.get("sec-websocket-accept") != expected:
            raise WsError("Sec-WebSocket-Accept did not match the key we sent")

        # Anything after the header block is already websocket bytes. Feed it
        # back before reading more, or the first frame is silently truncated.
        if tail:
            sock = _PrefixedSocket(sock, tail)

        t0 = time.monotonic()
        sock.sendall(_encode_frame(OP_TEXT, json.dumps(PROBE_REQUEST).encode()))

        deadline = time.monotonic() + timeout
        buffered = bytearray()
        while True:
            if time.monotonic() > deadline:
                raise WsError("no JSON-RPC answer inside the timeout")
            fin, opcode, payload = _read_frame(sock)
            if opcode == OP_PING:
                sock.sendall(_encode_frame(OP_PONG, payload))
                continue
            if opcode == OP_PONG:
                continue
            if opcode == OP_CLOSE:
                raise WsError("server closed the socket before answering")
            if opcode in (OP_TEXT, OP_BINARY, OP_CONT):
                buffered.extend(payload)
                if not fin:
                    continue
                result.rpc_ms = round((time.monotonic() - t0) * 1000, 1)
                try:
                    body = json.loads(buffered.decode("utf-8"))
                except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                    raise WsError(f"answer was not JSON: {exc}") from exc
                if "error" in body:
                    raise WsError(f"JSON-RPC error: {body['error']}")
                value = body.get("result")
                if value is None:
                    raise WsError(f"no result field: {body}")
                result.net_version = str(value)
                result.ok = True
                break
            raise WsError(f"unexpected opcode {opcode}")

    except WsError as exc:
        result.error = str(exc)
    except ssl.SSLError as exc:
        result.error = f"TLS: {exc}"
    except socket.timeout:
        result.error = f"timed out after {timeout}s"
    except OSError as exc:
        result.error = f"{type(exc).__name__}: {exc}"
    except Exception as exc:  # noqa: BLE001 - a probe must never abort the sweep
        result.error = f"{type(exc).__name__}: {exc}"
    finally:
        result.total_ms = round((time.monotonic() - started) * 1000, 1)
        if sock is not None:
            try:
                sock.close()
            except OSError:
                pass
    return result


def probe_best_of(
    url: str,
    origin: Optional[str],
    timeout: float,
    repeat: int,
    spacing: float = 1.5,
) -> Attempt:
    """Probe until one attempt succeeds, up to [repeat] times, spaced apart.

    Public RPC endpoints refuse intermittently, and **the refusals correlate in
    time** — so back-to-back retries are close to one sample, not several.
    Measured 2026-08-07 on ``wss://rpc.gnosischain.com/wss``: three consecutive
    tries all answered 400 in one sweep, while sixteen spaced tries minutes
    later gave fifteen 101s and one 400, with and without ``Origin`` alike.
    Retrying immediately reproduced the burst and condemned a live node; the
    [spacing] pause is what makes the retry an independent sample.
    """
    best: Optional[Attempt] = None
    tries = 0
    for index in range(max(1, repeat)):
        if index:
            time.sleep(spacing)
        tries += 1
        attempt = probe_once(url, origin, timeout=timeout)
        if best is None or (attempt.ok and not best.ok):
            best = attempt
        if attempt.ok:
            break
    assert best is not None
    best.tries = tries
    return best


# --------------------------------------------------------------------------
# Config inventory
# --------------------------------------------------------------------------


def collect_endpoints(
    config_path: str, only: Optional[List[str]]
) -> Dict[str, List[str]]:
    """Map every distinct ``ws_url`` to the platform tickers that publish it.

    Only ``protocol.type == "ETH"`` coins are considered: ERC-20 tokens repeat
    the platform's node list in the config, but at runtime they ``Arc::clone``
    the platform coin's pool rather than opening their own, so a token's copy is
    not an independent endpoint.
    """
    with open(config_path, encoding="utf-8") as handle:
        coins = json.load(handle)

    endpoints: Dict[str, List[str]] = {}
    for ticker, coin in sorted(coins.items()):
        if coin.get("protocol", {}).get("type") != "ETH":
            continue
        if only and ticker not in only:
            continue
        for node in coin.get("nodes") or []:
            if not isinstance(node, dict):
                continue
            ws_url = node.get("ws_url")
            if ws_url:
                endpoints.setdefault(ws_url, []).append(ticker)
    return endpoints


def load_baseline(path: str) -> Dict[str, str]:
    """Map url -> verdict from a previously archived run."""
    with open(path, encoding="utf-8") as handle:
        payload = json.load(handle)
    return {r["url"]: r.get("verdict", "dead") for r in payload.get("results", [])}


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Probe every ws_url in the coins config for a JSON-RPC answer.",
    )
    parser.add_argument("--config", default=COINS_CONFIG, help="coins_config.json path")
    parser.add_argument(
        "--url",
        action="append",
        default=[],
        help="probe this endpoint instead of reading the config (repeatable)",
    )
    parser.add_argument(
        "--only",
        default="",
        help="comma-separated platform tickers to restrict the config read to",
    )
    parser.add_argument(
        "--origin",
        default=DEFAULT_ORIGIN,
        help="Origin header for the browser-equivalent attempt (default %(default)s)",
    )
    parser.add_argument("--timeout", type=float, default=10.0, help="per-try seconds")
    parser.add_argument(
        "--repeat",
        type=int,
        default=4,
        help="tries per setting; first success wins. A single blip should not "
        "condemn a node that a rollout then loses for a year.",
    )
    parser.add_argument(
        "--spacing",
        type=float,
        default=1.5,
        help="seconds between tries. Refusals correlate in time, so "
        "back-to-back retries are one sample, not several (default %(default)s)",
    )
    parser.add_argument("--json", default="", help="write the raw result here")
    parser.add_argument(
        "--baseline",
        default="",
        help="a previously archived --json result; exit non-zero only on regressions",
    )
    args = parser.parse_args(argv)

    if args.url:
        endpoints = {url: [] for url in args.url}
        source = "--url"
    else:
        only = [t for t in args.only.split(",") if t] or None
        endpoints = collect_endpoints(args.config, only)
        source = os.path.relpath(args.config, REPO_ROOT)

    if not endpoints:
        print("no ws_url endpoints found", file=sys.stderr)
        return 1

    print(
        f"probing {len(endpoints)} endpoint(s) from {source}\n"
        f"each one twice: with Origin: {args.origin} (what web sends) "
        f"and with none (what native sends)\n"
    )
    results: List[Endpoint] = []
    for url, tickers in endpoints.items():
        endpoint = Endpoint(url=url, tickers=tickers)
        endpoint.browser = probe_best_of(
            url, args.origin, args.timeout, args.repeat, args.spacing
        )
        endpoint.native = probe_best_of(
            url, None, args.timeout, args.repeat, args.spacing
        )
        results.append(endpoint)

        mark = {
            "both": "ok       ",
            "native-only": "NATIVE ONLY",
            "web-only": "WEB ONLY ",
            "dead": "DEAD     ",
        }[endpoint.verdict]
        best = endpoint.browser if endpoint.browser_ok else endpoint.native
        detail = (
            f"net_version={best.net_version} rpc={best.rpc_ms}ms"
            if best and best.ok
            else f"web: {endpoint.browser.error} | native: {endpoint.native.error}"
        )
        print(f"  [{mark}] {url}\n         {detail}")
        if endpoint.verdict == "native-only":
            print(f"         web refused: {endpoint.browser.error}")

    usable = [r for r in results if r.browser_ok or r.native_ok]
    dead = [r for r in results if not (r.browser_ok or r.native_ok)]
    web_ok = [r for r in results if r.browser_ok]

    print(
        f"\n{len(usable)}/{len(results)} answered on at least one setting; "
        f"{len(web_ok)}/{len(results)} answered with an Origin header (i.e. work on web)\n"
    )
    if usable:
        header = f"{'endpoint':46}{'chain':11}{'verdict':13}{'rpc_ms':>8}  net_version"
        print(header)
        for r in sorted(usable, key=lambda x: (x.verdict, x.url)):
            best = r.browser if r.browser_ok else r.native
            print(
                f"{r.url:46}{','.join(r.tickers):11}{r.verdict:13}"
                f"{best.rpc_ms:>8}  {best.net_version}"
            )
    if dead:
        print("\nno answer on either setting:")
        for r in dead:
            print(
                f"  {r.url}  ({','.join(r.tickers) or 'ad-hoc'})\n"
                f"      web:    {r.browser.error}\n"
                f"      native: {r.native.error}"
            )

    payload = {
        "probed_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "config": source,
        "request": PROBE_REQUEST,
        "origin": args.origin,
        "timeout_s": args.timeout,
        "repeat": args.repeat,
        "spacing_s": args.spacing,
        "answered_any": len(usable),
        "answered_with_origin": len(web_ok),
        "total": len(results),
        "results": [
            {
                "url": r.url,
                "tickers": r.tickers,
                "verdict": r.verdict,
                "browser": asdict(r.browser) if r.browser else None,
                "native": asdict(r.native) if r.native else None,
            }
            for r in results
        ],
    }

    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)) or ".", exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
        print(f"\nwrote {args.json}")

    if args.baseline:
        baseline = load_baseline(args.baseline)
        rank = {"dead": 0, "web-only": 1, "native-only": 1, "both": 2}
        regressions = [
            (r.url, baseline[r.url], r.verdict)
            for r in results
            if r.url in baseline and rank[r.verdict] < rank[baseline[r.url]]
        ]
        if regressions:
            print(f"\nREGRESSED against {args.baseline}:")
            for url, was, now in regressions:
                print(f"  {url}: {was} -> {now}")
            return 1
        print(f"\nno regression against {args.baseline}")
        return 0

    return 0 if not dead else 1


if __name__ == "__main__":
    sys.exit(main())
