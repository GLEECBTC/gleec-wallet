"""Privacy and identity checks for the rollback source snapshot enumerator."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import prepare_auth_rollback as snapshot


class SnapshotSelectionTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="gleec-rollback-selection-")
        self.root = Path(self.directory.name)
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)

    def tearDown(self):
        self.directory.cleanup()

    def write(self, name, content="synthetic"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def test_includes_tracked_changes_and_required_new_source(self):
        self.write("lib/reader.dart", "before")
        subprocess.run(["git", "-C", str(self.root), "add", "lib/reader.dart"], check=True)
        self.write("lib/reader.dart", "after")
        self.write("lib/services/wallet_access/new_reader.dart")
        self.write("pubspec_overrides.yaml")
        self.assertEqual({str(item) for item in snapshot.selected(self.root)},
                         {"lib/reader.dart", "lib/services/wallet_access/new_reader.dart",
                          "pubspec_overrides.yaml"})

    def test_excludes_personal_material_even_when_tracked(self):
        for name in ["assets/debug_data.json", "android/key.properties", "android/signing.jks",
                     "assets/.env", "lib/.env.production", "lib/build/output.dart",
                     "tool/trace.log", "tool/export.zip", "tool/notes.local.md",
                     "ios/AuthKey.p8", "ios/signing.pem", "tool/__pycache__/cache.pyc",
                     "wallet-support.zip", "swap_data_2026.json"]:
            self.write(name)
        subprocess.run(["git", "-C", str(self.root), "add", "."], check=True)
        self.assertEqual(list(snapshot.selected(self.root)), [])

    def test_ignored_data_is_never_selected(self):
        self.write(".gitignore", "assets/private.json\n")
        self.write("assets/private.json")
        self.assertEqual(list(snapshot.selected(self.root)), [])

    def test_symlink_cannot_escape_allowlist(self):
        self.write("outside.txt")
        (self.root / "lib").mkdir()
        (self.root / "lib" / "leak.dart").symlink_to(self.root / "outside.txt")
        with self.assertRaisesRegex(RuntimeError, "explicit review"):
            list(snapshot.selected(self.root))

    def test_native_source_and_sdk_workspace_inputs_are_included(self):
        names = {"packages/framework/android/Vault.java", "packages/sdk/lib/reader.dart",
                 "playground/pubspec.yaml", "products/wallet/pubspec.yaml", "pubspec.yaml"}
        for name in names:
            self.write(name)
        self.assertEqual({str(item) for item in snapshot.selected(self.root, sdk=True)}, names)

    def test_profiles_only_disable_enrollment_and_shorten_grace(self):
        self.assertEqual(snapshot.ROLLBACK_DEFINES, {
            "WALLET_DEVICE_ENROLLMENT_ENABLED": "false",
            "WALLET_PASSKEY_ENROLLMENT_ENABLED": "false",
            "WALLET_IMMEDIATE_LOCK_REQUIRED": "true",
        })
        self.assertEqual(set(snapshot.NORMAL_DEFINES), set(snapshot.ROLLBACK_DEFINES))
        json.dumps(snapshot.ROLLBACK_DEFINES)


if __name__ == "__main__":
    unittest.main()
