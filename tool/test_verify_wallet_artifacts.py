import tempfile
from pathlib import Path
import unittest
import zipfile

from verify_wallet_artifacts import verify


class ArtifactPrivacyTest(unittest.TestCase):
    def test_rejects_fixture_in_directory_and_archive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture = root / "flutter_assets/assets/debug_data.json"
            fixture.parent.mkdir(parents=True)
            fixture.write_text("synthetic fixture")
            with self.assertRaises(ValueError):
                verify(root)
            for suffix in ("apk", "aab", "ipa", "zip"):
                archive = root / f"wallet.{suffix}"
                with zipfile.ZipFile(archive, "w") as output:
                    output.writestr("assets/flutter_assets/assets/debug_data.json", "synthetic fixture")
                with self.assertRaises(ValueError):
                    verify(archive)

    def test_accepts_public_assets_and_rejects_signing_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "index.html").write_text("public")
            verify(root)
            for filename in ("key.properties", "signing.jks", "release.keystore"):
                private = root / filename
                private.write_text("synthetic fixture")
                with self.assertRaises(ValueError):
                    verify(root)
                private.unlink()

    def test_missing_artifacts_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                verify(Path(directory) / "missing.apk")


if __name__ == "__main__":
    unittest.main()
