"""Exercise the real deploy wrapper without network access or real credentials."""

import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest


SCRIPTS = Path(__file__).resolve().parent
DEPLOY = SCRIPTS / "firebase_hosting_deploy.sh"
URL_READER = SCRIPTS / "hosting_deploy_url.sh"
CANARY = "SYNTHETIC_FIREBASE_SECRET_MUST_NOT_ESCAPE_632704"
PREVIEW_URL = "https://test-site--privacy-check-abc123.web.app"
LIVE_URL = "https://test-site.web.app"


FAKE_NPX = r'''
import json
import os
from pathlib import Path
import stat
import sys
import time

metadata = Path(os.environ["TEST_METADATA"])
records = json.loads(metadata.read_text()) if metadata.exists() else []
args = sys.argv[1:]
credential = Path(os.environ["GOOGLE_APPLICATION_CREDENTIALS"]).resolve()
cwd = Path.cwd()
config = Path(args[args.index("--config") + 1])
record = {
    "args": args,
    "privateWorkingDirectory": cwd.parent == Path(os.environ["RUNNER_TEMP"]).resolve(),
    "workingDirectoryMode": stat.S_IMODE(cwd.stat().st_mode),
    "credentialMode": stat.S_IMODE(credential.stat().st_mode),
    "credentialInWorkingDirectory": credential.parent == cwd,
    "credentialEnvironmentRemoved": "FIREBASE_SERVICE_ACCOUNT" not in os.environ,
    "debugEnvironmentRemoved": "DEBUG" not in os.environ,
    "absoluteConfiguration": config.is_absolute(),
    "configurationMatchesCheckout": config.resolve() == Path(os.environ["TEST_PROJECT"]).resolve() / "firebase.json",
    "configurationReadable": json.loads(config.read_text())["hosting"]["public"] == "public",
    "targetMappingReadable": json.loads((config.parent / ".firebaserc").read_text())["targets"]["fixture-project"]["hosting"]["web"] == ["test-site"],
    "configStorePrivate": Path(os.environ["XDG_CONFIG_HOME"]).resolve().parent == cwd,
    "npmLogsPrivate": Path(os.environ["npm_config_logs_dir"]).resolve().parent == cwd,
}
records.append(record)
metadata.write_text(json.dumps(records))
canary = "SYNTHETIC_FIREBASE_SECRET_MUST_NOT_ESCAPE_632704"
print('{"signIn":{"hashConfig":{"signerKey":"' + canary + '"}}}', flush=True)
print("provider stderr " + canary, file=sys.stderr, flush=True)
for name in ("firebase-debug.log", "firebase-debug.1.log"):
    (cwd / name).write_text(canary)
for variable in ("XDG_CONFIG_HOME", "npm_config_logs_dir"):
    directory = Path(os.environ[variable])
    directory.mkdir(exist_ok=True)
    (directory / "private-debug.log").write_text(canary)

scenario = os.environ["TEST_SCENARIO"]
attempt = len(records)
if scenario == "term":
    # The test signals the whole process group after these private files exist.
    Path(os.environ["TEST_READY"]).touch()
    time.sleep(30)
elif scenario == "permanent":
    sys.exit(42)
elif scenario == "exhaust" or (scenario in ("retry", "stale-active") and attempt == 1):
    print("Hosting URL: https://stale-attempt.web.app")
    print("ECONNRESET", file=sys.stderr)
    sys.exit(7)
elif scenario in ("active", "stale-active"):
    print("The supplied version is already the current active version.")
    sys.exit(1)
elif scenario == "active-preview":
    print("The supplied version is already the current active version.")
    print("+ hosting:channel: Channel URL (test-site): https://test-site--privacy-check-abc123.web.app [expires 2026-11-16]")
    sys.exit(1)
elif scenario in ("live-only", "active-live-only"):
    print("Hosting URL: https://test-site.web.app")
    if scenario == "active-live-only":
        print("The supplied version is already the current active version.")
        sys.exit(1)
    sys.exit(0)
elif scenario == "missing":
    sys.exit(0)
elif scenario == "invalid-url":
    print("Hosting URL: https://test-site.web.app/?credential=" + canary)
    sys.exit(0)

if "deploy" in args:
    print("Hosting URL: https://test-site.web.app")
else:
    print("Hosting URL: https://test-site.web.app")
    print("+ hosting:channel: Channel URL (test-site): https://test-site--privacy-check-abc123.web.app [expires 2026-11-16]")
'''


class DeployPrivacyTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="hosting-privacy-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "checkout with spaces"
        self.project.mkdir()
        (self.project / "firebase.json").write_text(
            json.dumps({"hosting": {"target": "web", "public": "public"}})
        )
        (self.project / ".firebaserc").write_text(
            json.dumps({"targets": {"fixture-project": {"hosting": {"web": ["test-site"]}}}})
        )
        (self.project / "public").mkdir()
        # Existing unrelated logs must never be deleted by wrapper cleanup.
        (self.project / "firebase-debug.log").write_text("pre-existing fixture")
        self.runner_temp = self.root / "runner-temp"
        self.runner_temp.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        (self.bin / "npx").write_text(f"#!{sys.executable}\n" + FAKE_NPX)
        (self.bin / "npx").chmod(0o755)
        # Retry timing is not the subject; record its requested delays instead.
        (self.bin / "sleep").write_text(
            '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$TEST_SLEEPS"\n'
        )
        (self.bin / "sleep").chmod(0o755)
        self.output = self.root / "github-output"
        self.metadata = self.root / "metadata.json"
        self.ready = self.root / "ready"
        self.sleeps = self.root / "sleeps"
        self.env = dict(
            os.environ,
            PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
            RUNNER_TEMP=str(self.runner_temp),
            FIREBASE_SERVICE_ACCOUNT=json.dumps({"type": "service_account", "private_key": CANARY}),
            CHANNEL_ID="privacy-check",
            TARGET="web",
            EXPIRES="7d",
            PROJECT_ID="fixture-project",
            FIREBASE_TOOLS_VERSION="15.22.3",
            URL_READER=str(URL_READER),
            GITHUB_OUTPUT=str(self.output),
            DEBUG="true",
            TEST_METADATA=str(self.metadata),
            TEST_PROJECT=str(self.project),
            TEST_READY=str(self.ready),
            TEST_SLEEPS=str(self.sleeps),
        )

    def run_deploy(self, scenario="success", **overrides):
        env = dict(self.env, TEST_SCENARIO=scenario, **overrides)
        return subprocess.run(
            ["bash", str(DEPLOY)], cwd=self.project, env=env,
            capture_output=True, text=True, timeout=10,
        )

    def assert_private(self, result, attempts):
        public = result.stdout + result.stderr
        if self.output.exists():
            public += self.output.read_text()
        self.assertNotIn(CANARY, public)
        self.assertNotIn("signerKey", public)
        self.assertFalse(list(self.runner_temp.iterdir()), "Run-owned files survived cleanup")
        self.assertEqual((self.project / "firebase-debug.log").read_text(), "pre-existing fixture")
        records = json.loads(self.metadata.read_text()) if self.metadata.exists() else []
        self.assertEqual(len(records), attempts)
        for record in records:
            for key, value in record.items():
                if key not in ("args", "workingDirectoryMode", "credentialMode"):
                    self.assertTrue(value, key)
            self.assertEqual(record["workingDirectoryMode"], 0o700)
            self.assertEqual(record["credentialMode"], 0o600)
            self.assertNotIn("--debug", record["args"])
            self.assertIn("--non-interactive", record["args"])
            self.assertIn("firebase-tools@15.22.3", record["args"])
        return records

    def test_preview_success_keeps_provider_data_private_and_preserves_args(self):
        result = self.run_deploy()
        self.assertEqual(result.returncode, 0, result.stderr)
        records = self.assert_private(result, 1)
        self.assertEqual(self.output.read_text(), f"details_url={PREVIEW_URL}\n")
        self.assertEqual(records[0]["args"][:4], ["--yes", "firebase-tools@15.22.3", "hosting:channel:deploy", "privacy-check"])
        self.assertIn("--expires", records[0]["args"])
        self.assertIn("web", records[0]["args"])

    def test_composite_action_runs_the_private_wrapper(self):
        action = (SCRIPTS.parent / "actions/firebase-hosting-deploy/action.yml").read_text()
        self.assertIn(
            "DEPLOY_SCRIPT: ${{ github.action_path }}/../../scripts/firebase_hosting_deploy.sh",
            action,
        )
        self.assertIn(
            "URL_READER: ${{ github.action_path }}/../../scripts/hosting_deploy_url.sh",
            action,
        )
        runtime = textwrap.dedent(action.split("      run: |\n", 1)[1])
        result = subprocess.run(
            ["bash", "-e", "-o", "pipefail", "-c", runtime], cwd=self.project,
            env=dict(self.env, TEST_SCENARIO="success", DEPLOY_SCRIPT=str(DEPLOY)),
            capture_output=True, text=True, timeout=10,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_private(result, 1)
        self.assertEqual(self.output.read_text(), f"details_url={PREVIEW_URL}\n")

    def test_live_success_preserves_only_target(self):
        result = self.run_deploy(CHANNEL_ID="live")
        self.assertEqual(result.returncode, 0, result.stderr)
        records = self.assert_private(result, 1)
        self.assertIn("hosting:web", records[0]["args"])
        self.assertNotIn("--expires", records[0]["args"])
        self.assertEqual(self.output.read_text(), f"details_url={LIVE_URL}\n")

    def test_live_without_target_remains_hosting_only(self):
        result = self.run_deploy(CHANNEL_ID="live", TARGET="")
        self.assertEqual(result.returncode, 0)
        records = self.assert_private(result, 1)
        self.assertIn("hosting", records[0]["args"])
        self.assertNotIn("hosting:", records[0]["args"])

    def test_permanent_failure_preserves_status_without_raw_output(self):
        result = self.run_deploy("permanent")
        self.assertEqual(result.returncode, 42)
        self.assert_private(result, 1)
        self.assertFalse(self.output.exists())

    def test_transient_failure_retries_then_publishes_only_final_url(self):
        result = self.run_deploy("retry")
        self.assertEqual(result.returncode, 0)
        self.assert_private(result, 2)
        self.assertEqual(self.sleeps.read_text(), "10\n")
        self.assertEqual(self.output.read_text(), f"details_url={PREVIEW_URL}\n")

    def test_retry_exhaustion_preserves_failure_and_cleans_all_logs(self):
        result = self.run_deploy("exhaust")
        self.assertEqual(result.returncode, 7)
        self.assert_private(result, 3)
        self.assertEqual(self.sleeps.read_text(), "10\n20\n")
        self.assertFalse(self.output.exists())

    def test_existing_active_live_version_remains_successful(self):
        result = self.run_deploy("active", CHANNEL_ID="live")
        self.assertEqual(result.returncode, 0)
        self.assert_private(result, 1)
        self.assertEqual(self.output.read_text(), "details_url=\n")

    def test_existing_active_preview_requires_its_valid_url(self):
        result = self.run_deploy("active-preview")
        self.assertEqual(result.returncode, 0)
        self.assert_private(result, 1)
        self.assertEqual(self.output.read_text(), f"details_url={PREVIEW_URL}\n")

    def test_active_preview_does_not_reuse_previous_attempt_url(self):
        result = self.run_deploy("stale-active")
        self.assertEqual(result.returncode, 1)
        self.assert_private(result, 2)
        self.assertFalse(self.output.exists())

    def test_successful_preview_without_url_fails_closed(self):
        result = self.run_deploy("missing")
        self.assertEqual(result.returncode, 1)
        self.assert_private(result, 1)
        self.assertFalse(self.output.exists())

    def test_preview_never_publishes_a_live_only_url(self):
        result = self.run_deploy("live-only")
        self.assertEqual(result.returncode, 1)
        self.assert_private(result, 1)
        self.assertFalse(self.output.exists())

    def test_active_preview_never_publishes_a_live_only_url(self):
        result = self.run_deploy("active-live-only")
        self.assertEqual(result.returncode, 1)
        self.assert_private(result, 1)
        self.assertFalse(self.output.exists())

    def test_successful_preview_with_secret_url_fails_closed(self):
        result = self.run_deploy("invalid-url")
        self.assertEqual(result.returncode, 1)
        self.assert_private(result, 1)
        self.assertFalse(self.output.exists())

    def test_malformed_credentials_do_not_reach_cli_or_diagnostics(self):
        result = self.run_deploy(FIREBASE_SERVICE_ACCOUNT='{"private_key":"' + CANARY)
        self.assertEqual(result.returncode, 1)
        self.assert_private(result, 0)
        self.assertEqual(result.stdout, "Firebase service account secret is not valid JSON.\n")
        self.assertEqual(result.stderr, "")

    def test_nonobject_credentials_are_rejected(self):
        result = self.run_deploy(FIREBASE_SERVICE_ACCOUNT=json.dumps(CANARY))
        self.assertEqual(result.returncode, 1)
        self.assert_private(result, 0)

    def test_channel_normalization_does_not_echo_raw_input(self):
        result = self.run_deploy(CHANNEL_ID="privacy/" + CANARY)
        self.assertEqual(result.returncode, 0)
        self.assert_private(result, 1)
        self.assertIn("Channel ID normalized", result.stdout)

    @unittest.skipUnless(hasattr(os, "killpg"), "Requires POSIX process groups")
    def test_term_cleans_private_credential_and_debug_files(self):
        process = subprocess.Popen(
            ["bash", str(DEPLOY)], cwd=self.project,
            env=dict(self.env, TEST_SCENARIO="term"),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            start_new_session=True,
        )
        try:
            deadline = time.monotonic() + 5
            while not self.ready.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(self.ready.exists(), "Fake CLI did not reach private-log creation")
            os.killpg(process.pid, signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=5)
            result = subprocess.CompletedProcess(process.args, process.returncode, stdout, stderr)
            self.assertEqual(result.returncode, 143)
            self.assert_private(result, 1)
            self.assertFalse(self.output.exists())
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()


class HostingUrlBoundaryTest(unittest.TestCase):
    def parse(self, contents, mode="auto"):
        with tempfile.TemporaryDirectory(prefix="hosting-url-boundary-") as directory:
            log = Path(directory) / "provider.log"
            log.write_bytes(contents.encode())
            return subprocess.run(["bash", str(URL_READER), str(log), mode], capture_output=True, text=True, timeout=5)

    def test_valid_live_preview_and_colored_lines(self):
        cases = [
            (f"Hosting URL: {LIVE_URL}\n", LIVE_URL),
            (f"+ hosting:channel: Channel URL (test-site): {PREVIEW_URL} [expires 2026-11-16] [version abc123]\n", PREVIEW_URL),
            (f"\x1b[32m+\x1b[39m hosting:channel: Channel URL (\x1b[1mtest-site\x1b[22m): {PREVIEW_URL} [expires 2026-11-16]\n", PREVIEW_URL),
        ]
        for contents, expected in cases:
            with self.subTest(contents=contents):
                result = self.parse(contents)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout, expected + "\n")
                self.assertEqual(result.stderr, "")

    def test_hostile_url_forms_are_never_output(self):
        invalid = [
            "https://example.com", "https://test-site.web.app.attacker.test",
            "https://user:secret@test-site.web.app", "https://test-site.web.app:443",
            "https://test-site.web.app/path", "https://test-site.web.app?token=secret",
            "https://test-site.web.app/#secret", "https://test-site.web.app%0aBAD=1",
            "https://test-site.web.app/$(touch${IFS}sentinel)",
            "https://test-site.web.app/`touch${IFS}sentinel`",
            'https://test-site.web.app/";exit;"', "https://test_site.web.app",
            "https://-test.web.app", "https://test-.web.app",
            "https://nested.test-site.web.app", "https://test-site.WEB.app",
            "https://" + "a" * 64 + ".web.app",
            "https://test-site.web.app\r", "https://test-site.web.app\x00",
            "https://test-site.web.app\x1b[2J", "https://test-site.web.app\v",
        ]
        for url in invalid:
            with self.subTest(url=repr(url)):
                result = self.parse("Hosting URL: " + url + "\n")
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")

    def test_embedded_provider_body_is_not_a_success_line(self):
        result = self.parse('[debug] {"message":"Hosting URL: ' + LIVE_URL + '"}\n')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")

    def test_conflicting_success_lines_fail_closed(self):
        result = self.parse(f"Hosting URL: {LIVE_URL}\nHosting URL: https://another-site.web.app\n")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")

    def test_preview_url_takes_precedence_over_live_url_in_either_order(self):
        live_line = f"Hosting URL: {LIVE_URL}\n"
        preview_line = f"+ hosting:channel: Channel URL (test-site): {PREVIEW_URL} [expires 2026-11-16]\n"
        for contents in (live_line + preview_line, preview_line + live_line,
                         live_line + preview_line + preview_line):
            with self.subTest(contents=contents):
                result = self.parse(contents)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout, PREVIEW_URL + "\n")

    def test_live_mode_selects_only_the_hosting_url(self):
        result = self.parse(
            f"Hosting URL: {LIVE_URL}\n"
            f"+ hosting:channel: Channel URL (test-site): {PREVIEW_URL}\n",
            mode="live",
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, LIVE_URL + "\n")

    def test_malformed_channel_lines_cannot_hide_behind_a_valid_url(self):
        malformed = [
            "https://attacker.test", PREVIEW_URL + " [unknown metadata]",
            PREVIEW_URL + "?secret=canary", "not-a-url",
        ]
        for url in malformed:
            with self.subTest(url=url):
                result = self.parse(
                    f"Hosting URL: {LIVE_URL}\n"
                    f"+ hosting:channel: Channel URL (test-site): {PREVIEW_URL}\n"
                    f"+ hosting:channel: Channel URL (test-site): {url}\n",
                    mode="preview",
                )
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, "")

    def test_conflicting_preview_urls_do_not_fall_back_to_live_url(self):
        result = self.parse(
            f"Hosting URL: {LIVE_URL}\n"
            f"+ hosting:channel: Channel URL (test-site): {PREVIEW_URL}\n"
            "+ hosting:channel: Channel URL (another-site): https://another-preview.web.app\n"
        )
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, "")

    def test_duplicate_identical_success_lines_are_unambiguous(self):
        result = self.parse(f"Hosting URL: {LIVE_URL}\nHosting URL: {LIVE_URL}\n")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, LIVE_URL + "\n")


if __name__ == "__main__":
    if not shutil.which("jq"):
        raise SystemExit("The deployment regression suite requires jq.")
    unittest.main()
