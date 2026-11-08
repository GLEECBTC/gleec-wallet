"""Offline regression checks for immutable, isolated candidate profiles."""

import json
import tempfile
import unittest
from pathlib import Path

from solana_candidate import (
    CandidateFailure, REFERENCE_COINS, REFERENCE_ENGINE, create_manifest,
    load_verified_manifest, main, preview_defines,
)


class CandidateTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.binary, self.coins = self.root / "kdf", self.root / "coins.json"
        self.binary.write_bytes(b"isolated test artifact")
        self.coins.write_text("{}")
        self.manifest = create_manifest(self.binary, self.coins, REFERENCE_ENGINE, REFERENCE_COINS)
        self.path = self.root / "manifest.json"
        self.save()

    def save(self):
        self.path.write_text(json.dumps(self.manifest))

    def test_round_trip_binds_full_commits_and_both_exact_artifacts(self):
        self.assertEqual(load_verified_manifest(self.path, self.binary, self.coins), self.manifest)
        self.binary.write_bytes(b"different engine")
        with self.assertRaisesRegex(CandidateFailure, "binary.*digest"):
            load_verified_manifest(self.path, self.binary, self.coins)

    def test_even_catalog_whitespace_changes_require_a_new_manifest(self):
        self.coins.write_text("{}\n")
        with self.assertRaisesRegex(CandidateFailure, "snapshot.*digest"):
            load_verified_manifest(self.path, self.binary, self.coins)

    def test_short_or_non_hex_commits_are_rejected(self):
        for value in (REFERENCE_ENGINE[:7], "z" * 40, REFERENCE_ENGINE.upper(), None):
            with self.subTest(value=value), self.assertRaises(CandidateFailure):
                create_manifest(self.binary, self.coins, value, REFERENCE_COINS)

    def test_release_manifest_cannot_run_as_an_isolated_candidate(self):
        self.manifest["production_ready"] = True
        self.save()
        with self.assertRaisesRegex(CandidateFailure, "isolated development"):
            load_verified_manifest(self.path, self.binary, self.coins)

    def test_profile_pins_snapshot_and_keeps_unverified_capabilities_off(self):
        defines = preview_defines(self.manifest, "http://localhost:18471/")
        self.assertTrue(defines["SOLANA_ENABLED"])
        for key in ("SOLANA_SPL_MAX_ENABLED", "SOLANA_TOKEN_2022_ENABLED", "SOLANA_DEVNET_TRADING_ENABLED"):
            self.assertFalse(defines[key])
        self.assertEqual(defines["SOLANA_PREVIEW_ORIGIN"], "http://localhost:18471")
        self.assertEqual(defines["SOLANA_CATALOG_SHA256"], self.manifest["coins_snapshot_sha256"])
        self.assertEqual(defines["KDF_COINS_STORAGE_NAMESPACE"], "solana-preview-" + self.manifest["coins_snapshot_sha256"][:12])

    def test_profile_rejects_shared_default_origin_credentials_and_paths(self):
        for origin in ("https://wallet.example", "https://u:p@localhost:18471", "http://localhost:18471/wallet", "file:///tmp/app"):
            with self.subTest(origin=origin), self.assertRaises(CandidateFailure):
                preview_defines(self.manifest, origin)

    def test_cli_does_not_overwrite_existing_manifest(self):
        before = self.path.read_bytes()
        with self.assertRaises(CandidateFailure):
            main(["--kdf", str(self.binary), "--coins", str(self.coins),
                  "--engine-commit", REFERENCE_ENGINE, "--coins-base-commit", REFERENCE_COINS,
                  "--output", str(self.path)])
        self.assertEqual(self.path.read_bytes(), before)

    def test_cli_rejects_shared_outputs_before_writing_anything(self):
        target = self.root / "new.json"
        with self.assertRaisesRegex(CandidateFailure, "separate output"):
            main(["--kdf", str(self.binary), "--coins", str(self.coins),
                  "--engine-commit", REFERENCE_ENGINE, "--coins-base-commit", REFERENCE_COINS,
                  "--output", str(target), "--defines-output", str(target),
                  "--preview-origin", "http://localhost:18471"])
        self.assertFalse(target.exists())


if __name__ == "__main__":
    unittest.main()
