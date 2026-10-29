"""Local regression checks for the unfunded quote runner; never starts KDF."""
import unittest
from unittest.mock import patch

from kdf_lifi_quote_smoke import QuoteOnlyKdf, random_kdf_password


class QuoteSmokeTest(unittest.TestCase):
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
