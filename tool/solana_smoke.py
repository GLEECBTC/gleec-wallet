#!/usr/bin/env python3
"""Opt-in, unfunded native Solana contract smoke for an isolated KDF candidate.

Only activation, read, disable and stop RPCs are permitted. Every wallet uses a
new random mnemonic; existing wallet files and seed environment variables are
never read. Temporary wallet data and logs are deleted, including after errors.
The manifest binds the candidate binary and catalog independently of production.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import socket
import sys
import tempfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from urllib.parse import urlsplit

from kdf_latency_probe import KdfProcess
from solana_candidate import CandidateFailure, load_verified_manifest, matches_engine_version


# Official cluster identity, not the illustrative getGenesisHash RPC example:
# https://beta.docs.solanalabs.com/clusters/available
DEVNET_GENESIS = "EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG"
PLATFORM = "SOL-DEV"
TOKEN = "USDC-SOL-DEV"
TOKEN_MINT = "4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU"
TOKEN_PROGRAM = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA"
_ALLOWED_METHODS = frozenset({
    "version", "stop", "experimental::enable_solana_with_assets",
    "experimental::enable_solana_token", "my_balance", "my_tx_history",
    "validateaddress", "disable_coin",
})


class SmokeFailure(ValueError):
    """A diagnostic authored locally, safe to include in an evidence report."""


def check(condition, message):
    if not condition:
        raise SmokeFailure(message)


def fresh_mnemonic(wordlist: Path, entropy: bytes | None = None) -> str:
    """Generate BIP39 from random 128-bit entropy without an extra dependency."""
    words = wordlist.read_text(encoding="utf-8").splitlines()
    check(len(words) == 2048 and len(set(words)) == 2048,
          "Bundled BIP39 word list is invalid")
    entropy = secrets.token_bytes(16) if entropy is None else entropy
    check(len(entropy) == 16, "Smoke mnemonic requires 128-bit entropy")
    value = (int.from_bytes(entropy, "big") << 4) | (hashlib.sha256(entropy).digest()[0] >> 4)
    return " ".join(words[(value >> (11 * offset)) & 2047]
                    for offset in reversed(range(12)))


def fresh_secret():
    while True:
        value = secrets.token_hex(32) + "Aa1!"
        if not re.search(r"(.)\1\1", value, re.IGNORECASE):
            return value


def validate_endpoint(url: str) -> None:
    try:
        parsed = urlsplit(url)
        port = parsed.port
        valid = (parsed.scheme == "https" and parsed.hostname
                 and parsed.username is None and parsed.password is None
                 and not parsed.fragment and not any(c.isspace() for c in url)
                 and (port is None or 0 < port <= 65535))
    except ValueError:
        valid = False
    check(valid, "Devnet endpoint must be a valid HTTPS URL without userinfo or fragment")


def verify_devnet(url: str, opener=urllib.request.urlopen) -> None:
    validate_endpoint(url)
    request = urllib.request.Request(
        url, data=json.dumps({"jsonrpc": "2.0", "id": 1,
                             "method": "getGenesisHash"}).encode(),
        headers={"Content-Type": "application/json"},
    )
    with opener(request, timeout=20) as response:
        data = json.load(response)
    check(isinstance(data, dict) and data.get("result") == DEVNET_GENESIS,
          "Endpoint did not prove Solana devnet identity")


def smoke_coins(path: Path) -> list[dict]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(data, dict):
        data = list(data.values())
    check(isinstance(data, list), "Coin snapshot must be an object or array")
    selected = {}
    for coin in data:
        if isinstance(coin, dict) and coin.get("coin") in {PLATFORM, TOKEN}:
            check(coin["coin"] not in selected, "Coin snapshot repeats a smoke asset")
            selected[coin["coin"]] = dict(coin)
    check(set(selected) == {PLATFORM, TOKEN}, "Candidate snapshot lacks the two devnet assets")
    for coin in selected.values():
        check(coin.get("is_testnet") is True, "Smoke assets must explicitly be testnet assets")
        coin["wallet_only"] = True
    check(selected[PLATFORM].get("protocol", {}).get("type") == "SOLANA",
          "Native smoke asset is not Solana")
    protocol = selected[TOKEN].get("protocol", {})
    metadata = protocol.get("protocol_data", {})
    check(protocol.get("type") == "SOLANATOKEN"
          and metadata.get("platform") == PLATFORM
          and metadata.get("mint_address") == TOKEN_MINT
          and metadata.get("program_id") == TOKEN_PROGRAM
          and metadata.get("decimals") == 6,
          "Smoke token differs from the reviewed classic devnet USDC configuration")
    return [selected[PLATFORM], selected[TOKEN]]


class UnfundedSolanaKdf(KdfProcess):
    """Reject fund-moving or secret-export operations before HTTP dispatch."""

    def rpc(self, method, params=None, mmrpc=None, timeout=30.0, count=True):
        check(method in _ALLOWED_METHODS, "RPC is outside the unfunded smoke allowlist")
        check(params is None or (isinstance(params, dict)
              and not {"method", "userpass", "mmrpc", "params"}.intersection(params)),
              "RPC parameters cannot override the unfunded smoke request envelope")
        payload = {"userpass": self.rpc_password, "method": method}
        if mmrpc is not None:
            payload.update({"mmrpc": mmrpc, "params": params or {}})
        elif params:
            payload.update(params)
        request = urllib.request.Request(
            f"http://127.0.0.1:{self.port}", data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json"},
        )
        started = time.monotonic()
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                raw = response.read()
        except urllib.error.HTTPError as error:
            raw = error.read()
        if count:
            self.rpc_counts[method] = self.rpc_counts.get(method, 0) + 1
            self.rpc_seconds[method] = self.rpc_seconds.get(method, 0) + time.monotonic() - started
        return json.loads(raw)


def result_of(response, phase):
    check(isinstance(response, dict) and "error" not in response
          and "error_type" not in response,
          f"KDF rejected {phase}; raw responses are omitted from reports")
    result = response.get("result", response)
    check(isinstance(result, dict), f"KDF returned an invalid {phase} response")
    return result


def zero_balance(balance, phase):
    check(isinstance(balance, dict), f"Missing {phase} balance")
    try:
        zero = (isinstance(balance["spendable"], str)
                and isinstance(balance["unspendable"], str)
                and Decimal(balance["spendable"]) == 0
                and Decimal(balance["unspendable"]) == 0)
    except (KeyError, TypeError, ValueError, InvalidOperation):
        zero = False
    check(zero, f"Fresh wallet did not report a valid zero {phase} balance")


def exercise_wallet(engine, endpoint, commit):
    version = engine.rpc("version").get("result")
    check(matches_engine_version(version, commit),
          "Running KDF version does not match the candidate manifest")
    params = {"ticker": PLATFORM, "nodes": [{"url": endpoint}],
              "tokens_params": [{"ticker": TOKEN}], "tx_history": True}
    activated = result_of(engine.rpc("experimental::enable_solana_with_assets", params,
                                     mmrpc="2.0", timeout=90), "platform activation")
    check(activated.get("ticker") == PLATFORM and isinstance(activated.get("address"), str),
          "Platform activation omitted ticker or address")
    check(isinstance(activated.get("current_block"), int), "Activation omitted slot")
    zero_balance(activated.get("balance"), "SOL")
    zero_balance(activated.get("tokens_balances", {}).get(TOKEN), "USDC")
    address = activated["address"]
    for ticker in (PLATFORM, TOKEN):
        balance = result_of(engine.rpc("my_balance", {"coin": ticker}), "balance")
        check(balance.get("address") == address, "SOL and SPL must share the owner address")
        zero_balance({"spendable": balance.get("balance"),
                      "unspendable": balance.get("unspendable_balance")}, ticker)
        history = result_of(engine.rpc("my_tx_history", {"coin": ticker, "limit": 10},
                                       mmrpc="2.0"), "v2 history")
        check(isinstance(history.get("transactions"), list)
              and isinstance(history.get("sync_status"), dict),
              "History omitted its transactions or synchronization status")
    valid = result_of(engine.rpc("validateaddress", {"coin": PLATFORM, "address": address}),
                      "address validation")
    check(valid.get("is_valid") is True, "Engine rejected its own Solana address")
    result_of(engine.rpc("disable_coin", {"coin": TOKEN}), "token deactivation")
    token = result_of(engine.rpc("experimental::enable_solana_token",
                                {"ticker": TOKEN, "activation_params": {}}, mmrpc="2.0"),
                      "later token activation")
    check(token.get("ticker") == TOKEN and token.get("address") == address,
          "Later token activation changed owner or ticker")
    check(isinstance(token.get("current_block"), int), "Later token activation omitted slot")
    zero_balance(token.get("balance"), "later USDC")
    return {"version": version, "passed": True, "_owner_address": address,
            "checks": ["platform_and_token_activation", "zero_balances", "shared_owner_address",
                       "v2_history", "address_validation", "later_token_activation"],
            "rpc_counts": dict(engine.rpc_counts)}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kdf", type=Path, default=os.environ.get("KDF_BINARY"))
    parser.add_argument("--coins", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--wallet-type", choices=("hd", "iguana", "both"), default="both")
    parser.add_argument("--json", type=Path)
    args = parser.parse_args(argv)
    report = {"tested_at": datetime.now(timezone.utc).isoformat(), "passed": False,
              "scope": "fresh unfunded devnet wallets; no signing, submission, or swaps",
              "wallets": []}
    try:
        check(args.kdf is not None and args.kdf.is_file(), "Set KDF_BINARY or --kdf to a candidate binary")
        report["phase"] = "candidate_verification"
        manifest = load_verified_manifest(args.manifest, args.kdf, args.coins)
        report.update({key: manifest[key] for key in (
            "engine_commit", "engine_binary_sha256", "coins_base_commit", "coins_snapshot_sha256")})
        coins = smoke_coins(args.coins)
        endpoint = os.environ.get("SOLANA_DEVNET_RPC_URL", "https://api.devnet.solana.com")
        report["phase"] = "devnet_identity"
        verify_devnet(endpoint)
        root = Path(__file__).resolve().parent.parent
        words = root / "sdk/packages/komodo_defi_types/assets/bip-0039/english-wordlist.txt"
        modes = ("hd", "iguana") if args.wallet_type == "both" else (args.wallet_type,)
        # A single disposable mnemonic makes the two derivation modes directly
        # comparable. It is never read from environment, printed, or persisted
        # outside the temporary process workspace.
        seed = fresh_mnemonic(words)
        owners = []
        for mode in modes:
            report["phase"] = f"{mode}_wallet"
            with tempfile.TemporaryDirectory(prefix="solana-unfunded-") as work:
                with socket.socket() as sock:
                    sock.bind(("127.0.0.1", 0))
                    port = sock.getsockname()[1]
                engine = UnfundedSolanaKdf(
                    binary=str(args.kdf.resolve()), coins=coins, seed=seed,
                    rpc_password=fresh_secret(), port=port, wallet_name="solana-smoke",
                    wallet_password=fresh_secret(), enable_hd=mode == "hd", workdir=work,
                )
                try:
                    engine.start()
                    result = exercise_wallet(engine, endpoint, manifest["engine_commit"])
                    owners.append(result.pop("_owner_address"))
                    report["wallets"].append({"mode": mode, **result})
                finally:
                    engine.stop()
        if len(owners) == 2:
            check(owners[0] != owners[1], "HD and Iguana derivation unexpectedly resolved the same owner")
            report["distinct_derivation_verified"] = True
        report.update({"passed": True, "phase": "complete"})
    except Exception as error:
        report["failure_type"] = type(error).__name__
        # Never echo provider URLs, raw RPCs, engine logs, process argv or seeds.
        report["failure"] = str(error) if isinstance(error, (SmokeFailure, CandidateFailure)) else "Engine or network check failed"
    if args.json:
        args.json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("PASS Solana unfunded contract smoke" if report["passed"]
          else "FAIL Solana unfunded smoke: " + report["failure"])
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
