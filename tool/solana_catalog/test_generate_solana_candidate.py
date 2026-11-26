from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import generate_solana_candidate as candidate


@unittest.skipUnless(os.environ.get("SOLANA_COINS_REPO"), "Set SOLANA_COINS_REPO to the pinned coins checkout")
class PreviewCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.repo = Path(os.environ["SOLANA_COINS_REPO"]).resolve()
        utils = str(cls.repo / "utils")
        sys.path.insert(0, utils)
        cls.addClassCleanup(sys.path.remove, utils)

        import generate_app_configs
        import solana_registry

        cls.generator = generate_app_configs
        cls.registry = solana_registry
        cls.coins = {coin["coin"]: coin for coin in json.loads((cls.repo / "coins").read_text())}

    def test_candidate_rejects_missing_parent(self):
        with patch.object(candidate.json, "load", return_value=[self.coins["TESTUSDC-TESTSOL"]]):
            with self.assertRaisesRegex(ValueError, "parent must exist"):
                candidate.candidate_catalog(self.repo)

    def test_candidate_outputs_are_reproducible_and_swaps_are_testnet_only(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            manifest = candidate.write_candidate(self.repo, output)
            files = {path.name: path.read_bytes() for path in output.iterdir()}
            committed = {path.name: path.read_bytes() for path in candidate.FIXTURES.iterdir()}
            self.assertEqual(files, committed)
            self.assertFalse(manifest["nodes_verified_during_generation"])
            self.assertTrue(manifest["requires_isolated_storage_namespace"])
            swap = json.loads(files["swap_coins_config.json"])
            self.assertEqual(set(swap), {"TESTSOL", "TESTUSDC-TESTSOL", "MARTY"})
            for coin in swap.values():
                self.assertTrue(coin["is_testnet"])
                self.assertFalse(coin["wallet_only"])
            for name, digest in manifest["sha256"].items():
                self.assertEqual(hashlib.sha256(files[name]).hexdigest(), digest)
            candidate.write_candidate(self.repo, output)
            self.assertEqual(files, {path.name: path.read_bytes() for path in output.iterdir()})

    def test_curated_utxo_uses_existing_testnet_metadata_and_nodes(self):
        coins, configs = candidate.curated_utxo_catalog(self.repo)
        self.assertEqual(coins, [self.coins["MARTY"]])
        existing = json.loads((self.repo / "utils/coins_config.json").read_text())["MARTY"]
        self.assertEqual(configs, {"MARTY": existing})
        self.assertTrue(configs["MARTY"]["is_testnet"])
        self.assertEqual(configs["MARTY"]["protocol"]["type"], "UTXO")

    def test_curated_utxo_rejects_missing_or_wrong_network_metadata(self):
        _, configs = candidate.curated_utxo_catalog(self.repo)
        marty = [self.coins["MARTY"]]
        cases = [([], configs), (marty, {})]
        for field, value in [("is_testnet", False), ("wallet_only", True),
                             ("protocol", {"type": "ETH"}), ("pubtype", 0)]:
            config = deepcopy(configs)
            config["MARTY"][field] = value
            cases.append((marty, config))
        for registry, generated in cases:
            with self.subTest(registry=registry, generated=generated):
                with patch.object(candidate.json, "load", side_effect=[registry, generated]):
                    with self.assertRaises(ValueError):
                        candidate.curated_utxo_catalog(self.repo)

    def test_curated_utxo_rejects_unknown_disabled_or_missing_browser_nodes(self):
        _, configs = candidate.curated_utxo_catalog(self.repo)
        source_nodes = json.loads((self.repo / "electrums/MARTY").read_text())
        unknown = deepcopy(configs)
        unknown["MARTY"]["electrum"][0]["url"] = "unreviewed.example:20021"
        missing_web = deepcopy(configs)
        missing_web["MARTY"]["electrum"] = [
            node for node in missing_web["MARTY"]["electrum"] if node["protocol"] != "WSS"
        ]
        disabled = [{**node, "disabled": ["WSS"]} for node in source_nodes]
        cases = [(unknown, source_nodes), (missing_web, source_nodes), (configs, disabled)]
        for generated, nodes in cases:
            with self.subTest(generated=generated, nodes=nodes):
                with patch.object(candidate.json, "load",
                                  side_effect=[[self.coins["MARTY"]], generated, nodes]):
                    with self.assertRaisesRegex(ValueError, "configured native SSL and browser WSS"):
                        candidate.curated_utxo_catalog(self.repo)

    def test_swap_fixture_keeps_utxo_on_native_and_browser_and_wallet_solana_gated(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(self.generator, "script_path", directory):
            output = Path(directory)
            candidate.write_candidate(self.repo, output)
            swap = json.loads((output / "swap_coins_config.json").read_text())
            native = self.generator.filter_ssl(deepcopy(swap))
            browser = self.generator.filter_wss(deepcopy(swap))
            wallet = json.loads((output / "coins_config.json").read_text())
        self.assertEqual(set(native), {"TESTSOL", "TESTUSDC-TESTSOL", "MARTY"})
        self.assertEqual(set(browser), set(native))
        self.assertTrue(all(node["protocol"] == "SSL" for node in native["MARTY"]["electrum"]))
        self.assertTrue(all(node["protocol"] == "WSS" for node in browser["MARTY"]["electrum"]))
        self.assertEqual(set(wallet), {"SOL", "USDC-SOL", "TESTSOL", "TESTUSDC-TESTSOL"})
        self.assertTrue(all(coin["wallet_only"] for coin in wallet.values()))

    def test_verification_manifest_does_not_claim_utxo_snapshot_was_live_checked(self):
        now = 2000000000
        report = {}
        for ticker in ("SOL", "TESTSOL"):
            source = self.registry.load_node_config(self.repo, ticker)
            report[ticker] = {"ssl": {
                node["url"]: {"result": "Passed", "last_connection": now, "genesis_hash": source["genesis_hash"]}
                for node in source["rpc_nodes"]
            }}
        with tempfile.TemporaryDirectory() as directory, patch.object(
                self.registry, "scan_solana", return_value=report) as scan, patch.object(
                self.registry.time, "time", return_value=now):
            manifest = candidate.write_candidate(self.repo, directory, verify_nodes=True)
        scan.assert_called_once_with(self.repo)
        self.assertTrue(manifest["solana_nodes_verified_during_generation"])
        self.assertFalse(manifest["utxo_nodes_verified_during_generation"])
        self.assertFalse(manifest["nodes_verified_during_generation"])

    def test_candidate_verify_nodes_refuses_failed_live_probe(self):
        with patch.object(self.registry, "scan_solana", return_value={}):
            with self.assertRaisesRegex(ValueError, "node validation failed"):
                candidate.candidate_catalog(self.repo, verify_nodes=True)


if __name__ == "__main__":
    unittest.main()
