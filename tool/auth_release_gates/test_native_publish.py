import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import zipfile

fake_paramiko = types.SimpleNamespace(SSHException=ValueError)
sys.modules.setdefault("paramiko", fake_paramiko)
implementation = Path(__file__).with_name("native_publish.py")
if not implementation.exists():
    implementation = Path(__file__).with_name("auth_native_publish.py")
spec = importlib.util.spec_from_file_location("publish", implementation)
publish = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publish)


class Remote(io.BytesIO):
    def __init__(self, data=b"", save=None):
        super().__init__(data)
        self.save = save

    def close(self):
        if self.save:
            self.save(self.getvalue())
        super().close()

    def set_pipelined(self, enabled):
        pass

    def prefetch(self, max_concurrent_requests):
        assert max_concurrent_requests == 64


class Sftp:
    def __init__(self):
        self.files = {}
        self.race = False
        self.fail_write = False
        self.removed = []

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def get_channel(self):
        return types.SimpleNamespace(settimeout=lambda value: None)

    def stat(self, name):
        if name not in self.files:
            raise FileNotFoundError(name)

    def open(self, name, mode):
        if mode == "wx":
            if name in self.files:
                raise FileExistsError(name)
            self.files[name] = b""
            stream = Remote(save=lambda value: self.files.__setitem__(name, value))
            if self.fail_write:
                stream.write = lambda block: (_ for _ in ()).throw(OSError("interrupted"))
            return stream
        return Remote(self.files[name])

    def chmod(self, name, mode):
        assert mode == 0o644

    def rename(self, source, destination):
        if self.race:
            self.files[destination] = b"another publisher"
        if destination in self.files:
            raise FileExistsError(destination)
        self.files[destination] = self.files.pop(source)

    def remove(self, name):
        self.removed.append(name)
        del self.files[name]


class PublicationTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.previous = Path.cwd()
        os.chdir(self.directory.name)
        Path("artifacts").mkdir()
        self.manifest = {"sourceCommit": publish.COMMIT, "artifacts": {}}
        for name, library in publish.NAMES.items():
            with zipfile.ZipFile(Path("artifacts", name), "w") as archive:
                archive.writestr("kdf", b"synthetic executable")
                archive.writestr(library, b"synthetic library")
            self.manifest["artifacts"][name] = hashlib.sha256(Path("artifacts", name).read_bytes()).hexdigest()
        Path("native-publication.json").write_text(json.dumps(self.manifest))
        self.sftp = Sftp()
        self.channel = types.SimpleNamespace(get_remote_server_key=lambda: types.SimpleNamespace(asbytes=lambda: b"public test host key"))
        self.client = types.SimpleNamespace(set_missing_host_key_policy=lambda policy: None,
            connect=self.connect, get_transport=lambda: self.channel,
            open_sftp=lambda: self.sftp, close=lambda: None)
        self.stack = contextlib.ExitStack()
        self.stack.enter_context(patch.dict(os.environ, FILE_SERVER_KEY="synthetic key", FILE_SERVER_HOST="test.invalid", FILE_SERVER_PORT="22", FILE_SERVER_USERNAME="fixture"))
        self.stack.enter_context(patch.object(publish, "paramiko", types.SimpleNamespace(
            Ed25519Key=types.SimpleNamespace(from_private_key=lambda stream: object()),
            RSAKey=object, ECDSAKey=object, SSHClient=lambda: self.client,
            AutoAddPolicy=lambda: object(), SSHException=ValueError)))
        self.stack.enter_context(patch.object(publish.urllib.request, "urlopen", self.fetch))
        self.foreign_redirect = False
        self.bad_https = False

    def tearDown(self):
        self.stack.close()
        os.chdir(self.previous)
        self.directory.cleanup()

    def connect(self, host, **kwargs):
        self.assertFalse(kwargs["allow_agent"])
        self.assertFalse(kwargs["look_for_keys"])
        self.assertNotIn("password", kwargs)

    def fetch(self, url, **kwargs):
        self.assertIn("GleecWalletReleaseValidation/", url.get_header("User-agent"))
        url = url.full_url
        body = self.sftp.files[publish.REMOTE + url.rsplit("/", 1)[-1]]
        response = Remote(b"wrong bytes" if self.bad_https else body)
        response.geturl = lambda: "https://other.invalid/file" if self.foreign_redirect else url
        return response

    def test_publish_and_rerun_never_replace(self):
        publish.main()
        first = dict(self.sftp.files)
        os.environ["FILE_SERVER_KEY"] = "synthetic key"
        publish.main()
        self.assertEqual(self.sftp.files, first)
        self.assertEqual(len(first), 2)
        self.assertTrue(Path("native-publication-evidence.json").exists())

    def test_existing_different_bytes_fail_without_delete(self):
        name = next(iter(publish.NAMES))
        self.sftp.files[publish.REMOTE + name] = b"old release"
        with self.assertRaises(ValueError):
            publish.main()
        self.assertEqual(self.sftp.files[publish.REMOTE + name], b"old release")
        self.assertFalse(self.sftp.removed)

    def test_race_at_rename_preserves_other_publisher(self):
        self.sftp.race = True
        with self.assertRaises(FileExistsError):
            publish.main()
        self.assertEqual(list(self.sftp.files.values()), [b"another publisher"])
        self.assertEqual(len(self.sftp.removed), 1)

    def test_interrupted_upload_removes_only_owned_staging(self):
        self.sftp.files["unrelated"] = b"keep"
        self.sftp.fail_write = True
        with self.assertRaises(OSError):
            publish.main()
        self.assertEqual(self.sftp.files, {"unrelated": b"keep"})

    def test_https_mismatch_cannot_produce_evidence(self):
        self.bad_https = True
        with self.assertRaises(ValueError):
            publish.main()
        self.assertFalse(Path("native-publication-evidence.json").exists())

    def test_foreign_redirect_cannot_produce_evidence(self):
        self.foreign_redirect = True
        with self.assertRaises(ValueError):
            publish.main()
        self.assertFalse(Path("native-publication-evidence.json").exists())

    def test_https_unavailable_cannot_produce_evidence(self):
        with patch.object(publish.urllib.request, "urlopen", side_effect=OSError("not published")):
            with self.assertRaises(OSError):
                publish.main()
        self.assertFalse(Path("native-publication-evidence.json").exists())

    def test_local_corruption_rejected_before_connect(self):
        self.client.connect = lambda *a, **k: self.fail("must not connect")
        Path("artifacts", next(iter(publish.NAMES))).write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            publish.main()


if __name__ == "__main__":
    unittest.main()
