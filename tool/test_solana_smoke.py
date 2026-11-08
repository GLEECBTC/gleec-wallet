"""The unfunded runner must stay unable to spend, export, or reuse a wallet."""

import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import solana_smoke as smoke
from solana_candidate import REFERENCE_COINS, REFERENCE_ENGINE, create_manifest


ZERO = {"spendable": "0", "unspendable": "0"}
ADDRESS = "11111111111111111111111111111111"


def catalog():
    return [
        {"coin": smoke.PLATFORM, "is_testnet": True, "wallet_only": False,
         "protocol": {"type": "SOLANA"}},
        {"coin": smoke.TOKEN, "is_testnet": True, "protocol": {
            "type": "SOLANATOKEN", "protocol_data": {
                "platform": smoke.PLATFORM, "mint_address": smoke.TOKEN_MINT,
                "program_id": smoke.TOKEN_PROGRAM, "decimals": 6}}},
    ]


class EngineDouble:
    def __init__(self, **kwargs):
        self.calls = []
        self.rpc_counts = {}
        self.kwargs = kwargs
        self.stopped = False

    def start(self):
        pass

    def stop(self):
        self.stopped = True

    def rpc(self, method, params=None, mmrpc=None, **kwargs):
        self.calls.append((method, params, mmrpc))
        self.rpc_counts[method] = self.rpc_counts.get(method, 0) + 1
        if method == "version":
            return {"result": "2.5.0-beta_" + REFERENCE_ENGINE[:7], "datetime": "2026-01-01T00:00:00Z"}
        if method == "experimental::enable_solana_with_assets":
            return {"result": {"ticker": smoke.PLATFORM, "address": ADDRESS,
                               "current_block": 42, "balance": ZERO,
                               "tokens_balances": {smoke.TOKEN: ZERO}}}
        if method == "experimental::enable_solana_token":
            return {"result": {"ticker": smoke.TOKEN, "address": ADDRESS,
                               "current_block": 42, "balance": ZERO}}
        if method == "my_balance":
            return {"coin": params["coin"], "address": ADDRESS, "balance": "0",
                    "unspendable_balance": "0"}
        if method == "my_tx_history":
            return {"result": {"transactions": [], "sync_status": {"state": "Finished"}}}
        if method == "validateaddress":
            return {"result": {"is_valid": True}}
        if method == "disable_coin":
            return {"result": {"coin": smoke.TOKEN}}
        raise AssertionError("Unscripted RPC")


class SmokeTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.binary, self.coins = self.root / "kdf", self.root / "coins.json"
        self.binary.write_bytes(b"test artifact")
        self.coins.write_text(json.dumps(catalog()))

    def test_mnemonic_uses_bip39_checksum_and_fresh_entropy(self):
        words = Path(smoke.__file__).resolve().parent.parent / "sdk/packages/komodo_defi_types/assets/bip-0039/english-wordlist.txt"
        self.assertEqual(smoke.fresh_mnemonic(words, bytes(16)), "abandon " * 11 + "about")
        self.assertNotEqual(smoke.fresh_mnemonic(words), smoke.fresh_mnemonic(words))

    def test_genesis_is_verified_before_engine_is_started(self):
        opener = lambda *a, **kw: io.BytesIO(json.dumps({"result": smoke.DEVNET_GENESIS}).encode())
        smoke.verify_devnet("https://api.devnet.solana.com", opener)
        with self.assertRaisesRegex(smoke.SmokeFailure, "devnet identity"):
            smoke.verify_devnet("https://api.mainnet-beta.solana.com",
                                lambda *a, **kw: io.BytesIO(b'{"result":"mainnet"}'))

    def test_endpoint_rejects_userinfo_insecure_and_malformed_urls(self):
        for value in ("http://api.devnet.solana.com", "https://user:secret@example.org", "https://example.org:bad", "https://example.org/#fragment"):
            with self.subTest(value=value), self.assertRaises(smoke.SmokeFailure):
                smoke.validate_endpoint(value)

    def test_smoke_catalog_is_limited_to_wallet_only_reviewed_devnet_assets(self):
        coins = smoke.smoke_coins(self.coins)
        self.assertEqual({row["coin"] for row in coins}, {smoke.PLATFORM, smoke.TOKEN})
        self.assertTrue(all(row["wallet_only"] for row in coins))
        self.assertFalse(json.loads(self.coins.read_text())[0]["wallet_only"])

    def test_smoke_refuses_mainnet_wrong_mint_program_or_precision(self):
        changes = ((0, "is_testnet", False), (1, "mint_address", "wrong"),
                   (1, "program_id", "Token2022"), (1, "decimals", 9))
        for index, key, value in changes:
            rows = catalog()
            target = rows[index] if key == "is_testnet" else rows[index]["protocol"]["protocol_data"]
            target[key] = value
            self.coins.write_text(json.dumps(rows))
            with self.subTest(key=key), self.assertRaises(smoke.SmokeFailure):
                smoke.smoke_coins(self.coins)

    def test_spending_signing_export_and_swap_rpcs_cannot_dispatch(self):
        engine = smoke.UnfundedSolanaKdf.__new__(smoke.UnfundedSolanaKdf)
        with patch.object(smoke.urllib.request, "urlopen") as transport:
            for method in ("withdraw", "send_raw_transaction", "sign_message", "show_priv_key", "buy", "sell", "setprice", "recover_funds_of_swap"):
                with self.subTest(method=method), self.assertRaises(smoke.SmokeFailure):
                    engine.rpc(method)
            transport.assert_not_called()

    def test_rpc_envelopes_keep_legacy_flat_and_v2_nested(self):
        engine = smoke.UnfundedSolanaKdf.__new__(smoke.UnfundedSolanaKdf)
        engine.rpc_password, engine.port = "disposable", 12345
        engine.rpc_counts, engine.rpc_seconds = {}, {}
        payloads = []
        def answer(request, **kwargs):
            payloads.append(json.loads(request.data))
            return io.BytesIO(b'{}')
        with patch.object(smoke.urllib.request, "urlopen", side_effect=answer):
            engine.rpc("my_balance", {"coin": smoke.PLATFORM})
            engine.rpc("my_tx_history", {"coin": smoke.PLATFORM}, mmrpc="2.0")
        self.assertEqual(payloads[0]["coin"], smoke.PLATFORM)
        self.assertNotIn("params", payloads[0])
        self.assertEqual(payloads[1]["params"], {"coin": smoke.PLATFORM})
        self.assertEqual(payloads[1]["mmrpc"], "2.0")

    def test_contract_uses_one_owner_and_targetless_v2_history(self):
        engine = EngineDouble()
        self.assertTrue(smoke.exercise_wallet(engine, "https://api.devnet.solana.com", REFERENCE_ENGINE)["passed"])
        history = [call for call in engine.calls if call[0] == "my_tx_history"]
        self.assertEqual(len(history), 2)
        self.assertTrue(all(call[2] == "2.0" and "target" not in call[1] for call in history))
        self.assertEqual(engine.calls[1][1]["nodes"], [{"url": "https://api.devnet.solana.com"}])
        self.assertFalse(any("task::" in method for method, _, _ in engine.calls))

    def test_wrong_engine_is_refused_before_activation(self):
        engine = EngineDouble()
        with self.assertRaisesRegex(smoke.SmokeFailure, "version"):
            smoke.exercise_wallet(engine, "https://api.devnet.solana.com", "a" * 40)
        self.assertEqual(len(engine.calls), 1)

    def test_nonzero_or_malformed_balance_fails_closed(self):
        for balance in (None, {}, {"spendable": 0, "unspendable": "0"},
                        {"spendable": "NaN", "unspendable": "0"},
                        {"spendable": "0.000000001", "unspendable": "0"}):
            with self.subTest(balance=balance), self.assertRaises(smoke.SmokeFailure):
                smoke.zero_balance(balance, "SOL")

    def test_failure_closes_process_removes_workspace_and_redacts_untrusted_error(self):
        manifest = self.root / "manifest.json"
        manifest.write_text(json.dumps(create_manifest(self.binary, self.coins, REFERENCE_ENGINE, REFERENCE_COINS)))
        report = self.root / "report.json"
        engine = EngineDouble()
        def build(**kwargs):
            engine.kwargs = kwargs
            return engine
        with patch.object(smoke.socket, "socket") as socket, patch.object(smoke, "verify_devnet"), patch.object(smoke, "UnfundedSolanaKdf", side_effect=build), patch.object(smoke, "exercise_wallet", side_effect=ValueError("https://secret-provider/token wallet-seed")), patch("builtins.print"):
            socket.return_value.__enter__.return_value.getsockname.return_value = ("127.0.0.1", 12345)
            code = smoke.main(["--kdf", str(self.binary), "--coins", str(self.coins),
                               "--manifest", str(manifest), "--json", str(report)])
        self.assertEqual(code, 1)
        self.assertTrue(engine.stopped)
        self.assertFalse(Path(engine.kwargs["workdir"]).exists())
        self.assertNotIn("secret-provider", report.read_text())
        self.assertNotIn(engine.kwargs["seed"], report.read_text())


if __name__ == "__main__":
    unittest.main()
