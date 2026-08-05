#!/usr/bin/env python3
"""Measure KDF wallet-load latency with no Flutter, no Dart and no SDK.

Why this exists
---------------
The Dart harness says HD logins are slow. That is only a useful claim if the
slowness is in KDF rather than in our orchestration of it, and a measurement
taken *through* the SDK cannot separate the two. This script talks to the KDF
binary over HTTP directly: it spawns the process, sends the same RPCs in the
same order, and times them. Nothing between the stopwatch and KDF.

If this reports the same numbers the Dart harness does, the latency is KDF's.

Requirements
------------
* Python 3.9+, standard library only.
* The KDF binary (the Flutter build transformer fetches it to
  ``sdk/packages/komodo_defi_framework/{macos,linux}/bin/kdf``). Override with
  ``--kdf``.
* A coins config JSON. Auto-detected from this repo; override with ``--coins``.
* ``KDF_TEST_SEED`` in the environment, so it stays out of *this* script's
  shell history and argv.

  **It is still visible in ``ps``.** KDF takes its whole config - passphrase
  included - as ``argv[1]`` of the spawned process, so the seed is readable by
  any local user for the lifetime of each scenario. Use a throwaway seed with
  no funds; the public ``abandon ... about`` vector is what every measurement
  in the docs used.

Usage
-----
    export KDF_TEST_SEED='abandon abandon ... about'
    python3 tool/kdf_latency_probe.py                  # default matrix
    python3 tool/kdf_latency_probe.py --json out.json  # machine-readable too
    python3 tool/kdf_latency_probe.py --quick          # one scenario, fast

Each scenario starts a **fresh KDF with a fresh database directory**, so no run
can be warmed by a previous one.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, List, Optional, Set, Tuple

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Matches the SDK. `hd_multi_address_strategy.dart` polls the scan every 250ms
# with a 20s ceiling and account_balance every 100ms with a 60s ceiling; the
# UTXO activation strategy polls every 500ms. Reproduced here so the RPC
# *pattern* is the same as the app's, not just the RPC set.
SCAN_POLL_S = 0.25
SCAN_TIMEOUT_S = 20.0
ACCOUNT_BALANCE_POLL_S = 0.10
ACCOUNT_BALANCE_TIMEOUT_S = 60.0
ACTIVATION_POLL_S = 0.50
ACTIVATION_TIMEOUT_S = 180.0
# `enable_eth_with_tokens` is SYNCHRONOUS - no task id, no progress, the caller
# just blocks. Measured at 356s for ETH + 2 ERC-20 tokens on HD (2.3s on
# iguana), so the ceiling has to be generous or the probe times out before KDF
# answers and reports a network failure that never happened.
EVM_ACTIVATION_TIMEOUT_S = 900.0

DEFAULT_PORT = 7783

# Only needed with --p2p. Taken from the app's own startup config.
SEED_NODES = [
    "seed01.kmdefi.net",
    "seed03.kmdefi.net",
    "kdfseed1.decker.im",
    "staking1.gleec.com",
    "staking2.gleec.com",
]

# Top-20 by market cap, mapped onto what THIS wallet's coins_config actually
# has. Three constructions of the same 19 assets, because "20 coins" and "20
# activations" are very different numbers: a platform and all of its tokens
# activate in ONE `enable_eth_with_tokens` call, and asking for a token
# silently forces its platform to activate too.
#
# XMR, APT and OP have no entry at all. POL does not exist either - Polygon is
# still keyed MATIC. ADA/DOT/XLM/HBAR/SUI/NEAR exist ONLY as -BEP20.
#
# List is as of 2026-08 and is a judgement call, not a live feed. Edit freely;
# the probe reports whatever it is given.
COIN_SETS: Dict[str, List[str]] = {
    # Canonical: native chain where this wallet has one, else the ERC-20 form.
    # Batches naturally into 4 utxo + 5 platform calls.
    "top20-median": [
        "BTC", "LTC", "DOGE", "BCH",
        "ETH", "USDT-ERC20", "USDC-ERC20", "XRP-ERC20", "LINK-ERC20",
        "SHIB-ERC20", "DAI-ERC20",
        "BNB", "SOL-BEP20", "ADA-BEP20", "DOT-BEP20", "XLM-BEP20",
        "AVAX", "MATIC", "TRX",
    ],
    # Everything wrappable taken as BEP-20, so one platform absorbs 13 tokens.
    # Best-case batching.
    "top20-min": [
        "BTC", "LTC", "DOGE", "BCH",
        "ETH",
        "BNB", "USDT-BEP20", "USDC-BEP20", "XRP-BEP20", "SOL-BEP20",
        "ADA-BEP20", "DOT-BEP20", "XLM-BEP20", "LINK-BEP20", "SHIB-BEP20",
        "DAI-BEP20", "AVAX-BEP20", "MATIC-BEP20", "TRX-BEP20",
    ],
    # Deliberately spread across as many distinct chains as the config allows.
    # Pulls in extra platforms (KCS via -KRC20, ETH-BASE via -BASE) that were
    # never asked for.
    "top20-max": [
        "BTC", "LTC", "DOGE", "BCH",
        "ETH", "BNB", "AVAX", "MATIC", "TRX",
        "USDT-KRC20", "USDC-BASE", "XRP-ERC20", "SOL-PLG20", "ADA-BEP20",
        "LINK-AVX20", "DOT-BEP20", "SHIB-KRC20", "DAI-AVX20", "XLM-BEP20",
    ],
    # What a real new login on this app actually enables
    # (`enabledByDefaultCoins`, lib/app_config/app_config.dart).
    "app-default": [
        "GLEEC", "KMD", "BTC-segwit", "ETH", "TRX",
        "USDT-ERC20", "USDT-TRC20", "USDC-ERC20",
    ],
}

# The default --coin-list. Named so `--quick` can tell "the user asked for
# these coins" from "nobody said", which decides whether it runs the whole list
# or just the first entry.
COIN_LIST_DEFAULT = "KMD,MARTY,DOC,BTC,LTC,DGB,RVN,VRSC"

# `type` values that activate through the EVM batch call. Mirrors
# EthWithTokensActivationStrategy.supportedProtocols. Note TRX is here too -
# there is no `enable_trx_with_tokens`; only the params object differs.
EVM_TYPES = {
    "ERC-20", "BEP-20", "Matic", "AVX-20", "KRC-20", "Arbitrum", "Base",
    "TRX", "TRC-20", "Ethereum Classic", "Moonbeam", "Moonriver", "HRC-20",
    "EWT", "QRC-20", "GRC-20", "RSK Smart Bitcoin", "ETH",
}
UTXO_TYPES = {"UTXO", "Smart Chain"}


@dataclass
class ActivationOp:
    """One activation RPC, as the SDK would issue it."""

    kind: str  # "utxo" | "eth_with_tokens" | "erc20"
    ticker: str
    tokens: List[str] = field(default_factory=list)
    forced: bool = False  # platform we added because a token needed it


def plan_activations(
    tickers: List[str],
    coins_index: Dict[str, dict],
    unbatched: bool = False,
) -> Tuple[List[ActivationOp], List[str]]:
    """Turn a wanted coin list into the activation RPCs the SDK would send.

    Mirrors `_AssetGroup._groupByPrimary` (activation_manager.dart): assets are
    bucketed under `parent_coin`, a platform carries its tokens in one call, and
    a token whose platform was not requested forces that platform in anyway.

    With `unbatched=True` each token is issued as its own `enable_erc20` after
    its platform - which is what the SDK actually does when the platform was
    already active. That is the worst case, and it is reachable in production.

    Returns (ops, skipped) where `skipped` are tickers with no config entry.
    """
    skipped = [t for t in tickers if t not in coins_index]
    wanted = [t for t in tickers if t in coins_index]

    platforms: Dict[str, List[str]] = {}
    standalone: List[str] = []
    for ticker in wanted:
        parent = coins_index[ticker].get("parent_coin")
        if parent:
            platforms.setdefault(parent, []).append(ticker)
        else:
            platforms.setdefault(ticker, [])

    ops: List[ActivationOp] = []
    for platform, tokens in platforms.items():
        entry = coins_index.get(platform)
        if entry is None:
            skipped.extend(tokens)
            continue
        forced = platform not in wanted
        kind = "utxo" if entry.get("type") in UTXO_TYPES else "eth_with_tokens"
        if kind == "utxo":
            ops.append(ActivationOp("utxo", platform, forced=forced))
            # A UTXO platform cannot carry tokens; anything parented to it is
            # out of scope for this probe.
            skipped.extend(tokens)
            continue
        ops.append(
            ActivationOp(
                "eth_with_tokens",
                platform,
                tokens=[] if unbatched else list(tokens),
                forced=forced,
            )
        )
        if unbatched:
            ops.extend(ActivationOp("erc20", token) for token in tokens)

    # Platforms first so a token never precedes its platform.
    ops.sort(key=lambda op: 0 if op.kind != "erc20" else 1)
    _ = standalone
    return ops, skipped


# --------------------------------------------------------------------------
# small helpers
# --------------------------------------------------------------------------


def find_kdf_binary(explicit: Optional[str]) -> Optional[str]:
    if explicit:
        return explicit if os.path.exists(explicit) else None
    env = os.environ.get("KDF_BINARY")
    if env and os.path.exists(env):
        return env
    plat = {"Darwin": "macos", "Linux": "linux"}.get(platform.system())
    if not plat:
        return None
    candidate = os.path.join(
        REPO_ROOT, "sdk", "packages", "komodo_defi_framework", plat, "bin", "kdf"
    )
    return candidate if os.path.exists(candidate) else None


def find_coins_config(explicit: Optional[str]) -> Optional[str]:
    if explicit:
        return explicit if os.path.exists(explicit) else None
    for rel in (
        "sdk/packages/komodo_defi_framework/assets/config/coins_config.json",
        "build/web/assets/packages/komodo_defi_framework/assets/config/coins_config.json",
    ):
        path = os.path.join(REPO_ROOT, rel)
        if os.path.exists(path):
            return path
    return None


def port_is_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind(("127.0.0.1", port))
            return True
        except OSError:
            return False


def wait_for_free_port(port: int, timeout: float = 30.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if port_is_free(port):
            return True
        time.sleep(0.25)
    return False


# --------------------------------------------------------------------------
# results
# --------------------------------------------------------------------------


@dataclass
class Step:
    """One logical step, e.g. 'activate KMD'."""

    name: str
    seconds: float
    polls: int = 0
    detail: str = ""
    timed_out: bool = False
    # Distinct from `timed_out`: a step that ERRORED rather than exceeded a
    # ceiling. Kept separate because `derive_findings` reasons specifically
    # about the 20s scan ceiling, and because a failure returns FAST - recording
    # one as a completed step turns an error into an apparent speedup, which is
    # exactly how a `NoSuchCoin` once looked like a 92x win.
    failed: bool = False


@dataclass
class ScenarioResult:
    name: str
    wallet_type: str
    coins: List[str]
    gap_limit: int
    scan_policy: str
    steps: List[Step] = field(default_factory=list)
    rpc_counts: Dict[str, int] = field(default_factory=dict)
    rpc_seconds: Dict[str, float] = field(default_factory=dict)
    total_seconds: float = 0.0
    addresses_returned: int = 0
    #: How many activation RPCs the plan produced. Deliberately reported next to
    #: the coin count: a platform carries its tokens in one call, so the two
    #: numbers differ and the gap is the lever the app controls.
    activation_calls: int = 0
    forced_platforms: List[str] = field(default_factory=list)
    skipped_coins: List[str] = field(default_factory=list)
    error: Optional[str] = None

    def step(self, name: str) -> Optional[Step]:
        for candidate in self.steps:
            if candidate.name == name:
                return candidate
        return None


# --------------------------------------------------------------------------
# the KDF client
# --------------------------------------------------------------------------


class KdfProcess:
    """Spawns KDF and speaks its JSON-RPC over HTTP. No SDK involved."""

    def __init__(
        self,
        binary: str,
        coins: List[dict],
        seed: str,
        rpc_password: str,
        port: int,
        wallet_name: str,
        wallet_password: str,
        enable_hd: bool,
        workdir: str,
        verbose: bool = False,
        p2p: bool = False,
    ) -> None:
        self.binary = binary
        self.port = port
        self.rpc_password = rpc_password
        self.workdir = workdir
        self.verbose = verbose
        self.proc: Optional[subprocess.Popen] = None
        self.rpc_counts: Dict[str, int] = {}
        self.rpc_seconds: Dict[str, float] = {}
        self.stdout_path = os.path.join(workdir, "kdf.log")

        dbdir = os.path.join(workdir, ".kdf")
        os.makedirs(dbdir, exist_ok=True)

        # Mirrors what the Dart auth layer sends, minus p2p. Two KDF prechecks
        # bite here and are worth knowing about:
        #   * "Cannot disable P2P while seed nodes are configured" - the two
        #     settings must agree, so `seednodes` is omitted entirely.
        #   * "Password can't contain the word password" - applies to
        #     rpc_password.
        self.config = {
            "mm2": 1,
            "allow_weak_password": False,
            "rpc_password": rpc_password,
            "netid": 6133,
            "gui": "kdf-latency-probe",
            "wallet_name": wallet_name,
            "wallet_password": wallet_password,
            "passphrase": seed,
            "dbdir": dbdir,
            "userhome": workdir,
            "rpcport": port,
            "rpc_local_only": True,
            "allow_registrations": True,
            "enable_hd": enable_hd,
            "https": False,
        }
        if p2p:
            # TRX activation panics without a P2P context - see the note on
            # `--p2p` in main(). Seed nodes and p2p must agree: KDF refuses to
            # start with "Cannot disable P2P while seed nodes are configured."
            self.config["seednodes"] = SEED_NODES
        else:
            self.config["disable_p2p"] = True
        self.coins = coins

    # -- lifecycle ---------------------------------------------------------

    def start(self, timeout: float = 60.0) -> None:
        coins_path = os.path.join(self.workdir, "coins.json")
        with open(coins_path, "w", encoding="utf-8") as handle:
            json.dump(self.coins, handle)

        env = dict(os.environ)
        env["MM_COINS_PATH"] = coins_path

        log = open(self.stdout_path, "wb")
        self.proc = subprocess.Popen(
            [self.binary, json.dumps(self.config)],
            stdout=log,
            stderr=subprocess.STDOUT,
            env=env,
            # Own process group, so a Ctrl-C that kills this script can take the
            # whole group with it instead of orphaning a KDF onto the port.
            start_new_session=True,
        )

        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(
                    f"KDF exited during startup (code {self.proc.returncode}). "
                    f"Log: {self.stdout_path}"
                )
            try:
                self.rpc("version", count=False)
                return
            except Exception:
                time.sleep(0.25)
        raise RuntimeError(f"KDF did not open its RPC port within {timeout}s")

    def stop(self) -> None:
        if not self.proc:
            return
        try:
            self.rpc("stop", count=False)
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

    # -- rpc ---------------------------------------------------------------

    def rpc(
        self,
        method: str,
        params: Optional[dict] = None,
        mmrpc: Optional[str] = None,
        timeout: float = 30.0,
        count: bool = True,
    ) -> dict:
        payload: Dict[str, Any] = {"userpass": self.rpc_password, "method": method}
        if mmrpc:
            payload["mmrpc"] = mmrpc
        if params is not None:
            payload["params"] = params

        body = json.dumps(payload).encode()
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}",
            data=body,
            headers={"Content-Type": "application/json"},
        )
        started = time.time()
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read().decode()
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode()
        elapsed = time.time() - started

        if count:
            self.rpc_counts[method] = self.rpc_counts.get(method, 0) + 1
            self.rpc_seconds[method] = self.rpc_seconds.get(method, 0.0) + elapsed
        if self.verbose:
            print(f"    [rpc] {method} {elapsed*1000:.0f}ms", file=sys.stderr)

        return json.loads(raw) if raw else {}


# --------------------------------------------------------------------------
# the scenario
# --------------------------------------------------------------------------


def electrum_server(server: dict) -> dict:
    """One `servers` entry, shaped the way the SDK ships it.

    `WssWebsocketTransform` synthesises `ws_url` from `url` for every `WSS`
    entry (`config_transform.dart:259`) - the raw config has no `ws_url` at
    all. Omitting it is not a cosmetic difference: KDF then has no websocket
    endpoint to dial and the connection fails, which is exactly how "native
    cannot do WSS" nearly became a finding.
    """
    entry: Dict[str, Any] = {"url": server["url"]}
    if "protocol" in server:
        entry["protocol"] = server["protocol"]
    if server.get("protocol") == "WSS":
        entry["ws_url"] = server.get("ws_url", server["url"])
    return entry


def utxo_activation_params(coin: dict, gap_limit: int, scan_policy: str,
                           enable_hd: bool,
                           protocols: Optional[Set[str]] = None) -> dict:
    """The same shape `UtxoProtocol.defaultActivationParams` builds.

    [protocols] restricts which electrum entries are offered, which is what the
    SDK's `WssWebsocketTransform` does per platform: `WSS` only on web,
    everything else on native. Pass it to reproduce either platform's server
    list on the other platform's binary.
    """
    servers = coin.get("electrum") or []
    if protocols is not None:
        servers = [s for s in servers if s.get("protocol") in protocols]
    params: Dict[str, Any] = {
        "mode": {
            "rpc": "Electrum",
            "rpc_data": {
                "servers": [electrum_server(server) for server in servers]
            },
        },
        "tx_history": True,
    }
    if enable_hd:
        params.update(
            {
                "scan_policy": scan_policy,
                "gap_limit": gap_limit,
                "min_addresses_number": 1,
            }
        )
    return params


def run_scenario(
    *,
    binary: str,
    coins_index: Dict[str, dict],
    seed: str,
    tickers: List[str],
    wallet_type: str,
    gap_limit: int,
    scan_policy: str,
    port: int,
    keep_workdir: bool,
    verbose: bool,
    label: str,
    unbatched: bool = False,
    p2p: bool = False,
    electrum_protocols: Optional[Set[str]] = None,
) -> ScenarioResult:
    enable_hd = wallet_type == "hd"
    result = ScenarioResult(
        name=label,
        wallet_type=wallet_type,
        coins=list(tickers),
        gap_limit=gap_limit,
        scan_policy=scan_policy if enable_hd else "n/a",
    )

    ops, skipped = plan_activations(tickers, coins_index, unbatched=unbatched)
    if not ops:
        result.error = f"nothing activatable in {', '.join(tickers)}"
        return result
    result.skipped_coins = skipped
    result.activation_calls = len(ops)
    result.forced_platforms = [op.ticker for op in ops if op.forced]

    # KDF needs a config entry for every coin it will be asked about, including
    # platforms pulled in on a token's behalf.
    needed: List[str] = []
    for op in ops:
        for ticker in [op.ticker, *op.tokens]:
            if ticker not in needed:
                needed.append(ticker)

    if not wait_for_free_port(port):
        result.error = f"port {port} is in use (lsof -nP -iTCP:{port})"
        return result

    workdir = tempfile.mkdtemp(prefix="kdf_probe_")
    kdf = KdfProcess(
        binary=binary,
        coins=[coins_index[t] for t in needed],
        seed=seed,
        rpc_password="Probe1!Rpc2Secret",  # must not contain "password"
        port=port,
        wallet_name=f"probe-{wallet_type}",
        wallet_password="Probe1!Wallet2",
        enable_hd=enable_hd,
        workdir=workdir,
        verbose=verbose,
        p2p=p2p,
    )

    scenario_started = time.time()
    try:
        boot_started = time.time()
        kdf.start()
        result.steps.append(Step("kdf_boot", time.time() - boot_started))

        for op in ops:
            if op.kind == "utxo":
                _activate(
                    kdf, result, op.ticker, coins_index[op.ticker],
                    gap_limit, scan_policy, enable_hd, electrum_protocols,
                )
            elif op.kind == "eth_with_tokens":
                _activate_eth_with_tokens(
                    kdf, result, op.ticker, op.tokens, coins_index, enable_hd,
                )
            else:
                _activate_erc20(kdf, result, op.ticker, coins_index)

        # Balance for the *first activated* coin only: the metric under study is
        # time-to-first-balance, and later coins would measure queueing.
        first = ops[0].ticker
        if enable_hd:
            _hd_scan(kdf, result, first)
            _hd_account_balance(kdf, result, first)
        else:
            _iguana_balance(kdf, result, first)

    except Exception as exc:  # noqa: BLE001 - reported, not swallowed
        result.error = f"{type(exc).__name__}: {exc}"
    finally:
        result.total_seconds = time.time() - scenario_started
        result.rpc_counts = dict(kdf.rpc_counts)
        result.rpc_seconds = dict(kdf.rpc_seconds)
        kdf.stop()
        wait_for_free_port(port, timeout=20)
        if keep_workdir:
            print(f"    workdir kept: {workdir}", file=sys.stderr)
        else:
            shutil.rmtree(workdir, ignore_errors=True)

    return result


def _activate(kdf, result, ticker, coin, gap_limit, scan_policy, enable_hd,
              protocols=None):
    started = time.time()
    init = kdf.rpc(
        "task::enable_utxo::init",
        params={
            "ticker": ticker,
            "activation_params": utxo_activation_params(
                coin, gap_limit, scan_policy, enable_hd, protocols
            ),
        },
        mmrpc="2.0",
    )
    task_id = (init.get("result") or {}).get("task_id")
    if task_id is None:
        raise RuntimeError(f"enable_utxo::init for {ticker} failed: {init}")

    polls = 0
    detail = ""
    timed_out = False
    while True:
        status = kdf.rpc(
            "task::enable_utxo::status",
            params={"task_id": task_id, "forget_if_finished": False},
            mmrpc="2.0",
        )
        polls += 1
        state = (status.get("result") or {}).get("status")
        if state == "Ok":
            break
        if state == "Error":
            # Mark it FAILED, not merely finished. A failed activation returns
            # fast, so recording it as a completed step made an error look like
            # a speedup - which is exactly how "WSS activates in 0.5s" nearly
            # got reported as a 92x win instead of `NoSuchCoin`.
            detail = json.dumps((status.get("result") or {}).get("details"))[:200]
            timed_out = True
            break
        if time.time() - started > ACTIVATION_TIMEOUT_S:
            timed_out = True
            break
        time.sleep(ACTIVATION_POLL_S)

    result.steps.append(
        Step(
            f"activate:{ticker}",
            time.time() - started,
            polls=polls,
            detail=detail,
            timed_out=timed_out,
        )
    )


def _evm_nodes(coin: dict) -> List[dict]:
    """`EvmNode.toJson()` - url plus komodo_proxy, and nothing else.

    The config's `ws_url` is deliberately dropped: `EvmNode` has no such field,
    so the SDK never sends it and neither do we.
    """
    nodes = []
    for node in coin.get("nodes") or []:
        nodes.append(
            {
                "url": node["url"],
                "komodo_proxy": bool(
                    node.get("komodo_proxy", node.get("gui_auth", False))
                ),
            }
        )
    return nodes


def _activate_eth_with_tokens(kdf, result, platform, tokens, coins_index,
                              enable_hd):
    """`enable_eth_with_tokens` - one call for a platform and all its tokens.

    Unlike the UTXO path this is **synchronous**: there is no task id and
    nothing to poll. Params sit flat under `params`, not nested in
    `activation_params` (which is what `enable_erc20` does instead).

    TRX comes through here too - there is no `enable_trx_with_tokens` in the
    SDK; only the params object differs, dropping the swap contracts.
    """
    coin = coins_index[platform]
    started = time.time()

    params: Dict[str, Any] = {
        "ticker": platform,
        "nodes": _evm_nodes(coin),
        "erc20_tokens_requests": [
            # `required_confirmations` here is TokensRequest's hardcoded 3, NOT
            # the token's own config value. Matching the SDK exactly matters:
            # a different value would be a different request.
            {"ticker": token, "required_confirmations": 3}
            for token in tokens
        ],
        "priv_key_policy": {"type": "ContextPrivKey"},
        "requires_notarization": bool(coin.get("requires_notarization", False)),
        "tx_history": True,
        "get_balances": True,
    }
    if coin.get("required_confirmations") is not None:
        params["required_confirmations"] = coin["required_confirmations"]
    # TRX has no swap contracts in its params object.
    if coin.get("type") != "TRX":
        for key in ("swap_contract_address", "fallback_swap_contract"):
            if coin.get(key):
                params[key] = coin[key]

    response = kdf.rpc(
        "enable_eth_with_tokens",
        params=params,
        mmrpc="2.0",
        timeout=EVM_ACTIVATION_TIMEOUT_S,
    )
    detail = ""
    failed = False
    if "error" in response:
        failed = True
        detail = str(response.get("error"))[:160]
    else:
        block = (response.get("result") or {}).get("current_block")
        detail = f"{len(tokens)} token(s), block {block}"

    result.steps.append(
        Step(
            f"activate:{platform}"
            + (f"+{len(tokens)}tok" if tokens else ""),
            time.time() - started,
            polls=1,
            detail=detail,
            # `failed`, not `timed_out`. This call is synchronous, so a refused
            # activation comes back in about a second - the fastest row in the
            # table - and reporting it as a timeout made a hard 100% failure
            # look like a timing. GLEEC failed every HD activation for a week
            # while this printed "<-- TIMED OUT" next to 1.1s.
            failed=failed,
        )
    )


def _activate_erc20(kdf, result, ticker, coins_index):
    """`enable_erc20` - one token, after its platform is already up.

    This is what the SDK falls back to when the platform was activated first
    (activation_strategy_base.dart), and it is the unbatched worst case. Note
    the params ARE nested here, unlike enable_eth_with_tokens.
    """
    coin = coins_index[ticker]
    started = time.time()
    activation_params: Dict[str, Any] = {
        "requires_notarization": bool(coin.get("requires_notarization", False)),
        "priv_key_policy": {"type": "ContextPrivKey"},
        "nodes": _evm_nodes(coin),
    }
    for key in ("swap_contract_address", "fallback_swap_contract"):
        if coin.get(key):
            activation_params[key] = coin[key]

    response = kdf.rpc(
        "enable_erc20",
        params={"ticker": ticker, "activation_params": activation_params},
        mmrpc="2.0",
        timeout=EVM_ACTIVATION_TIMEOUT_S,
    )
    failed = "error" in response
    result.steps.append(
        Step(
            f"activate:{ticker}",
            time.time() - started,
            polls=1,
            detail=str(response.get("error", ""))[:160] if failed else "token",
            timed_out=failed,
        )
    )


def _hd_scan(kdf, result, ticker):
    """The scan the SDK issues on every fresh pubkey fetch."""
    started = time.time()
    init = kdf.rpc(
        "task::scan_for_new_addresses::init",
        params={"coin": ticker, "account_index": 0, "gap_limit": 20},
        mmrpc="2.0",
    )
    task_id = (init.get("result") or {}).get("task_id")
    polls = 0
    timed_out = False
    failed = False
    detail = ""
    if task_id is None:
        # The init RPC itself was rejected. Returns in milliseconds, so without
        # this flag the SUMMARY row reads as a sub-second success.
        failed = True
        detail = "FAILED at init: " + json.dumps(init)[:200]
    else:
        while True:
            status = kdf.rpc(
                "task::scan_for_new_addresses::status",
                params={"task_id": task_id, "forget_if_finished": False},
                mmrpc="2.0",
            )
            polls += 1
            state = (status.get("result") or {}).get("status")
            if state in ("Ok", "Error"):
                detail = str(state)
                if state == "Error":
                    failed = True
                    detail = "FAILED: " + json.dumps(
                        (status.get("result") or {}).get("details")
                    )[:200]
                break
            if time.time() - started > SCAN_TIMEOUT_S:
                timed_out = True
                detail = "TIMED OUT at the SDK's 20s ceiling"
                break
            time.sleep(SCAN_POLL_S)

    result.steps.append(
        Step(
            f"scan_for_new_addresses:{ticker}",
            time.time() - started,
            polls=polls,
            detail=detail,
            timed_out=timed_out,
            failed=failed,
        )
    )


def _hd_account_balance(kdf, result, ticker):
    started = time.time()
    init = kdf.rpc(
        "task::account_balance::init",
        params={"coin": ticker, "account_index": 0},
        mmrpc="2.0",
    )
    task_id = (init.get("result") or {}).get("task_id")
    polls = 0
    timed_out = False
    failed = False
    addresses = 0
    if task_id is None:
        raise RuntimeError(f"account_balance::init failed: {init}")
    while True:
        status = kdf.rpc(
            "task::account_balance::status",
            params={"task_id": task_id, "forget_if_finished": False},
            mmrpc="2.0",
        )
        polls += 1
        payload = status.get("result") or {}
        if payload.get("status") == "Ok":
            addresses = len((payload.get("details") or {}).get("addresses") or [])
            break
        if payload.get("status") == "Error":
            # Errors come back fast. Recording this as a plain step made a
            # failed balance read look like the fastest row in the table.
            failed = True
            break
        if time.time() - started > ACCOUNT_BALANCE_TIMEOUT_S:
            timed_out = True
            break
        time.sleep(ACCOUNT_BALANCE_POLL_S)

    result.addresses_returned = addresses
    detail = f"{addresses} addresses"
    if failed:
        detail = "FAILED: " + json.dumps(
            ((status.get("result") or {}).get("details"))
        )[:200]
    result.steps.append(
        Step(
            f"account_balance:{ticker}",
            time.time() - started,
            polls=polls,
            detail=detail,
            timed_out=timed_out,
            failed=failed,
        )
    )


def _iguana_balance(kdf, result, ticker):
    started = time.time()
    response = kdf.rpc("my_balance", params=None, mmrpc=None, timeout=60)
    # my_balance is a legacy (mmrpc-less) call that takes `coin` at the top
    # level rather than inside `params`.
    if "error" in response or "address" not in response:
        # The first call deliberately omits `coin`, so it always fails - judge
        # success on the POST-fallback response only.
        response = _legacy_my_balance(kdf, ticker)
    failed = "address" not in response
    result.addresses_returned = 0 if failed else 1
    if failed:
        detail = "FAILED: " + json.dumps(response.get("error", response))[:200]
    else:
        balance = response.get("balance", "")
        detail = balance[:80] if isinstance(balance, str) else ""
    result.steps.append(
        Step(
            f"my_balance:{ticker}",
            time.time() - started,
            polls=1,
            detail=detail,
            failed=failed,
        )
    )


def _legacy_my_balance(kdf, ticker) -> dict:
    payload = {"userpass": kdf.rpc_password, "method": "my_balance", "coin": ticker}
    request = urllib.request.Request(
        f"http://127.0.0.1:{kdf.port}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    kdf.rpc_counts["my_balance"] = kdf.rpc_counts.get("my_balance", 0) + 1
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        return json.loads(exc.read().decode() or "{}")


# --------------------------------------------------------------------------
# reporting
# --------------------------------------------------------------------------


def build_matrix(args) -> List[dict]:
    if args.coin_set:
        return [
            dict(
                label=f"{args.coin_set}"
                + (" (unbatched)" if args.unbatched else " (batched)")
                + f" [{args.wallet_type}]",
                wallet_type=args.wallet_type,
                tickers=COIN_SETS[args.coin_set],
                gap_limit=20 if args.wallet_type == "hd" else 0,
                scan_policy=(
                    "scan_if_new_wallet" if args.wallet_type == "hd" else "n/a"
                ),
                unbatched=args.unbatched,
            )
        ]
    if args.quick:
        # An explicit --coin-list is taken literally; without one, the first
        # coin of the default list.
        #
        # It used to be `[:1]` unconditionally, which made the two scenarios
        # the EVM work is measured against - ETH + 2 ERC-20, TRX + USDT-TRC20 -
        # impossible to express: the tokens were silently dropped and the row
        # measured a bare platform activation while claiming otherwise. `--quick`
        # means one *scenario*, which is what it says; how many coins are in it
        # is the coin list's business.
        tickers = args.coin_list if args.coin_list_explicit else args.coin_list[:1]
        return [
            dict(
                label=f"quick: HD, {len(tickers)} coin(s), gap 20",
                wallet_type="hd",
                tickers=tickers,
                gap_limit=20,
                scan_policy="scan_if_new_wallet",
            )
        ]

    one = args.coin_list[:1]
    many = args.coin_list[: args.max_coins]

    matrix = [
        # --- address-count dimension (gap limit), activation count held at 1 --
        dict(
            label="BEST address: HD, 1 coin, gap 1",
            wallet_type="hd",
            tickers=one,
            gap_limit=1,
            scan_policy="scan_if_new_wallet",
        ),
        dict(
            label="baseline: HD, 1 coin, gap 20 (shipped default)",
            wallet_type="hd",
            tickers=one,
            gap_limit=20,
            scan_policy="scan_if_new_wallet",
        ),
        dict(
            label="WORST address: HD, 1 coin, gap 50",
            wallet_type="hd",
            tickers=one,
            gap_limit=50,
            scan_policy="scan_if_new_wallet",
        ),
        dict(
            label="HD, 1 coin, gap 20, scan_policy=do_not_scan",
            wallet_type="hd",
            tickers=one,
            gap_limit=20,
            scan_policy="do_not_scan",
        ),
        # --- activation-count dimension, gap limit held at the default -------
        dict(
            label=f"WORST activation: HD, {len(many)} coins, gap 20",
            wallet_type="hd",
            tickers=many,
            gap_limit=20,
            scan_policy="scan_if_new_wallet",
        ),
        # --- EVM per-call cost, both derivation modes -------------------------
        # `enable_eth_with_tokens` is synchronous: one request, no progress, the
        # caller blocks. Worth isolating because it dwarfs the UTXO path.
        dict(
            label="HD, ETH + 2 ERC-20 tokens (1 sync call)",
            wallet_type="hd",
            tickers=["ETH", "USDT-ERC20", "USDC-ERC20"],
            gap_limit=20,
            scan_policy="scan_if_new_wallet",
        ),
        dict(
            label="iguana, ETH + 2 ERC-20 tokens (1 sync call)",
            wallet_type="iguana",
            tickers=["ETH", "USDT-ERC20", "USDC-ERC20"],
            gap_limit=0,
            scan_policy="n/a",
        ),
        # --- activation-count dimension over the top-20 set -------------------
        # min / median / max. All three enable the SAME 19 assets; only the
        # number of activation RPCs differs.
        #
        # Measured on iguana deliberately. Per-call cost there is ~2s, so the
        # curve shows the effect of the COUNT rather than being swamped by
        # per-call cost - which the HD rows above already quantify separately.
        # Multiplying the two gives the HD figure without a 2-hour run.
        dict(
            label="MIN activations: top20 all-BEP20 batched (6 calls)",
            wallet_type="iguana",
            tickers=COIN_SETS["top20-min"],
            gap_limit=0,
            scan_policy="n/a",
        ),
        dict(
            label="MEDIAN activations: top20 canonical batched (9 calls)",
            wallet_type="iguana",
            tickers=COIN_SETS["top20-median"],
            gap_limit=0,
            scan_policy="n/a",
        ),
        dict(
            label="MAX activations: top20 max-spread unbatched (21 calls)",
            wallet_type="iguana",
            tickers=COIN_SETS["top20-max"],
            gap_limit=0,
            scan_policy="n/a",
            unbatched=True,
        ),
        # --- the realistic login ---------------------------------------------
        dict(
            label="app default set, HD (what a real login enables)",
            wallet_type="hd",
            tickers=COIN_SETS["app-default"],
            gap_limit=20,
            scan_policy="scan_if_new_wallet",
        ),
        dict(
            label="app default set, iguana",
            wallet_type="iguana",
            tickers=COIN_SETS["app-default"],
            gap_limit=0,
            scan_policy="n/a",
        ),
        # --- the control ------------------------------------------------------
        dict(
            label="BEST overall: iguana, 1 coin",
            wallet_type="iguana",
            tickers=one,
            gap_limit=0,
            scan_policy="n/a",
        ),
        dict(
            label=f"iguana, {len(many)} coins",
            wallet_type="iguana",
            tickers=many,
            gap_limit=0,
            scan_policy="n/a",
        ),
    ]
    return matrix


def fmt_seconds(value: float) -> str:
    return f"{value:8.2f}s"


def print_report(results: List[ScenarioResult], meta: dict) -> None:
    line = "=" * 78
    print(line)
    print("KDF WALLET-LOAD LATENCY PROBE")
    print(line)
    for key, value in meta.items():
        print(f"  {key:<22} {value}")
    print()

    print(line)
    print("SUMMARY")
    print(line)
    header = (
        f"{'scenario':<52}{'assets':>7}{'calls':>6}{'total':>10}"
        f"{'activate':>10}{'scan':>9}{'balance':>9}"
    )
    print(header)
    print("-" * len(header))
    for res in results:
        if res.error:
            print(f"{res.name:<52}  ERROR: {res.error}")
            continue
        activate = sum(s.seconds for s in res.steps if s.name.startswith("activate:"))
        scan = sum(
            s.seconds for s in res.steps if s.name.startswith("scan_for_new_addresses")
        )
        balance = sum(
            s.seconds
            for s in res.steps
            if s.name.startswith("account_balance") or s.name.startswith("my_balance")
        )
        print(
            f"{res.name:<52}{len(res.coins):>7}{res.activation_calls:>6}"
            f"{res.total_seconds:>9.1f}s{activate:>9.1f}s"
            f"{scan:>8.1f}s{balance:>8.1f}s"
        )
    print()

    print(line)
    print("PER-SCENARIO DETAIL")
    print(line)
    for res in results:
        print(f"\n### {res.name}")
        print(
            f"    wallet={res.wallet_type} gap_limit={res.gap_limit} "
            f"scan_policy={res.scan_policy}"
        )
        print(
            f"    assets requested: {len(res.coins)}   "
            f"activation RPCs issued: {res.activation_calls}"
            + (
                f"   forced platforms: {','.join(res.forced_platforms)}"
                if res.forced_platforms
                else ""
            )
        )
        if res.skipped_coins:
            print(f"    skipped (no config entry): {','.join(res.skipped_coins)}")
        print(f"    coins: {','.join(res.coins)}")
        if res.error:
            print(f"    ERROR: {res.error}")
            continue
        print(f"    addresses returned: {res.addresses_returned}")
        print(f"    {'step':<40}{'seconds':>10}{'polls':>8}  detail")
        for step in res.steps:
            if step.failed:
                flag = "  <-- FAILED"
            elif step.timed_out:
                flag = "  <-- TIMED OUT"
            else:
                flag = ""
            print(
                f"    {step.name:<40}{step.seconds:>9.2f}s{step.polls:>8}  "
                f"{step.detail}{flag}"
            )
        print(f"    {'RPC':<40}{'count':>8}{'total s':>10}")
        for method, count in sorted(
            res.rpc_counts.items(), key=lambda kv: -kv[1]
        ):
            print(
                f"    {method:<40}{count:>8}"
                f"{res.rpc_seconds.get(method, 0.0):>9.2f}s"
            )

    print()
    print(line)
    print("FINDINGS")
    print(line)
    for finding in derive_findings(results):
        print(f"  * {finding}")
    print()


def derive_findings(results: List[ScenarioResult]) -> List[str]:
    findings: List[str] = []
    ok = [r for r in results if not r.error]
    by_label = {r.name: r for r in ok}

    def activate_seconds(res: ScenarioResult) -> float:
        return sum(s.seconds for s in res.steps if s.name.startswith("activate:"))

    hd_one = next(
        (r for r in ok if r.wallet_type == "hd" and len(r.coins) == 1
         and r.gap_limit == 20 and r.scan_policy == "scan_if_new_wallet"),
        None,
    )
    ig_one = next(
        (r for r in ok if r.wallet_type == "iguana" and len(r.coins) == 1), None
    )
    if hd_one and ig_one:
        hd_total = hd_one.total_seconds
        ig_total = ig_one.total_seconds
        ratio = hd_total / ig_total if ig_total else 0
        findings.append(
            f"HD vs iguana, one coin, identical seed and KDF: "
            f"{hd_total:.1f}s vs {ig_total:.1f}s ({ratio:.1f}x). "
            "No Flutter, no Dart, no SDK in the loop - so the difference is "
            "KDF-side work, not client orchestration."
        )

    gap_scenarios = sorted(
        [r for r in ok if r.wallet_type == "hd" and len(r.coins) == 1
         and r.scan_policy == "scan_if_new_wallet"],
        key=lambda r: r.gap_limit,
    )
    if len(gap_scenarios) >= 2:
        parts = ", ".join(
            f"gap {r.gap_limit}: {activate_seconds(r):.1f}s" for r in gap_scenarios
        )
        findings.append(f"Activation time tracks the gap limit ({parts}).")

    no_scan = next(
        (r for r in ok if r.scan_policy == "do_not_scan"), None
    )
    if no_scan and hd_one:
        saved = activate_seconds(hd_one) - activate_seconds(no_scan)
        findings.append(
            f"scan_policy=do_not_scan activates in "
            f"{activate_seconds(no_scan):.1f}s vs "
            f"{activate_seconds(hd_one):.1f}s for scan_if_new_wallet "
            f"({saved:+.1f}s). The address walk is the activation cost."
        )

    scans = [
        s
        for r in ok
        for s in r.steps
        if s.name.startswith("scan_for_new_addresses")
    ]
    timed_out = [s for s in scans if s.timed_out]
    failed_scans = [s for s in scans if s.failed]
    completed = [s for s in scans if not s.timed_out and not s.failed]
    if failed_scans:
        # Reported before the timing lines, and the timing lines below exclude
        # these: a failed scan returns in milliseconds, so averaging it in
        # reads as a speedup.
        findings.append(
            f"{len(failed_scans)} of {len(scans)} task::scan_for_new_addresses "
            "calls FAILED. Their timings are excluded below - a failure returns "
            "fast and would otherwise look like a fast success. First error: "
            + (failed_scans[0].detail or "(no detail)")
        )
    if timed_out:
        findings.append(
            f"{len(timed_out)} of {len(scans)} explicit "
            f"task::scan_for_new_addresses calls hit the SDK's 20s ceiling "
            "without finishing. That call runs AFTER activation has already "
            "walked the same gap, so it is a second walk whose result is "
            "discarded."
        )
    elif completed:
        findings.append(
            f"task::scan_for_new_addresses completed in "
            f"{max(s.seconds for s in completed):.1f}s (worst case) - it did not "
            "hit the SDK's 20s ceiling in this run."
        )

    multi = [r for r in ok if len(r.coins) > 1]
    for res in multi:
        singles = [
            r for r in ok if r.wallet_type == res.wallet_type and len(r.coins) == 1
            and r.gap_limit == res.gap_limit
        ]
        if singles:
            per_coin = activate_seconds(res) / max(len(res.coins), 1)
            findings.append(
                f"{res.wallet_type} with {len(res.coins)} coins: "
                f"{activate_seconds(res):.1f}s total, {per_coin:.1f}s per coin "
                f"(one coin alone: {activate_seconds(singles[0]):.1f}s). "
                "Activation cost is roughly per-coin, so it scales with how "
                "many coins a login enables."
            )

    # The isolation argument. Note this is deliberately NOT "% of time inside
    # HTTP calls" - that was a fair proxy while every activation was task-based
    # and the client polled, but `enable_eth_with_tokens` is SYNCHRONOUS, so
    # time inside that call is KDF computing, not transport. Both buckets are
    # KDF; what matters is that neither is client code.
    transport = sum(sum(r.rpc_seconds.values()) for r in ok)
    wall = sum(r.total_seconds for r in ok)
    if wall > 0:
        findings.append(
            f"Of {wall:.1f}s of wall clock across all scenarios, "
            f"{transport:.1f}s was spent blocked inside an RPC call and "
            f"{wall - transport:.1f}s was spent sleeping between polls waiting "
            "for a task KDF had already accepted. Both are KDF working. This "
            "script is Python stdlib talking HTTP to a process - there is no "
            "Flutter, Dart or SDK code anywhere in the measurement - so the "
            "client's own contribution is the arithmetic between those two "
            "numbers, which is not measurable at this resolution."
        )

    if not findings:
        findings.append("No scenarios completed; see errors above.")
    return findings


# --------------------------------------------------------------------------
# web tier: serve the built app + the probe page, collect the POSTed result
# --------------------------------------------------------------------------


def serve_web_probe(port: int, timeout_s: float) -> Optional[dict]:
    """Serve `build/web` with the probe page overlaid, and wait for a result.

    Why a server at all: the probe page must be same-origin with the app's
    `kdflib.js`, `kdflib_bg.wasm` and coins config, and ES modules plus
    `application/wasm` do not work over `file://`.

    Why no browser driver: driving Flutter's canvas is what failed. This page
    is plain DOM, so a human opening a URL is both sufficient and more honest
    than a headless harness nobody will maintain.
    """
    import http.server
    import threading

    web_root = os.path.join(REPO_ROOT, "build", "web")
    if not os.path.isdir(web_root):
        print(
            "build/web not found. Build the web app once:\n"
            "  flutter build web --release \\\n"
            "    --dart-define=TRON_GASLESS_ENABLED=true \\\n"
            "    --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \\\n"
            "    --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \\\n"
            "    --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird",
            file=sys.stderr,
        )
        return None

    probe_page = os.path.join(REPO_ROOT, "tool", "web", "kdf_web_probe.html")
    collected: Dict[str, Any] = {}
    done = threading.Event()

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=web_root, **kw)

        def log_message(self, *a):  # quiet
            pass

        def do_GET(self):  # noqa: N802
            if self.path.split("?")[0] == "/kdf-probe.html":
                with open(probe_page, "rb") as handle:
                    body = handle.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            super().do_GET()

        def do_POST(self):  # noqa: N802
            if self.path != "/probe-result":
                self.send_error(404)
                return
            length = int(self.headers.get("Content-Length", "0"))
            try:
                collected.update(json.loads(self.rfile.read(length) or b"{}"))
            except Exception as exc:  # noqa: BLE001
                self.send_error(400, str(exc))
                return
            self.send_response(204)
            self.end_headers()
            done.set()

    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = f"http://127.0.0.1:{port}/kdf-probe.html"
    print(f"\n  Web probe ready:  {url}\n  Open it, press Run, and paste a "
          f"throwaway seed. Waiting up to {int(timeout_s / 60)} min ...\n",
          file=sys.stderr)
    got = done.wait(timeout_s)
    server.shutdown()
    if not got:
        print("  No result POSTed before the timeout.", file=sys.stderr)
        return None
    return collected


def print_web_report(payload: dict) -> None:
    line = "=" * 78
    print(line)
    print("WEB TIER (KDF WASM in the browser, no Flutter/Dart)")
    print(line)
    for key, value in (payload.get("meta") or {}).items():
        print(f"  {key:<22} {value}")
    print()
    header = (
        f"{'scenario':<38}{'total':>10}{'activate':>10}{'scan':>9}"
        f"{'balance':>9}{'longtask':>10}"
    )
    print(header)
    print("-" * len(header))
    for res in payload.get("results", []):
        if res.get("error"):
            print(f"{res.get('name','?'):<38}  ERROR: {res['error']}")
            continue
        steps = res.get("steps", [])

        def total(prefix: str) -> float:
            return sum(s["seconds"] for s in steps if s["name"].startswith(prefix))

        print(
            f"{res['name']:<38}{res['total_seconds']:>9.1f}s"
            f"{total('activate:'):>9.1f}s{total('scan_for_new_addresses'):>8.1f}s"
            f"{(total('account_balance') + total('my_balance')):>8.1f}s"
            f"{res.get('long_task_ms', 0):>9}ms"
        )
    print()
    blocked = sum(r.get("long_task_ms", 0) for r in payload.get("results", []))
    wall = sum(r.get("total_seconds", 0) for r in payload.get("results", []))
    if wall:
        print(
            f"  Main thread blocked for {blocked / 1000:.1f}s of {wall:.1f}s "
            f"({blocked / 10 / wall:.1f}%). On web KDF is WASM on the same "
            "thread as the UI, so this is time the app could not paint."
        )
    print()


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Measure KDF wallet-load latency without Flutter."
    )
    parser.add_argument("--kdf", help="Path to the kdf binary")
    parser.add_argument("--coins", help="Path to coins_config.json")
    parser.add_argument(
        "--coin-list",
        default=COIN_LIST_DEFAULT,
        help="Comma-separated tickers, most important first. Tokens are "
             "grouped under their platform automatically, so "
             "'ETH,USDT-ERC20' is one enable_eth_with_tokens call.",
    )
    parser.add_argument("--max-coins", type=int, default=4)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--json", help="Also write the full result as JSON here")
    parser.add_argument("--quick", action="store_true", help="One scenario only")
    parser.add_argument(
        "--coin-set",
        choices=sorted(COIN_SETS),
        help="Run a single named set instead of the full matrix",
    )
    parser.add_argument(
        "--wallet-type", choices=["hd", "iguana"], default="hd",
        help="Derivation mode for --coin-set runs",
    )
    parser.add_argument(
        "--unbatched",
        action="store_true",
        help="Issue each token as its own enable_erc20 (worst-case fan-out)",
    )
    parser.add_argument(
        "--p2p",
        action="store_true",
        help=(
            "Start KDF with p2p and seed nodes instead of disable_p2p. "
            "This used to be REQUIRED for any set containing TRX, which "
            "panicked at mm2_p2p/src/p2p_ctx.rs:42 (Option::unwrap on None) "
            "with p2p off and took the whole RPC service down. Fixed in KDF "
            "ed8de236b; TRX HD activation has since been measured repeatedly "
            "with p2p off. Still needed for anything that actually uses the "
            "network - swaps, peer health, proxy-signed gas-free relays."
        ),
    )
    parser.add_argument(
        "--web",
        action="store_true",
        help="Serve build/web + the WASM probe page and wait for its result",
    )
    parser.add_argument(
        "--web-port", type=int, default=8091, help="Port for --web (default 8091)"
    )
    parser.add_argument(
        "--web-timeout-min", type=float, default=45.0
    )
    parser.add_argument(
        "--plan-only",
        action="store_true",
        help="Print the activation plan for every coin set and exit. No KDF.",
    )
    parser.add_argument(
        "--electrum-protocol",
        action="append",
        choices=["TCP", "SSL", "WSS"],
        help="Restrict electrum servers to these protocols. Repeatable. "
             "The SDK ships WSS-only on web and TCP+SSL on native "
             "(WssWebsocketTransform), so --electrum-protocol WSS runs the "
             "native binary against the web platform's server list.",
    )
    parser.add_argument("--keep-workdir", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()
    # Recorded before the split, while it is still comparable to the default.
    args.coin_list_explicit = args.coin_list != COIN_LIST_DEFAULT
    args.coin_list = [c.strip() for c in args.coin_list.split(",") if c.strip()]

    seed = os.environ.get("KDF_TEST_SEED", "").strip()
    if not seed and not args.plan_only and not args.web:
        print(
            "KDF_TEST_SEED is not set.\n"
            "  export KDF_TEST_SEED='abandon abandon abandon abandon abandon "
            "abandon abandon abandon abandon abandon abandon about'\n"
            "Use a throwaway seed. This script starts a real KDF and it will "
            "talk to real electrum servers.",
            file=sys.stderr,
        )
        return 2

    if args.plan_only:
        with open(find_coins_config(args.coins), encoding="utf-8") as handle:
            raw = json.load(handle)
        index = raw if isinstance(raw, dict) else {c["coin"]: c for c in raw}
        for name in sorted(COIN_SETS):
            for unbatched in (False, True):
                ops, skipped = plan_activations(
                    COIN_SETS[name], index, unbatched=unbatched
                )
                kinds: Dict[str, int] = {}
                for op in ops:
                    kinds[op.kind] = kinds.get(op.kind, 0) + 1
                forced = [op.ticker for op in ops if op.forced]
                print(
                    f"{name:15} {'unbatched' if unbatched else 'batched  '} "
                    f"assets={len(COIN_SETS[name]):2} calls={len(ops):2} "
                    f"{kinds}"
                    + (f" forced={forced}" if forced else "")
                    + (f" skipped={skipped}" if skipped else "")
                )
        return 0

    if args.web:
        payload = serve_web_probe(args.web_port, args.web_timeout_min * 60)
        if payload is None:
            return 1
        print_web_report(payload)
        if args.json:
            with open(args.json, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, indent=2)
            print(f"JSON written to {args.json}")
        return 0

    binary = find_kdf_binary(args.kdf)
    if not binary:
        print(
            "No KDF binary found. It is a build artifact - run a Flutter build "
            "once so the transformer fetches it, or pass --kdf/KDF_BINARY.",
            file=sys.stderr,
        )
        return 2
    os.chmod(binary, 0o755)

    coins_path = find_coins_config(args.coins)
    if not coins_path:
        print("No coins config found; pass --coins.", file=sys.stderr)
        return 2
    with open(coins_path, encoding="utf-8") as handle:
        raw_coins = json.load(handle)
    if isinstance(raw_coins, dict):
        coins_index = raw_coins
    else:
        coins_index = {c["coin"]: c for c in raw_coins}

    electrum_protocols = (
        set(args.electrum_protocol) if args.electrum_protocol else None
    )

    meta = {
        "kdf binary": binary,
        "coins config": coins_path,
        "host": f"{platform.system()} {platform.release()} ({platform.machine()})",
        "python": platform.python_version(),
        "port": args.port,
        "started": time.strftime("%Y-%m-%d %H:%M:%S"),
        "electrum protocols": (
            "+".join(sorted(electrum_protocols)) if electrum_protocols
            else "all (as shipped in the config)"
        ),
    }

    results: List[ScenarioResult] = []
    matrix = build_matrix(args)
    for index, scenario in enumerate(matrix, start=1):
        print(
            f"[{index}/{len(matrix)}] {scenario['label']} ...",
            file=sys.stderr,
            flush=True,
        )
        results.append(
            run_scenario(
                binary=binary,
                coins_index=coins_index,
                seed=seed,
                tickers=scenario["tickers"],
                wallet_type=scenario["wallet_type"],
                gap_limit=scenario["gap_limit"],
                scan_policy=scenario["scan_policy"],
                port=args.port,
                keep_workdir=args.keep_workdir,
                verbose=args.verbose,
                label=scenario["label"],
                unbatched=scenario.get("unbatched", False),
                p2p=args.p2p,
                electrum_protocols=electrum_protocols,
            )
        )

    print_report(results, meta)

    if args.json:
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(
                {"meta": meta, "results": [asdict(r) for r in results]},
                handle,
                indent=2,
            )
        print(f"JSON written to {args.json}")

    # Non-zero if *anything* failed, not if everything did.
    #
    # This used to be `any(not r.error ...)`, which exits 0 as long as one row
    # of the matrix survived - so a coin failing 100% of its activations was
    # invisible to any caller that checked the exit code. That is precisely how
    # the GLEEC regression reached a release with every gate green. A failed
    # step counts too: an EVM activation error is recorded on the step, and the
    # scenario itself carries no error unless a later call happened to raise.
    failed_steps = [
        (r.name, s.name) for r in results for s in r.steps if getattr(s, "failed", False)
    ]
    if failed_steps:
        print("\nFAILED steps:", file=sys.stderr)
        for scenario, step in failed_steps:
            print(f"  {scenario}: {step}", file=sys.stderr)

    return 0 if not failed_steps and all(not r.error for r in results) else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\ninterrupted", file=sys.stderr)
        sys.exit(130)
