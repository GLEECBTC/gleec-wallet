"""Negative packaging cases for rollback compatibility evidence."""

import unittest

from verify_packaged_readers import (
    DART_READERS, NATIVE_READERS, REQUIRED_ABIS, VerificationFailure,
    inspect_payloads,
)


def fixture():
    result = {"classes.dex": "\0".join(NATIVE_READERS).encode()}
    for abi, machine in REQUIRED_ABIS.items():
        result[f"lib/{abi}/libapp.so"] = "\0".join(DART_READERS).encode()
        header = bytearray(20)
        header[:4] = b"\x7fELF"
        header[5] = 1
        header[16:18] = (3).to_bytes(2, "little")
        header[18:20] = machine.to_bytes(2, "little")
        result[f"lib/{abi}/libkomodo_defi_framework.so"] = bytes(header) + b"mm2_main\0mm2_main_status\0mm2_stop\0"
    return result


class PackagedReadersTest(unittest.TestCase):
    def test_both_architectures_and_native_bridge_are_checked(self):
        result = inspect_payloads(fixture())
        self.assertEqual(set(result["abis"]), set(REQUIRED_ABIS))

    def test_missing_cleanup_reader_in_only_one_architecture_fails(self):
        payloads = fixture()
        key = "lib/armeabi-v7a/libapp.so"
        payloads[key] = payloads[key].replace(b"wallet_access_cleanup_v1", b"")
        with self.assertRaisesRegex(VerificationFailure, "dart_reader_missing"):
            inspect_payloads(payloads)

    def test_missing_native_reader_fails(self):
        payloads = fixture()
        payloads["classes.dex"] = payloads["classes.dex"].replace(b"prepareDelete", b"")
        with self.assertRaisesRegex(VerificationFailure, "native_reader_missing"):
            inspect_payloads(payloads)

    def test_wrong_engine_architecture_fails(self):
        payloads = fixture()
        payloads["lib/arm64-v8a/libkomodo_defi_framework.so"] = payloads["lib/armeabi-v7a/libkomodo_defi_framework.so"]
        with self.assertRaisesRegex(VerificationFailure, "bundled_native_engine"):
            inspect_payloads(payloads)

    def test_legacy_executable_marker_fails(self):
        payloads = fixture()
        payloads["lib/arm64-v8a/libapp.so"] += b"KdfOperationsLocalExecutable"
        with self.assertRaisesRegex(VerificationFailure, "legacy_executable"):
            inspect_payloads(payloads)

    def test_private_fixture_and_executable_assets_fail(self):
        for name in ("assets/debug_data.json", "assets/bin/kdf", "assets/Test.JKS"):
            with self.subTest(name=name):
                payloads = fixture()
                payloads[name] = b"unused"
                with self.assertRaisesRegex(VerificationFailure, "forbidden_packaged_file"):
                    inspect_payloads(payloads)

    def test_temporary_lifecycle_diagnostic_marker_fails(self):
        payloads = fixture()
        payloads["lib/arm64-v8a/libapp.so"] += b"wallet_rollback_lifecycle:"
        with self.assertRaisesRegex(VerificationFailure, "temporary_diagnostic"):
            inspect_payloads(payloads)

    def test_missing_native_export_fails(self):
        payloads = fixture()
        key = "lib/arm64-v8a/libkomodo_defi_framework.so"
        payloads[key] = payloads[key].replace(b"mm2_stop\0", b"")
        with self.assertRaisesRegex(VerificationFailure, "bundled_native_engine"):
            inspect_payloads(payloads)


if __name__ == "__main__":
    unittest.main()
