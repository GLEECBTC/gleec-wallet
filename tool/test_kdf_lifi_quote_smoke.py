"""Local regression checks for the unfunded quote runner; never starts KDF."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from kdf_lifi_quote_smoke import QuoteOnlyKdf, deployment_config, random_kdf_password


class QuoteSmokeTest(unittest.TestCase):
    def test_production_preflight_uses_the_public_build_policy(self):
        path = Path(__file__).resolve().parent.parent / "docs/LIFI_PRODUCTION_BUILD_DEFINES.json"
        config = deployment_config(path)
        self.assertEqual(config["integrator"],
                         {"name": "gleec-dex-production", "fee_bps": 178, "lifi_fee_bps": 22})
        self.assertEqual(config["proxy"], "https://quicknode.gleec.com/lifi")
        self.assertEqual(deployment_config()["integrator"]["name"], "gleec-dex-staging")

    def test_rejects_credentials_and_wrong_fee_policy_before_startup(self):
        path = Path(__file__).resolve().parent.parent / "docs/LIFI_PRODUCTION_BUILD_DEFINES.json"
        valid = json.loads(path.read_text())
        for overrides in [
            {"LIFI_API_KEY": "not-a-real-key"},
            {"LIFI_PROXY_URL": "https://user:not-a-real-key@example.com/lifi"},
            {"LIFI_PROXY_URL": "https://example.com/lifi?api_key=not-a-real-key"},
            {"LIFI_PROXY_URL": "https://example.com/lifi?"},
            {"LIFI_PROXY_URL": "https://example.com/lifi#"},
            {"LIFI_PROXY_URL": "https://example.com:invalid/lifi"},
            {"LIFI_PROXY_URL": " https://example.com/lifi"},
            {"LIFI_PROXY_URL": "http://example.com/lifi"},
            {"LIFI_FEE_BPS": "25"},
            {"LIFI_INTEGRATOR_ENABLED": "false"},
        ]:
            with self.subTest(fields=list(overrides)), tempfile.TemporaryDirectory() as work:
                candidate = Path(work) / "public.json"
                candidate.write_text(json.dumps({**valid, **overrides}))
                with self.assertRaises(ValueError) as caught:
                    deployment_config(candidate)
                self.assertNotIn("not-a-real-key", str(caught.exception))

    def test_rejects_repetition_in_random_password_and_suffix_boundary(self):
        with patch("kdf_lifi_quote_smoke.secrets.token_hex", side_effect=[
            "111" + "ab" * 30 + "a", "bc" * 31 + "aa", "ab" * 32,
        ]) as random:
            self.assertEqual(random_kdf_password(), "ab" * 32 + "Aa1!")
            self.assertEqual(random.call_count, 3)

    def test_fund_committing_methods_are_rejected_before_transport(self):
        engine = object.__new__(QuoteOnlyKdf)
        for method in ["task::routed_swap::init", "withdraw", "send_raw_transaction", "approve"]:
            with self.subTest(method=method), self.assertRaises(ValueError):
                engine.rpc(method)


if __name__ == "__main__":
    unittest.main()
