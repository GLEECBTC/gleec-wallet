#!/usr/bin/env python3
"""Assert the pinned KDF's LI.FI quote contract using an unfunded fresh wallet.

Python standard library only. Requires generated KDF/coin assets and network
access. No existing wallet or seed is read. Only version, activation, quote and
stop RPCs are allowed. The temporary wallet, seed and engine logs are removed.
The JSON report contains assertions and public quote figures, never credentials.
"""

import argparse
import hashlib
import json
import secrets
import socket
import sys
import tempfile
from datetime import datetime, timezone
from decimal import Decimal
from pathlib import Path

from kdf_latency_probe import (
    KdfProcess,
    _evm_nodes,
    find_coins_config,
    find_kdf_binary,
)


class QuoteOnlyKdf(KdfProcess):
    """Prevent future smoke-test edits from accidentally submitting a swap."""

    def rpc(self, method, *args, **kwargs):
        if method not in {"version", "enable_eth_with_tokens", "routed_swap::quote", "stop"}:
            raise ValueError("This smoke test only permits read-only quote RPCs")
        return super().rpc(method, *args, **kwargs)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check_pair(engine, coins, native, token):
    coin = coins[native]
    params = {
        "ticker": native,
        "nodes": _evm_nodes(coin),
        "erc20_tokens_requests": [{"ticker": token, "required_confirmations": 3}],
        "priv_key_policy": {"type": "ContextPrivKey"},
        "tx_history": False,
        "get_balances": True,
    }
    for key in ("swap_contract_address", "fallback_swap_contract"):
        if coin.get(key):
            params[key] = coin[key]
    activation = engine.rpc("enable_eth_with_tokens", params, mmrpc="2.0", timeout=90)
    require("error" not in activation, "Activation failed: " + activation.get("error_type", "unknown"))

    quote_params = {"from": native, "to": token, "slippage": 0.005, "order": "cheapest"}
    exact = engine.rpc(
        "routed_swap::quote", {**quote_params, "amount": "0.05"}, mmrpc="2.0", timeout=120
    )
    require("error" not in exact, "Exact quote failed: " + exact.get("error_type", "unknown"))
    routes = exact.get("result", {}).get("routes", [])
    require(bool(routes), "Exact quote returned no route")
    route = routes[0]
    require(route["from"]["coin"] == native, "Quote changed the source asset")
    require(route["to"]["coin"] == token, "Quote changed the destination asset")
    require(Decimal(route["from"]["amount"]) == Decimal("0.05"), "Quote changed the exact amount")
    minimum = Decimal(route["to"]["amount_min"])
    require(0 < minimum <= Decimal(route["to"]["amount"]), "Invalid quoted minimum")
    gas = route["total_gas_costs"]
    require(bool(gas), "Quote omitted total gas funding")
    for fee in gas:
        require(Decimal(fee["required_balance"]) >= Decimal(fee["amount"]) >= 0,
                "Gas funding must cover the estimate without changing estimated spending")
    commission = [fee for fee in route["fee_costs"] if fee["name"] == "LIFI Fixed Fee"]
    require(len(commission) == 1, "Expected one combined included LI.FI commission")
    fee = commission[0]
    require(fee["included"] is True and fee["coin"] == native,
            "Commission must be included in the source amount")
    # A test assertion, not a second deduction or a production fee calculator.
    require(Decimal(fee["amount"]) == Decimal("0.05") * Decimal("0.02"),
            "Commission does not match the configured 178 + 22 bps")

    maximum = engine.rpc(
        "routed_swap::quote", {**quote_params, "max": True}, mmrpc="2.0", timeout=120
    )
    require(maximum.get("error_type") == "InsufficientBalance",
            "An unfunded Max must return typed InsufficientBalance")
    shortfall = maximum["error_data"]
    require(shortfall["coin"] == native and Decimal(shortfall["available"]) == 0,
            "Max shortfall must name the unfunded native asset")
    require(Decimal(shortfall["required"]) > 0, "Max shortfall must state the required balance")
    if "locked_by_swaps" in shortfall:
        require(Decimal(shortfall["locked_by_swaps"]) == 0,
                "Fresh wallet unexpectedly has atomic commitments")
    return {
        "pair": [native, token],
        "fee_model": coin.get("fee_model", "standard"),
        "exact_amount": route["from"]["amount"],
        "receive": route["to"]["amount"],
        "minimum": route["to"]["amount_min"],
        "gas_funding": gas,
        "included_commission": fee,
        "max_error": {"error_type": maximum["error_type"], "error_data": shortfall},
        "passed": True,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kdf", help="Native KDF binary; defaults to generated repo assets")
    parser.add_argument("--coins", help="Coins configuration; defaults to generated repo assets")
    parser.add_argument("--json", type=Path, help="Write a credential-free report")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    manifest = json.loads((root / "sdk/packages/komodo_defi_framework/app_build/build_config.json").read_text())
    report = {
        "tested_at": datetime.now(timezone.utc).isoformat(),
        "engine_commit": manifest["api"]["api_commit_hash"],
        "coins_commit": manifest["coins"]["bundled_coins_repo_commit"],
        "proxy": "https://quicknode.gleec.com/lifi",
        "integrator": {"name": "gleec-dex-staging", "fee_bps": 178, "lifi_fee_bps": 22},
        "scope": "fresh unfunded wallet; version, activation, quote and stop only",
        "checks": [],
        "passed": False,
    }
    try:
        binary, coins_path = find_kdf_binary(args.kdf), find_coins_config(args.coins)
        require(binary is not None and coins_path is not None, "Generate the native KDF and coin assets first")
        coins_bytes = Path(coins_path).read_bytes()
        report["coins_config_sha256"] = hashlib.sha256(coins_bytes).hexdigest()
        coins = json.loads(coins_bytes)
        # Mirror the SDK's missing-only transform for this direct-engine check.
        # SDK tests separately verify all four models and cached startup.
        coins["ETH-BASE"].setdefault("fee_model", "op_stack")
        with tempfile.TemporaryDirectory(prefix="lifi-quote-smoke-") as work:
            with socket.socket() as sock:
                sock.bind(("127.0.0.1", 0))
                port = sock.getsockname()[1]
            engine = QuoteOnlyKdf(
                binary=binary, coins=list(coins.values()), seed=secrets.token_hex(32),
                rpc_password=secrets.token_hex(32) + "Aa1!", port=port,
                wallet_name="lifi-quote-smoke", wallet_password=secrets.token_hex(32) + "Aa1!",
                enable_hd=False, workdir=work, p2p=True,
            )
            engine.config.update({"lifi_proxy_url": report["proxy"], "lifi_integrator": report["integrator"]})
            try:
                report["phase"] = "startup"
                engine.start()
                report["phase"] = "version"
                version = engine.rpc("version")["result"]
                require(version.endswith("_" + report["engine_commit"][:7]), "Engine version does not match manifest")
                report["version"] = version
                for native, token in [("ETH-ARB20", "USDC-ARB20"), ("ETH-BASE", "USDC-BASE")]:
                    report["phase"] = f"quote {native} -> {token}"
                    report["checks"].append(check_pair(engine, coins, native, token))
                    print(f"PASS {native} -> {token}: exact, included fee, funding, unfunded Max", flush=True)
            finally:
                engine.stop()
        report["phase"] = "complete"
        report["passed"] = True
    except Exception as error:
        # Do not dump a response, process argv, configuration or engine log.
        report["failure_type"] = type(error).__name__
        report["failure"] = str(error) if isinstance(error, (ValueError, RuntimeError)) else "Engine/network check failed"
        print("FAIL: " + report["failure"], file=sys.stderr)
    finally:
        if args.json:
            args.json.write_text(json.dumps(report, indent=2) + "\n")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
