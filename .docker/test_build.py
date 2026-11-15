"""Exercise the Docker wrapper using temporary Git repos and a fake Docker CLI."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent


class DockerBuildTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.base = Path(self.directory.name)
        self.work = self.base / "wallet with spaces"
        self.work.mkdir()
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.calls = self.base / "docker.jsonl"
        self.real_git = shutil.which("git")
        self.env = {
            "PATH": str(self.bin) + os.pathsep + os.environ["PATH"],
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
            "GIT_ALLOW_PROTOCOL": "file",
            "DOCKER_CALLS": str(self.calls),
            "LIFI_BUILD_ENVIRONMENT": "production",
        }
        for key in ("SYSTEMROOT", "WINDIR", "TMPDIR", "TEMP"):
            if key in os.environ:
                self.env[key] = os.environ[key]
        self.executable("docker", "#!/usr/bin/env python3\n"
                        "import json, os, sys\n"
                        "with open(os.environ['DOCKER_CALLS'], 'a') as output:\n"
                        "    output.write(json.dumps(sys.argv[1:]) + '\\n')\n")
        self.source = self.base / "sdk-source"
        self.source.mkdir()
        self.git("init", "-q", cwd=self.source)
        (self.source / "tracked.txt").write_text("recorded SDK\n")
        self.git("add", ".", cwd=self.source)
        self.commit(self.source)
        self.git("init", "-q")
        self.git("submodule", "add", "-q", str(self.source), "sdk")
        self.commit(self.work)
        for name in ("tool", ".github"):
            (self.work / name).symlink_to(ROOT / name, target_is_directory=True)

    def executable(self, name, contents):
        path = self.bin / name
        path.write_text(contents)
        path.chmod(0o700)

    def git(self, *args, cwd=None):
        return subprocess.run([self.real_git, *args], cwd=cwd or self.work,
                              env=self.env, check=True, capture_output=True,
                              text=True).stdout.strip()

    def commit(self, cwd):
        self.git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "commit", "-qm", "fixture", cwd=cwd)

    def build(self):
        return subprocess.run(["bash", str(ROOT / ".docker/build.sh"),
                               "linux", "release"], cwd=self.work,
                              env=self.env, capture_output=True, text=True)

    def test_preserves_tracked_and_untracked_sdk_work(self):
        tracked = self.work / "sdk/tracked.txt"
        untracked = self.work / "sdk/local-only.txt"
        tracked.write_text("local SDK edit\n")
        untracked.write_text("local SDK note\n")
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(tracked.read_text(), "local SDK edit\n")
        self.assertEqual(untracked.read_text(), "local SDK note\n")
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        run = next(call for call in calls if call[0] == "run")
        self.assertIn(str(self.work.resolve()) + ":/app", run)
        self.assertNotIn("--config-only", run[-1])
        self.assertEqual(run[-4:-1], ["bash", "-e", "-c"])

    def test_refuses_different_sdk_commit_without_checking_out(self):
        sdk = self.work / "sdk"
        (sdk / "tracked.txt").write_text("new SDK commit\n")
        self.git("add", ".", cwd=sdk)
        self.commit(sdk)
        head = self.git("rev-parse", "HEAD", cwd=sdk)
        result = self.build()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local work was left intact", result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD", cwd=sdk), head)
        self.assertFalse(self.calls.exists())

    def test_initializes_missing_sdk(self):
        self.git("submodule", "deinit", "-f", "--", "sdk")
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.work / "sdk/tracked.txt").read_text(),
                         "recorded SDK\n")

    def test_failed_submodule_update_stops_before_docker(self):
        self.executable("git", "#!/bin/bash\n"
                        "if [[ $1 == submodule && $2 == update ]]; then exit 23; fi\n"
                        'exec "$REAL_GIT" "$@"\n')
        self.env["REAL_GIT"] = self.real_git
        result = self.build()
        self.assertEqual(result.returncode, 23)
        self.assertFalse(self.calls.exists())

    def test_failed_pub_resolution_never_starts_flutter_build(self):
        result = self.build()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        run = next(call for call in calls if call[0] == "run")
        self.executable("sudo", "#!/bin/sh\nexit 0\n")
        self.executable("flutter", '#!/bin/sh\nprintf "%s\\n" "$*" >> "$FLUTTER_CALLS"\n'
                        'if [ "$1" = pub ]; then exit 19; fi\n')
        flutter_calls = self.base / "flutter.txt"
        result = subprocess.run(run[-4:], cwd=self.work,
                                env={**self.env, "FLUTTER_CALLS": str(flutter_calls)},
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 19)
        self.assertEqual(flutter_calls.read_text().splitlines(),
                         ["pub get --enforce-lockfile"])


if __name__ == "__main__":
    unittest.main()
