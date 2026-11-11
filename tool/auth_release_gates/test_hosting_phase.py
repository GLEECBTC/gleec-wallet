import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch
import urllib.error
import zipfile

implementation = Path(__file__).with_name("hosting_phase.py")
if not implementation.exists():
    implementation = Path(__file__).with_name("auth_hosting_phase.py")
spec = importlib.util.spec_from_file_location("hosting", implementation)
hosting = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hosting)


class HostingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.previous = Path.cwd()
        os.chdir(self.temp.name)
        self.live = "sites/gleec-wallet-official/versions/old123"
        self.target = "sites/gleec-wallet-official/versions/new456"
        self.preview = self.target
        self.url = "https://gleec-wallet-official--auth-security-20261108-abcd12.web.app"
        self.posts = 0
        self.cli_calls = []
        self.cli_configuration = None
        self.lose_response = False
        self.returned_version = "new456"
        self.remote_files = {}
        self.extra_file = False
        self.bad_config = False
        self.change_during_inventory = False
        self.missing_file = False
        self.paginate = False
        self.config = {"mode": "preview", "expectedLiveVersion": self.live,
                       "expectedLiveMainSha256": hashlib.sha256(b"original main").hexdigest(),
                       "previewVersion": self.target}
        self.firebase = {"hosting": {"site": hosting.SITE, "public": "public", "appAssociation": "NONE",
                                     "rewrites": [{"source": "**", "destination": "/index.html"}]}}
        self.stack = contextlib.ExitStack()
        self.stack.enter_context(patch.dict(os.environ, HOSTING_SERVICE_ACCOUNT=json.dumps({"type": "service_account", "project_id": hosting.SITE})))
        self.stack.enter_context(patch.object(hosting.urllib.request, "urlopen", self.fetch))
        self.stack.enter_context(patch.object(hosting.subprocess, "run", self.run_command))
        self.prepare()

    def tearDown(self):
        self.stack.close()
        os.chdir(self.previous)
        self.temp.cleanup()

    def prepare(self, extra=None):
        with zipfile.ZipFile("hosting-candidate.zip", "w") as archive:
            archive.writestr("firebase.json", json.dumps(self.firebase))
            for name in ("index.html", "main.dart.js", "flutter_bootstrap.js", ".well-known/apple-app-site-association"):
                archive.writestr("public/" + name, "synthetic content")
            if extra:
                archive.writestr(extra, "invalid entry")
        self.config["candidateSha256"] = hashlib.sha256(Path("hosting-candidate.zip").read_bytes()).hexdigest()
        Path("hosting-operation.json").write_text(json.dumps(self.config))

    def run_command(self, command, **kwargs):
        if command[0] == "gcloud":
            return types.SimpleNamespace(returncode=0, stdout="synthetic bearer")
        self.cli_calls.append(command)
        self.assertIn("--no-authorized-domains", command)
        self.assertNotIn("HOSTING_SERVICE_ACCOUNT", kwargs["env"])
        candidate = Path(kwargs["cwd"])
        self.cli_configuration = json.loads((candidate / "firebase.json").read_text())
        cache = candidate / ".firebase"
        cache.mkdir()
        rows = []
        for file in sorted((candidate / "public").rglob("*")):
            if file.is_file():
                path = file.relative_to(candidate / "public").as_posix()
                digest = hashlib.sha256(file.read_bytes()).hexdigest()
                rows.append(f"{path},0,{digest}")
                self.remote_files["/" + path] = digest
        (cache / "hosting.cHVibGlj.cache").write_text("\n".join(rows))
        value = {"status": "success", "result": {hosting.SITE: {"version": self.returned_version, "url": self.url}}}
        return types.SimpleNamespace(returncode=0, stdout=json.dumps(value))

    def fetch(self, request, **kwargs):
        if isinstance(request, str):
            self.assertEqual(request, "https://dex.gleec.com/main.dart.js")
            return io.BytesIO(b"original main")
        url = request.full_url
        if request.data is not None:
            self.assertIn("/releases?versionName=", url)
            self.posts += 1
            self.live = self.target
            if self.lose_response:
                raise urllib.error.URLError("response lost after write")
            value = {"name": "newRelease"}
        elif url.endswith("/channels/live"):
            value = {"release": {"name": "liveRelease", "version": {"name": self.live}}}
        elif "/channels/" in url:
            value = {"url": self.url, "release": {"version": {"name": self.preview}}}
        elif "/versions/new456/files?" in url:
            files = dict(self.remote_files)
            if self.extra_file:
                files["/unexpected.js"] = "f" * 64
            if self.missing_file:
                files.pop(next(iter(files)))
            rows = [{"path": path, "hash": digest} for path, digest in files.items()]
            if self.paginate and "pageToken=next" not in url:
                value = {"files": rows[:2], "nextPageToken": "next"}
            elif self.paginate:
                value = {"files": rows[2:]}
            else:
                value = {"files": rows}
            if self.change_during_inventory:
                self.preview = "sites/gleec-wallet-official/versions/foreign789"
        elif url.endswith("/versions/new456"):
            value = {"status": "FINALIZED", "config": {} if self.bad_config else hosting.expected_version_config(self.firebase["hosting"])}
        else:
            self.fail("Unexpected endpoint: " + url)
        return io.BytesIO(json.dumps(value).encode())

    def test_preview_preserves_live_and_binds_exact_version(self):
        hosting.main()
        self.assertEqual(self.posts, 0)
        self.assertEqual(len(self.cli_calls), 1)
        evidence = json.loads(Path("hosting-operation-evidence.json").read_text())
        self.assertEqual(evidence["version"], self.target)

    def test_concurrent_preview_change_rejected(self):
        self.preview = "sites/gleec-wallet-official/versions/foreign789"
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(Path("hosting-operation-evidence.json").exists())

    def test_same_site_full_resource_version_is_accepted(self):
        self.returned_version = self.target
        hosting.main()
        evidence = json.loads(Path("hosting-operation-evidence.json").read_text())
        self.assertEqual(evidence["version"], self.target)

    def test_other_site_resource_is_rejected(self):
        self.returned_version = "sites/other-site/versions/new456"
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(Path("hosting-operation-evidence.json").exists())

    def test_missing_cli_version_requires_complete_equivalence(self):
        self.returned_version = ""
        hosting.main()
        self.assertTrue(Path("hosting-operation-evidence.json").exists())

    def test_reviewed_config_overlay_is_bound_to_evidence(self):
        overlay = json.loads(json.dumps(self.firebase))
        overlay["hosting"]["headers"] = [{"source": "**", "headers": [
            {"key": "Cache-Control", "value": "no-cache, max-age=0, must-revalidate"}
        ]}]
        raw = json.dumps(overlay).encode()
        Path("hosting-configuration.json").write_bytes(raw)
        self.config["configurationSha256"] = hashlib.sha256(raw).hexdigest()
        self.prepare()
        # The archive still has the original configuration; only the reviewed
        # overlay and the simulated finalized server use the new cache policy.
        self.firebase = overlay
        hosting.main()
        self.assertEqual(self.cli_configuration, overlay)
        evidence = json.loads(Path("hosting-operation-evidence.json").read_text())
        self.assertEqual(evidence["configurationSha256"], self.config["configurationSha256"])

    def test_correctly_hashed_overlay_hook_is_rejected_before_deploy(self):
        overlay = json.loads(json.dumps(self.firebase))
        overlay["hosting"]["predeploy"] = ["touch unwanted"]
        raw = json.dumps(overlay).encode()
        Path("hosting-configuration.json").write_bytes(raw)
        self.config["configurationSha256"] = hashlib.sha256(raw).hexdigest()
        self.prepare()
        with self.assertRaisesRegex(ValueError, "deploy hooks"):
            hosting.main()
        self.assertFalse(self.cli_calls)
        self.assertFalse(Path("hosting-operation-evidence.json").exists())

    def test_correctly_hashed_overlay_dynamic_rewrite_is_rejected(self):
        overlay = json.loads(json.dumps(self.firebase))
        overlay["hosting"]["rewrites"] = [{"source": "**", "function": "unwanted"}]
        raw = json.dumps(overlay).encode()
        Path("hosting-configuration.json").write_bytes(raw)
        self.config["configurationSha256"] = hashlib.sha256(raw).hexdigest()
        self.prepare()
        with self.assertRaisesRegex(ValueError, "Dynamic or external"):
            hosting.main()
        self.assertFalse(self.cli_calls)
        self.assertFalse(Path("hosting-operation-evidence.json").exists())

    def test_changed_config_overlay_is_rejected(self):
        Path("hosting-configuration.json").write_text("{}")
        self.config["configurationSha256"] = "a" * 64
        self.prepare()
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(self.cli_calls)

    def test_extra_remote_file_is_rejected_even_with_empty_cli_version(self):
        self.returned_version = ""
        self.extra_file = True
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(Path("hosting-operation-evidence.json").exists())

    def test_remote_config_mismatch_is_rejected(self):
        self.bad_config = True
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(Path("hosting-operation-evidence.json").exists())

    def test_missing_remote_file_is_rejected(self):
        self.missing_file = True
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(Path("hosting-operation-evidence.json").exists())

    def test_all_inventory_pages_are_compared(self):
        self.paginate = True
        hosting.main()
        self.assertTrue(Path("hosting-operation-evidence.json").exists())

    def test_changed_preview_during_inventory_is_rejected(self):
        self.change_during_inventory = True
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(Path("hosting-operation-evidence.json").exists())

    def test_duplicate_cache_path_is_rejected(self):
        candidate = Path("cache-fixture")
        (candidate / ".firebase").mkdir(parents=True)
        row = "index.html,0," + "a" * 64
        (candidate / ".firebase/hosting.cHVibGlj.cache").write_text(row + "\n" + row)
        with self.assertRaises(ValueError):
            hosting.uploaded_files(candidate)

    def test_malformed_cache_record_is_rejected(self):
        candidate = Path("cache-fixture")
        (candidate / ".firebase").mkdir(parents=True)
        (candidate / ".firebase/hosting.cHVibGlj.cache").write_text("index.html,not-a-time," + "a" * 64)
        with self.assertRaises(ValueError):
            hosting.uploaded_files(candidate)

    def test_changed_live_prevents_deploy(self):
        self.live = "sites/gleec-wallet-official/versions/other"
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(self.cli_calls)

    def test_noncanonical_archive_path_rejected(self):
        self.prepare("public/./index.html")
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(self.cli_calls)

    def test_hook_rejected_before_deploy(self):
        self.firebase["hosting"]["predeploy"] = ["touch unwanted"]
        self.prepare()
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(self.cli_calls)

    def test_dynamic_rewrite_rejected(self):
        self.firebase["hosting"]["rewrites"] = [{"source": "**", "function": "unwanted"}]
        self.prepare()
        with self.assertRaises(ValueError):
            hosting.main()
        self.assertFalse(self.cli_calls)

    def test_lost_promotion_response_reconciles_without_second_write(self):
        self.config["mode"] = "promote"
        self.prepare()
        self.lose_response = True
        hosting.main()
        self.assertEqual(self.posts, 1)
        self.assertEqual(self.live, self.target)
        self.assertFalse(self.cli_calls)


if __name__ == "__main__":
    unittest.main()
