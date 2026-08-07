#!/usr/bin/env python3
"""Count what KDF asks an EVM node for, and how fast it asks.

Why this exists
---------------
The reported defect is not latency, it is *volume*: "hundreds of requests ...
more than 20 requests per second ... and obviously receives 429". Latency
probes cannot answer that, because they measure the wall clock of an
activation, not the traffic it generates. This measures the traffic.

An instrument process stands between KDF and every EVM endpoint in the coins
config. Every EVM node URL is rewritten to point at it, and it records each
HTTP request with its arrival time, its JSON-RPC method(s), the address
argument when there is one, and the status it answered with.

Three upstream modes, because they answer three different questions:

  * ``unlimited`` - a local mock that answers everything instantly and never
    refuses. This measures the load KDF *offers*: the request count and peak
    rate with no retry pressure mixed in.
  * ``limited``   - the same mock behind a token bucket (default 20/s, the
    measured capacity of evm-rpc.gleec.com). This adds the node's refusals,
    so the difference between the two runs is exactly the retry amplification.
  * ``proxy``     - forwards to the real endpoint. The truth check. Deliberately
    bounded: use it for a handful of runs, not for sweeps.

Nothing here is Flutter, Dart or SDK. The activation RPCs are issued the way
the SDK issues them (see ``tool/kdf_latency_probe.py``, from which the request
shapes are taken verbatim).
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Dict, List, Optional, Tuple

import http.client

REPO_ROOT = os.environ.get(
    "WALLET_REPO", "/Users/charl/Code/Gleec/gleec-wallet-kdf-integrations"
)
COINS_CONFIG = os.path.join(
    REPO_ROOT,
    "sdk/packages/komodo_defi_framework/assets/config/coins_config.json",
)
WORDLIST = (
    "/Users/charl/.cargo/registry/src/index.crates.io-1949cf8c6b5b557f/"
    "hkd32-0.6.0/src/mnemonic/langs/english.txt"
)

# The measured serving capacity of evm-rpc.gleec.com: it answered exactly 120
# requests in a six-second window regardless of whether the client offered 55/s
# or 32/s (see web3_pool.rs module docs).
GLEEC_RATE_PER_S = 20.0
GLEEC_BURST = 20

# What the app enables on a fresh registration - `enabledByDefaultCoins` in
# lib/app_config/app_config.dart. This is the set Decker's screenshots show.
DEFAULT_COINS = [
    "GLEEC",
    "KMD",
    "BTC-segwit",
    "ETH",
    "TRX",
    "USDT-ERC20",
    "USDT-TRC20",
    "USDC-ERC20",
]

# Every GRC-20 token on the GLEEC chain, for the worst case where a user has
# them all enabled.
GLEEC_TOKENS = [
    "A29-GRC20",
    "BCASH-GRC20",
    "BCZERO-GRC20",
    "KMD-GRC20",
    "MDX-GRC20",
    "RAPH-GRC20",
]

EVM_TYPES = {"ETH", "ERC20", "TRX"}


# --------------------------------------------------------------------------
# a brand-new wallet
# --------------------------------------------------------------------------


def mnemonic_from_entropy(entropy: bytes) -> str:
    """A valid BIP39 mnemonic from fixed entropy.

    Deliberately *not* the ``abandon ... about`` vector every other probe in
    this repo uses. That vector is the most-used test seed there is, so on
    Ethereum its gap scan keeps finding used addresses and walks hundreds of
    them - which is the opposite of the case under investigation. Decker's
    report is about a **brand-new wallet**, where nothing is used anywhere, so
    the seed has to be one nobody has ever funded.
    """
    with open(WORDLIST, "r", encoding="utf-8") as handle:
        words = [w.strip() for w in handle if w.strip()]
    if len(words) != 2048:
        raise RuntimeError(f"bad wordlist: {len(words)} words")
    checksum_bits = len(entropy) * 8 // 32
    digest = hashlib.sha256(entropy).digest()
    bits = "".join(f"{b:08b}" for b in entropy)
    bits += f"{digest[0]:08b}"[:checksum_bits]
    return " ".join(
        words[int(bits[i : i + 11], 2)] for i in range(0, len(bits), 11)
    )


# Fixed so every run in the matrix uses the identical wallet, and so the run is
# reproducible. Never funded; generated from a constant, not from randomness.
BENCH_ENTROPY = hashlib.sha256(b"gleec-rpc-burst-bench/2026-08-06").digest()[:16]


# --------------------------------------------------------------------------
# the instrument
# --------------------------------------------------------------------------


@dataclass
class Event:
    """One HTTP request as the instrument saw it."""

    t_start: float
    t_end: float
    slot: str
    upstream: str
    methods: List[str]
    addresses: List[str]
    status: int
    batch_size: int
    body_bytes: int


class Upstreams:
    """Registry mapping a slot id to the real endpoint it stands in for."""

    def __init__(self) -> None:
        self._by_slot: Dict[str, str] = {}
        self._by_url: Dict[str, str] = {}

    def slot_for(self, url: str) -> str:
        if url in self._by_url:
            return self._by_url[url]
        slot = f"n{len(self._by_slot)}"
        self._by_slot[slot] = url
        self._by_url[url] = slot
        return slot

    def url_for(self, slot: str) -> str:
        return self._by_slot.get(slot, "")


class TokenBucket:
    """A rate limit, because that is what a node actually enforces.

    Not a concurrency limit. The distinction is the whole point: a burst of 12
    at one instant is served cleanly by evm-rpc.gleec.com; 12 in flight at a
    220ms round trip is a sustained 55/s and is not.
    """

    def __init__(self, rate: float, burst: int) -> None:
        self.rate = rate
        self.burst = float(burst)
        self._tokens = float(burst)
        self._last = time.monotonic()
        self._lock = threading.Lock()

    def take(self) -> bool:
        with self._lock:
            now = time.monotonic()
            self._tokens = min(
                self.burst, self._tokens + (now - self._last) * self.rate
            )
            self._last = now
            if self._tokens >= 1.0:
                self._tokens -= 1.0
                return True
            return False


class ConnectionPool:
    """Keep-alive upstream connections, one set per host.

    Without pooling the instrument would add a TLS handshake to every request
    and depress the very rate it is trying to measure.
    """

    def __init__(self) -> None:
        self._pools: Dict[str, List[http.client.HTTPSConnection]] = defaultdict(list)
        self._lock = threading.Lock()

    def acquire(self, host: str, port: int, scheme: str):
        key = f"{scheme}://{host}:{port}"
        with self._lock:
            pool = self._pools[key]
            if pool:
                return pool.pop()
        if scheme == "https":
            return http.client.HTTPSConnection(host, port, timeout=30)
        return http.client.HTTPConnection(host, port, timeout=30)

    def release(self, host: str, port: int, scheme: str, conn) -> None:
        key = f"{scheme}://{host}:{port}"
        with self._lock:
            if len(self._pools[key]) < 32:
                self._pools[key].append(conn)
                return
        try:
            conn.close()
        except Exception:
            pass


class Instrument:
    """The HTTP server KDF talks to instead of the real endpoints."""

    def __init__(
        self,
        mode: str,
        upstreams: Upstreams,
        rate: Optional[float],
        burst: int,
        chain_id: int,
        latency_s: float = 0.0,
    ) -> None:
        self.mode = mode
        self.upstreams = upstreams
        self.chain_id = chain_id
        # A mock that answers instantly makes the *rate* unmeasurable: request
        # rate is in-flight concurrency divided by round trip, so a zero round
        # trip reports whatever the CPU can push rather than what the client
        # would offer a real node. evm-rpc.gleec.com answers in ~220ms.
        self.latency_s = latency_s
        self.events: List[Event] = []
        self.events_lock = threading.Lock()
        self.inflight = 0
        self.peak_inflight = 0
        self.t0 = time.monotonic()
        self.block = 0x1E8480
        self.bucket = TokenBucket(rate, burst) if rate else None
        self.pool = ConnectionPool()
        self.server: Optional[ThreadingHTTPServer] = None
        self.port = 0

    # -- lifecycle ---------------------------------------------------------

    def start(self) -> None:
        instrument = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *_a):  # quiet
                pass

            def do_OPTIONS(self):  # noqa: N802
                # A browser would send this; KDF native does not. Answered so
                # the same instrument can serve the web arm of the benchmark.
                allowed = instrument._preflight_allowed()
                self.send_response(204 if allowed else 429)
                if allowed or instrument.mode != "cors-strip":
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.send_header("Access-Control-Allow-Headers", "*")
                    self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
                self.send_header("Content-Length", "0")
                self.end_headers()

            def do_POST(self):  # noqa: N802
                instrument._handle(self)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def stop(self) -> None:
        if self.server:
            self.server.shutdown()
            self.server.server_close()
            self.server = None

    def reset(self) -> None:
        with self.events_lock:
            self.events = []
            self.peak_inflight = 0
            self.inflight = 0
        self.t0 = time.monotonic()
        if self.bucket:
            self.bucket = TokenBucket(self.bucket.rate, int(self.bucket.burst))

    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def _preflight_allowed(self) -> bool:
        if not self.bucket:
            return True
        return self.bucket.take()

    # -- request handling --------------------------------------------------

    def _handle(self, handler: BaseHTTPRequestHandler) -> None:
        t_start = time.monotonic() - self.t0
        with self.events_lock:
            self.inflight += 1
            if self.inflight > self.peak_inflight:
                self.peak_inflight = self.inflight

        try:
            length = int(handler.headers.get("Content-Length") or 0)
            raw = handler.rfile.read(length) if length else b""
            slot = handler.path.strip("/").split("/")[0] or "n0"
            upstream = self.upstreams.url_for(slot)

            methods, addresses, batch_size = self._parse(raw)

            if self.bucket and not self.bucket.take():
                # A refusal is cheap for the node - it is served off the edge
                # without touching the origin - so it does not get the full
                # round trip. This asymmetry is exactly why refusing is faster
                # than serving, and why throttling the client can be slower.
                if self.latency_s:
                    time.sleep(self.latency_s * 0.15)
                status, body = 429, b'{"error":"rate limited"}'
            elif self.mode == "proxy":
                status, body = self._forward(upstream, raw, handler.headers)
            else:
                if self.latency_s:
                    time.sleep(self.latency_s)
                status, body = 200, self._mock(raw)

            handler.send_response(status)
            handler.send_header("Content-Type", "application/json")
            handler.send_header("Content-Length", str(len(body)))
            # Emulate the edge that generates the 429: on `cors-strip` the
            # error response carries no CORS headers, which is what makes a
            # browser report it as a CORS failure with no status at all.
            if not (status == 429 and self.mode == "cors-strip"):
                handler.send_header("Access-Control-Allow-Origin", "*")
            handler.end_headers()
            handler.wfile.write(body)

            with self.events_lock:
                self.events.append(
                    Event(
                        t_start=t_start,
                        t_end=time.monotonic() - self.t0,
                        slot=slot,
                        upstream=upstream,
                        methods=methods,
                        addresses=addresses,
                        status=status,
                        batch_size=batch_size,
                        body_bytes=len(raw),
                    )
                )
        finally:
            with self.events_lock:
                self.inflight -= 1

    @staticmethod
    def _parse(raw: bytes) -> Tuple[List[str], List[str], int]:
        try:
            payload = json.loads(raw or b"{}")
        except Exception:
            return ["<unparseable>"], [], 1
        calls = payload if isinstance(payload, list) else [payload]
        methods, addresses = [], []
        for call in calls:
            if not isinstance(call, dict):
                continue
            methods.append(str(call.get("method", "?")))
            for param in call.get("params") or []:
                if isinstance(param, str) and param.startswith("0x") and len(param) == 42:
                    addresses.append(param.lower())
                elif isinstance(param, dict):
                    for key in ("to", "from", "address"):
                        value = param.get(key)
                        if isinstance(value, str) and len(value) == 42:
                            addresses.append(value.lower())
        return methods, addresses, len(calls)

    def _forward(self, upstream: str, raw: bytes, headers) -> Tuple[int, bytes]:
        if not upstream:
            return 502, b'{"error":"no upstream"}'
        scheme, rest = upstream.split("://", 1)
        hostport, _, path = rest.partition("/")
        host, _, port_s = hostport.partition(":")
        port = int(port_s) if port_s else (443 if scheme == "https" else 80)
        conn = self.pool.acquire(host, port, scheme)
        try:
            conn.request(
                "POST",
                "/" + path,
                body=raw,
                headers={
                    "Content-Type": "application/json",
                    "Content-Length": str(len(raw)),
                    "User-Agent": headers.get("User-Agent", "kdf-burst-bench"),
                    "Host": host,
                },
            )
            response = conn.getresponse()
            body = response.read()
            status = response.status
            self.pool.release(host, port, scheme, conn)
            return status, body
        except Exception as exc:  # noqa: BLE001
            try:
                conn.close()
            except Exception:
                pass
            return 599, json.dumps({"error": str(exc)[:200]}).encode()

    def _mock(self, raw: bytes) -> bytes:
        try:
            payload = json.loads(raw or b"{}")
        except Exception:
            return b'{"jsonrpc":"2.0","id":0,"result":null}'
        single = not isinstance(payload, list)
        calls = [payload] if single else payload
        out = [self._mock_one(call) for call in calls]
        return json.dumps(out[0] if single else out).encode()

    def _mock_one(self, call: dict) -> dict:
        method = call.get("method")
        rid = call.get("id", 0)

        def ok(result):
            return {"jsonrpc": "2.0", "id": rid, "result": result}

        if method == "eth_chainId":
            return ok(hex(self.chain_id))
        if method == "net_version":
            return ok(str(self.chain_id))
        if method == "web3_clientVersion":
            return ok("kdf-burst-bench/1.0")
        if method == "eth_blockNumber":
            self.block += 1
            return ok(hex(self.block))
        if method in ("eth_getBalance", "eth_getTransactionCount"):
            return ok("0x0")
        if method == "eth_gasPrice":
            return ok("0x3b9aca00")
        if method == "eth_maxPriorityFeePerGas":
            return ok("0x3b9aca00")
        if method == "eth_estimateGas":
            return ok("0x5208")
        if method == "eth_getCode":
            return ok("0x60006000")
        if method == "eth_call":
            # 32 zero bytes: reads as 0 for balanceOf and for decimals.
            return ok("0x" + "0" * 64)
        if method == "eth_getLogs":
            return ok([])
        if method == "eth_feeHistory":
            return ok(
                {
                    "oldestBlock": hex(self.block),
                    "baseFeePerGas": ["0x1", "0x1"],
                    "gasUsedRatio": [0.5],
                    "reward": [["0x1"]],
                }
            )
        if method in ("eth_getBlockByNumber", "eth_getBlockByHash"):
            return ok(
                {
                    "number": hex(self.block),
                    "hash": "0x" + "11" * 32,
                    "parentHash": "0x" + "22" * 32,
                    "timestamp": hex(int(time.time())),
                    "gasLimit": "0x1c9c380",
                    "gasUsed": "0x0",
                    "baseFeePerGas": "0x1",
                    "transactions": [],
                    "uncles": [],
                    "miner": "0x" + "00" * 20,
                    "difficulty": "0x0",
                    "totalDifficulty": "0x0",
                    "size": "0x0",
                    "extraData": "0x",
                    "logsBloom": "0x" + "00" * 256,
                    "nonce": "0x0000000000000000",
                    "sha3Uncles": "0x" + "00" * 32,
                    "stateRoot": "0x" + "00" * 32,
                    "receiptsRoot": "0x" + "00" * 32,
                    "transactionsRoot": "0x" + "00" * 32,
                    "mixHash": "0x" + "00" * 32,
                }
            )
        return ok(None)

    # -- metrics -----------------------------------------------------------

    def metrics(self, window: float = 1.0, step: float = 0.05) -> dict:
        with self.events_lock:
            events = list(self.events)
        if not events:
            return {"requests": 0}

        by_upstream: Dict[str, List[Event]] = defaultdict(list)
        for event in events:
            by_upstream[event.upstream or event.slot].append(event)

        def summarize(rows: List[Event]) -> dict:
            starts = sorted(e.t_start for e in rows)
            span = starts[-1] - starts[0]
            peak, peak_at = 0, 0.0
            t = starts[0]
            index = 0
            counts: List[int] = []
            while t <= starts[-1] + step:
                # requests whose start falls in [t, t+window)
                n = sum(1 for s in starts if t <= s < t + window)
                counts.append(n)
                if n > peak:
                    peak, peak_at = n, t
                t += step
            methods = defaultdict(int)
            for row in rows:
                for m in row.methods:
                    methods[m] += 1
            statuses = defaultdict(int)
            for row in rows:
                statuses[row.status] += 1
            addresses = {a for row in rows for a in row.addresses}
            first_second = sum(1 for s in starts if s < starts[0] + 1.0)
            return {
                "http_requests": len(rows),
                "jsonrpc_calls": sum(r.batch_size for r in rows),
                "batched_requests": sum(1 for r in rows if r.batch_size > 1),
                "span_s": round(span, 3),
                "first_request_at_s": round(starts[0], 3),
                "last_request_at_s": round(starts[-1], 3),
                "peak_req_per_s": peak,
                "peak_at_s": round(peak_at, 2),
                "requests_in_first_second": first_second,
                "mean_req_per_s": round(len(rows) / span, 2) if span > 0 else None,
                "methods": dict(sorted(methods.items(), key=lambda kv: -kv[1])),
                "statuses": dict(sorted(statuses.items())),
                "http_429": statuses.get(429, 0),
                "distinct_addresses": len(addresses),
                "addresses": sorted(addresses),
            }

        return {
            "total_http_requests": len(events),
            "peak_inflight": self.peak_inflight,
            "per_upstream": {k: summarize(v) for k, v in by_upstream.items()},
            "all": summarize(events),
        }


# --------------------------------------------------------------------------
# coins config
# --------------------------------------------------------------------------


def load_coins() -> Dict[str, dict]:
    with open(COINS_CONFIG, "r", encoding="utf-8") as handle:
        return json.load(handle)


def rewrite_evm_nodes(
    coins: Dict[str, dict], instrument: Instrument, upstreams: Upstreams
) -> List[dict]:
    """Point every EVM node at the instrument, remembering what it stood for."""
    out = []
    for ticker, coin in coins.items():
        entry = json.loads(json.dumps(coin))
        entry.setdefault("coin", ticker)
        nodes = entry.get("nodes")
        if isinstance(nodes, list) and nodes:
            rewritten = []
            for node in nodes:
                url = node.get("url")
                if not url:
                    continue
                slot = upstreams.slot_for(url)
                rewritten.append(
                    {"url": f"{instrument.base_url()}/{slot}", "komodo_proxy": False}
                )
            if rewritten:
                entry["nodes"] = rewritten
        out.append(entry)
    return out


# --------------------------------------------------------------------------
# KDF
# --------------------------------------------------------------------------


class Kdf:
    def __init__(self, binary: str, coins: List[dict], seed: str, workdir: str,
                 port: int, enable_hd: bool, env_extra: Optional[dict] = None) -> None:
        self.binary = binary
        self.port = port
        self.workdir = workdir
        self.password = "Bench-rpc-1!"
        self.proc: Optional[subprocess.Popen] = None
        self.log_path = os.path.join(workdir, "kdf.log")
        self.coins = coins
        self.env_extra = env_extra or {}
        dbdir = os.path.join(workdir, ".kdf")
        os.makedirs(dbdir, exist_ok=True)
        self.config = {
            "mm2": 1,
            "allow_weak_password": False,
            "rpc_password": self.password,
            "netid": 6133,
            "gui": "kdf-burst-bench",
            "wallet_name": "bench",
            "wallet_password": self.password,
            "passphrase": seed,
            "dbdir": dbdir,
            "userhome": workdir,
            "rpcport": port,
            "rpc_local_only": True,
            "allow_registrations": True,
            "enable_hd": enable_hd,
            "https": False,
            "disable_p2p": True,
        }

    def start(self, timeout: float = 90.0) -> None:
        coins_path = os.path.join(self.workdir, "coins.json")
        with open(coins_path, "w", encoding="utf-8") as handle:
            json.dump(self.coins, handle)
        env = dict(os.environ)
        env["MM_COINS_PATH"] = coins_path
        env.update(self.env_extra)
        log = open(self.log_path, "wb")
        self.proc = subprocess.Popen(
            [self.binary, json.dumps(self.config)],
            stdout=log,
            stderr=subprocess.STDOUT,
            env=env,
            start_new_session=True,
        )
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(
                    f"KDF exited during startup (code {self.proc.returncode}); "
                    f"log {self.log_path}"
                )
            try:
                self.rpc("version", timeout=3)
                return
            except Exception:
                time.sleep(0.2)
        raise RuntimeError("KDF did not open its RPC port")

    def stop(self) -> None:
        if not self.proc:
            return
        try:
            self.rpc("stop", timeout=5)
        except Exception:
            pass
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
            except Exception:
                self.proc.kill()
            try:
                self.proc.wait(timeout=5)
            except Exception:
                pass
        self.proc = None

    def rpc(self, method: str, params: Any = None, mmrpc: Optional[str] = None,
            timeout: float = 30.0) -> dict:
        payload: Dict[str, Any] = {"userpass": self.password, "method": method}
        if mmrpc:
            payload["mmrpc"] = mmrpc
        if params is not None:
            payload["params"] = params
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read().decode()
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode()
        return json.loads(raw) if raw else {}


def evm_nodes(coin: dict) -> List[dict]:
    """`EvmNode.toJson()` - url plus komodo_proxy, exactly as the SDK sends it."""
    return [
        {"url": n["url"], "komodo_proxy": bool(n.get("komodo_proxy", False))}
        for n in (coin.get("nodes") or [])
        if n.get("url")
    ]


def activate_eth_with_tokens(kdf: Kdf, coin: dict, platform: str,
                             tokens: List[str], timeout: float) -> dict:
    params: Dict[str, Any] = {
        "ticker": platform,
        "nodes": evm_nodes(coin),
        "erc20_tokens_requests": [
            {"ticker": t, "required_confirmations": 3} for t in tokens
        ],
        "priv_key_policy": {"type": "ContextPrivKey"},
        "requires_notarization": bool(coin.get("requires_notarization", False)),
        "tx_history": True,
        "get_balances": True,
    }
    if coin.get("required_confirmations") is not None:
        params["required_confirmations"] = coin["required_confirmations"]
    if coin.get("type") != "TRX":
        for key in ("swap_contract_address", "fallback_swap_contract"):
            if coin.get(key):
                params[key] = coin[key]
    return kdf.rpc("enable_eth_with_tokens", params=params, mmrpc="2.0",
                   timeout=timeout)


def hd_scan(kdf: Kdf, ticker: str, gap_limit: int = 20,
            poll_s: float = 0.25, ceiling_s: float = 20.0) -> dict:
    """`task::scan_for_new_addresses`, polled the way the SDK polls it.

    This is the step the app runs after activation, and it is the one commit
    407cf6c0a changed - activation does its own address walk, but the *scan*
    RPC is where serial became windowed-concurrent. Measuring activation alone
    misses the change entirely.

    `hd_multi_address_strategy.dart` polls every 250ms and gives up at 20s.
    Reproduced here so a scan that outruns the client's patience shows up as
    the client giving up, exactly as it would in the app.
    """
    started = time.monotonic()
    init = kdf.rpc(
        "task::scan_for_new_addresses::init",
        params={"coin": ticker, "account_index": 0, "gap_limit": gap_limit},
        mmrpc="2.0",
    )
    task_id = (init.get("result") or {}).get("task_id")
    if task_id is None:
        return {"step": "scan", "ok": False, "error": json.dumps(init)[:200],
                "seconds": round(time.monotonic() - started, 3), "polls": 0}
    polls = 0
    state = "?"
    detail = ""
    while True:
        status = kdf.rpc(
            "task::scan_for_new_addresses::status",
            params={"task_id": task_id, "forget_if_finished": False},
            mmrpc="2.0",
        )
        polls += 1
        payload = status.get("result") or {}
        state = payload.get("status", "?")
        if state in ("Ok", "Error"):
            detail = json.dumps(payload.get("details"))[:200]
            break
        if time.monotonic() - started > ceiling_s:
            state = "ClientGaveUp"
            break
        time.sleep(poll_s)
    return {
        "step": "scan",
        "ok": state == "Ok",
        "state": state,
        "detail": detail,
        "seconds": round(time.monotonic() - started, 3),
        "polls": polls,
    }


def hd_account_balance(kdf: Kdf, ticker: str, poll_s: float = 0.10,
                       ceiling_s: float = 60.0) -> dict:
    started = time.monotonic()
    init = kdf.rpc(
        "task::account_balance::init",
        params={"coin": ticker, "account_index": 0},
        mmrpc="2.0",
    )
    task_id = (init.get("result") or {}).get("task_id")
    if task_id is None:
        return {"step": "account_balance", "ok": False,
                "error": json.dumps(init)[:200],
                "seconds": round(time.monotonic() - started, 3), "polls": 0}
    polls = 0
    addresses = 0
    state = "?"
    while True:
        status = kdf.rpc(
            "task::account_balance::status",
            params={"task_id": task_id, "forget_if_finished": False},
            mmrpc="2.0",
        )
        polls += 1
        payload = status.get("result") or {}
        state = payload.get("status", "?")
        if state == "Ok":
            addresses = len((payload.get("details") or {}).get("addresses") or [])
            break
        if state == "Error":
            break
        if time.monotonic() - started > ceiling_s:
            state = "ClientGaveUp"
            break
        time.sleep(poll_s)
    return {
        "step": "account_balance",
        "ok": state == "Ok",
        "state": state,
        "addresses": addresses,
        "seconds": round(time.monotonic() - started, 3),
        "polls": polls,
    }


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


# --------------------------------------------------------------------------
# scenarios
# --------------------------------------------------------------------------


def run_once(binary_dir: str, sha: str, scenario: str, mode: str,
             rate: Optional[float], enable_hd: bool, coins_index: Dict[str, dict],
             env_extra: Optional[dict] = None, verbose: bool = False,
             latency_s: float = 0.0) -> dict:
    upstreams = Upstreams()
    instrument = Instrument(
        mode=mode,
        upstreams=upstreams,
        rate=rate,
        burst=GLEEC_BURST,
        chain_id=11169,
        latency_s=latency_s,
    )
    instrument.start()

    coins_list = rewrite_evm_nodes(coins_index, instrument, upstreams)
    coins_by_ticker = {c["coin"]: c for c in coins_list}

    workdir = tempfile.mkdtemp(prefix=f"burst-{sha}-")
    kdf = Kdf(
        binary=os.path.join(binary_dir, "kdf"),
        coins=coins_list,
        seed=mnemonic_from_entropy(BENCH_ENTROPY),
        workdir=workdir,
        port=free_port(),
        enable_hd=enable_hd,
        env_extra=env_extra,
    )

    outcome: Dict[str, Any] = {
        "sha": sha,
        "scenario": scenario,
        "mode": mode,
        "rate_limit_per_s": rate,
        "hd": enable_hd,
    }
    try:
        kdf.start()
        # Start counting only once KDF is up, so process start-up does not land
        # in the first-second bucket.
        instrument.reset()
        started = time.monotonic()

        platform, tokens = {
            "gleec-only": ("GLEEC", []),
            "gleec-all-tokens": ("GLEEC", GLEEC_TOKENS),
            "eth-default": ("ETH", ["USDT-ERC20", "USDC-ERC20"]),
            # The full sequence the SDK issues at login, not just activation.
            "app-login-gleec": ("GLEEC", []),
            "app-login-gleec-tokens": ("GLEEC", GLEEC_TOKENS),
            "app-login-eth": ("ETH", ["USDT-ERC20", "USDC-ERC20"]),
        }.get(scenario, (None, None))
        if platform is None:
            raise ValueError(f"unknown scenario {scenario}")

        response = activate_eth_with_tokens(
            kdf, coins_by_ticker[platform], platform, tokens, timeout=900
        )
        outcome["activation_s"] = round(time.monotonic() - started, 3)
        if "error" in response:
            outcome["ok"] = False
            outcome["error"] = str(response.get("error"))[:300]
            outcome["error_type"] = str(response.get("error_type", ""))[:80]
        else:
            outcome["ok"] = True
            result = response.get("result") or {}
            outcome["current_block"] = result.get("current_block")
            outcome["addresses_reported"] = _count_reported_addresses(result)

        if scenario.startswith("app-login") and outcome.get("ok") and enable_hd:
            # Everything the SDK does after activation on an HD wallet, in the
            # order it does it, for the platform coin and then each token.
            steps = []
            for ticker in [platform] + list(tokens):
                steps.append(hd_scan(kdf, ticker))
                steps.append(hd_account_balance(kdf, ticker))
            outcome["post_activation_steps"] = steps
            outcome["login_total_s"] = round(time.monotonic() - started, 3)

        # Let anything periodic show itself: 10s of quiet observation after the
        # activation returns. Decker's complaint is about "after startup", so a
        # post-activation tail matters.
        time.sleep(10.0)
        outcome["metrics"] = instrument.metrics()
        outcome["log_tail"] = _log_tail(kdf.log_path)
    except Exception as exc:  # noqa: BLE001
        outcome["ok"] = False
        outcome["error"] = f"{type(exc).__name__}: {exc}"[:300]
        outcome["metrics"] = instrument.metrics()
        outcome["log_tail"] = _log_tail(kdf.log_path)
    finally:
        kdf.stop()
        instrument.stop()
        if not verbose:
            shutil.rmtree(workdir, ignore_errors=True)
        else:
            outcome["workdir"] = workdir
    return outcome


def _count_reported_addresses(result: dict) -> int:
    for key in ("eth_addresses_infos", "erc20_addresses_infos"):
        block = result.get(key)
        if isinstance(block, dict):
            return len(block)
    balance = result.get("wallet_balance") or {}
    accounts = balance.get("accounts")
    if isinstance(accounts, list) and accounts:
        return len(accounts[0].get("addresses") or [])
    return -1


def _log_tail(path: str, lines: int = 40) -> List[str]:
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            return [l.rstrip() for l in handle.readlines()[-lines:]]
    except Exception:
        return []


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin-root", required=True)
    parser.add_argument("--shas", default="bd413dc,ed8de23,34ab0e7,a86fa37,4254e19,25f6e1f")
    parser.add_argument("--scenario", default="gleec-only")
    parser.add_argument("--mode", default="unlimited",
                        choices=["unlimited", "limited", "proxy", "cors-strip"])
    parser.add_argument("--rate", type=float, default=None,
                        help="requests/s the instrument will serve; default 20 for "
                             "limited/cors-strip, unlimited otherwise")
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--latency-ms", type=float, default=220.0,
                        help="round trip the mock imposes; the measured RTT of "
                             "evm-rpc.gleec.com. Ignored in proxy mode.")
    parser.add_argument("--iguana", action="store_true",
                        help="run in iguana (single-address) mode instead of HD")
    parser.add_argument("--json", default=None)
    parser.add_argument("--env", action="append", default=[],
                        help="extra env for KDF, KEY=VALUE")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    rate = args.rate
    if rate is None and args.mode in ("limited", "cors-strip"):
        rate = GLEEC_RATE_PER_S

    env_extra = {}
    for item in args.env:
        key, _, value = item.partition("=")
        env_extra[key] = value

    coins_index = load_coins()
    results = []
    for sha in [s.strip() for s in args.shas.split(",") if s.strip()]:
        binary_dir = os.path.join(args.bin_root, sha)
        if not os.path.isfile(os.path.join(binary_dir, "kdf")):
            print(f"!! no binary for {sha}", file=sys.stderr)
            continue
        for run in range(args.repeat):
            print(f"-- {sha} {args.scenario} {args.mode} run {run + 1}/{args.repeat}",
                  file=sys.stderr, flush=True)
            outcome = run_once(
                binary_dir=binary_dir,
                sha=sha,
                scenario=args.scenario,
                mode=args.mode,
                rate=rate,
                enable_hd=not args.iguana,
                coins_index=coins_index,
                env_extra=env_extra,
                verbose=args.verbose,
                latency_s=(0.0 if args.mode == "proxy" else args.latency_ms / 1000.0),
            )
            outcome["run"] = run + 1
            results.append(outcome)
            summary = outcome.get("metrics", {}).get("all", {})
            print(
                f"   ok={outcome.get('ok')} "
                f"t={outcome.get('login_total_s', outcome.get('activation_s'))}s "
                f"req={summary.get('http_requests')} "
                f"peak/s={summary.get('peak_req_per_s')} "
                f"first_s={summary.get('requests_in_first_second')} "
                f"429={summary.get('http_429')} "
                f"addrs={summary.get('distinct_addresses')}",
                file=sys.stderr, flush=True,
            )
            if not outcome.get("ok"):
                print(f"   error: {outcome.get('error')}", file=sys.stderr, flush=True)

    payload = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "scenario": args.scenario,
        "mode": args.mode,
        "rate_limit_per_s": rate,
        "latency_ms": 0.0 if args.mode == "proxy" else args.latency_ms,
        "hd": not args.iguana,
        "seed_fingerprint": hashlib.sha256(
            mnemonic_from_entropy(BENCH_ENTROPY).encode()
        ).hexdigest()[:16],
        "results": results,
    }
    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=1)
        print(f"wrote {args.json}", file=sys.stderr)
    else:
        print(json.dumps(payload, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
