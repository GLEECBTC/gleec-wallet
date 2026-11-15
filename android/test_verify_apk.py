"""Regression tests for unsupported or incomplete native APK distributions."""

from pathlib import Path
import tempfile
import unittest
import warnings
import zipfile

from verify_apk import ApkValidationError, verify_apk


class VerifyApkTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.apk = Path(self.directory.name) / "wallet.apk"
        self.entries = {"AndroidManifest.xml": b"manifest-content"}
        for abi in ("arm64-v8a", "armeabi-v7a"):
            for library in ("libapp.so", "libflutter.so", "libkomodo_defi_framework.so"):
                self.entries[f"lib/{abi}/{library}"] = b"native-library-content"

    def write_apk(self):
        with zipfile.ZipFile(self.apk, "w", compression=zipfile.ZIP_STORED) as archive:
            for name, data in self.entries.items():
                archive.writestr(name, data)

    def test_accepts_complete_wallet_and_additional_plugin_libraries(self):
        self.entries["lib/arm64-v8a/libbarhopper_v3.so"] = b"plugin"
        self.entries["assets/flutter_assets/AssetManifest.bin"] = b"assets"
        self.write_apk()
        verify_apk(self.apk)

    def test_rejects_x86_even_when_flutter_for_x86_is_present(self):
        self.entries["lib/x86_64/libflutter.so"] = b"flutter"
        self.entries["lib/x86_64/libapp.so"] = b"aot"
        self.write_apk()
        with self.assertRaisesRegex(ApkValidationError, "unsupported: x86_64"):
            verify_apk(self.apk)

    def test_rejects_an_omitted_supported_architecture(self):
        self.entries = {
            name: data
            for name, data in self.entries.items()
            if not name.startswith("lib/armeabi-v7a/")
        }
        self.write_apk()
        with self.assertRaisesRegex(ApkValidationError, "missing: armeabi-v7a"):
            verify_apk(self.apk)

    def test_rejects_each_missing_runtime_library(self):
        required = [name for name in self.entries if name.startswith("lib/")]
        for name in required:
            with self.subTest(library=name):
                data = self.entries.pop(name)
                self.write_apk()
                with self.assertRaisesRegex(ApkValidationError, "missing a nonempty"):
                    verify_apk(self.apk)
                self.entries[name] = data

    def test_rejects_empty_kdf_library(self):
        self.entries["lib/arm64-v8a/libkomodo_defi_framework.so"] = b""
        self.write_apk()
        with self.assertRaisesRegex(ApkValidationError, "missing a nonempty"):
            verify_apk(self.apk)

    def test_rejects_plain_files_and_truncated_archives(self):
        self.apk.write_bytes(b"not an apk")
        with self.assertRaises(ApkValidationError):
            verify_apk(self.apk)
        self.write_apk()
        self.apk.write_bytes(self.apk.read_bytes()[:-16])
        with self.assertRaises(ApkValidationError):
            verify_apk(self.apk)

    def test_rejects_zip_without_an_android_manifest(self):
        del self.entries["AndroidManifest.xml"]
        self.write_apk()
        with self.assertRaisesRegex(ApkValidationError, "AndroidManifest.xml"):
            verify_apk(self.apk)

    def test_rejects_corrupt_payloads(self):
        self.write_apk()
        data = bytearray(self.apk.read_bytes())
        data[data.index(b"manifest-content")] ^= 1
        self.apk.write_bytes(data)
        with self.assertRaisesRegex(ApkValidationError, "corrupt entry"):
            verify_apk(self.apk)

    def test_rejects_malformed_compressed_payload(self):
        with zipfile.ZipFile(self.apk, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in self.entries.items():
                archive.writestr(name, data)
        data = bytearray(self.apk.read_bytes())
        # First local header has no extra fields; force an invalid deflate block.
        data[30 + len(b"AndroidManifest.xml")] = 0x07
        self.apk.write_bytes(data)
        with self.assertRaises(ApkValidationError):
            verify_apk(self.apk)

    def test_rejects_duplicate_native_entries(self):
        self.write_apk()
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.apk, "a") as archive:
                archive.writestr("lib/arm64-v8a/libflutter.so", b"ambiguous")
        with self.assertRaisesRegex(ApkValidationError, "duplicate"):
            verify_apk(self.apk)

    def test_rejects_malformed_native_paths(self):
        self.entries["lib/arm64-v8a/nested/libflutter.so"] = b"misplaced"
        self.write_apk()
        with self.assertRaisesRegex(ApkValidationError, "Malformed native"):
            verify_apk(self.apk)

    def test_missing_file_is_a_validation_error(self):
        with self.assertRaises(ApkValidationError):
            verify_apk(self.apk)


if __name__ == "__main__":
    unittest.main()
