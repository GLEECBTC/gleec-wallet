"""Public configuration and actual build-command regression checks; no network."""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from lifi_build_config import (PROFILES, event_environment, load_build_defines,
                               select_build_config, validate_build_command)


ROOT = Path(__file__).resolve().parent.parent


def build_environment(work, environment):
    # These tests exercise commands with stubs; never inherit provider secrets.
    inherited = {key: os.environ[key] for key in ["PATH", "SYSTEMROOT", "WINDIR", "TMPDIR", "TEMP"]
                 if key in os.environ}
    return {**inherited, "PATH": str(work / "bin") + os.pathsep + os.environ["PATH"],
            "LIFI_BUILD_ENVIRONMENT": environment,
            "TRON_GASLESS_CONFIG_VALIDATOR": str(ROOT / ".github/scripts/validate_tron_gasless_config.sh"),
            "TRON_GASLESS_ENABLED": "true", "TRON_GASLESS_RECEIVE_ENABLED": "true",
            "TRON_GASLESS_BASE_URL": "https://quicknode.gleec.com/gasfree/tron",
            "TRON_GASLESS_SERVICE_PROVIDER": "TLntW9Z59LYY5KEi9cmwk3PKjQga828ird",
            "TRON_GASLESS_REQUIRED_NETWORK": "tron"}


class LifiBuildConfigTest(unittest.TestCase):
    def test_event_selection(self):
        for event in ["pull_request", "push", "schedule"]:
            self.assertEqual(event_environment(event, "production"), "staging")
        for requested in PROFILES:
            self.assertEqual(event_environment("release", requested), "production")
            self.assertEqual(event_environment("workflow_dispatch", requested), requested)
        with self.assertRaises(ValueError):
            event_environment("workflow_dispatch", "invalid")

    def test_conflicting_defines_and_files_are_rejected_without_values(self):
        for option in ["--dart-define=", "--dart-define ", "--dart-defines=", "-D", "-D "]:
            for value in ["LIFI_INTEGRATOR_NAME=gleec-dex-staging",
                          "LIFI_INTEGRATOR_ENABLED=false", "LIFI_INTEGRATOR_FEE_BPS=0",
                          "LIFI_FEE_BPS=25", "LIFI_API_KEY=not-a-real-key"]:
                with self.subTest(option=option, field=value.split("=")[0]):
                    with self.assertRaises(ValueError) as caught:
                        validate_build_command("flutter build web " + option + value)
                    self.assertNotIn(value, str(caught.exception))
        for flag in ["--dart-define-from-file=private.env", "--dart-define-from-file private.env"]:
            with self.assertRaises(ValueError):
                validate_build_command("flutter build web " + flag)
        validate_build_command("flutter build web --release --dart-define=BYPASS_LEGAL_DOCUMENT_GATE=false")

    def test_profiles_select_their_matching_integration_and_fee_policy(self):
        for environment, (relative, integration) in PROFILES.items():
            with self.subTest(environment=environment):
                self.assertEqual(select_build_config(environment), relative)
                values = load_build_defines(ROOT / relative)
                self.assertEqual(values["LIFI_INTEGRATOR_NAME"], integration)
                self.assertEqual(values["LIFI_INTEGRATOR_FEE_BPS"], "178")
                self.assertEqual(values["LIFI_FEE_BPS"], "22")

    def test_wrong_profile_or_extra_credential_fields_fail_without_values(self):
        for overrides in [
            {"LIFI_INTEGRATOR_NAME": "gleec-dex-staging"},
            {"LIFI_API_KEY": "not-a-real-key"},
            {"LIFI_APP_ID": "not-a-real-key"},
            {"LIFI_FEE_BPS": 22},
        ]:
            with self.subTest(fields=list(overrides)), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root / PROFILES["production"][0]
                path.parent.mkdir()
                path.write_text(json.dumps({**load_build_defines(ROOT / PROFILES["production"][0]),
                                            **overrides}))
                with self.assertRaises(ValueError) as caught:
                    select_build_config("production", root)
                self.assertNotIn("not-a-real-key", str(caught.exception))

    def test_cli_rejects_unknown_environment_without_echoing_it(self):
        result = subprocess.run([sys.executable, str(ROOT / "tool/lifi_build_config.py"),
                                 "not-a-real-key"], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("not-a-real-key", result.stderr)

    def test_shared_action_passes_each_profile_to_warmup_and_final_build(self):
        action = (ROOT / ".github/actions/generate-assets/action.yml").read_text()
        body = action.split("      id: fetch_and_build\n", 1)[1].split("      run: |\n", 1)[1]
        script = "\n".join(line[8:] if line.startswith("        ") else line
                           for line in body.splitlines())
        for environment, extra in [(p, "") for p in PROFILES] + [
            ("production", " --dart-define=LIFI_INTEGRATOR_NAME=gleec-dex-staging"),
            ("production", " --dart-define=LIFI_INTEGRATOR_ENABLED=false"),
            ("production", " --dart-define=LIFI_INTEGRATOR_FEE_BPS=0"),
            ("production", " --dart-define-from-file=private.env"),
        ]:
            with self.subTest(environment=environment, extra=extra), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                (work / "bin").mkdir()
                (work / "tool").symlink_to(ROOT / "tool", target_is_directory=True)
                flutter = work / "bin/flutter"
                flutter.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$FLUTTER_CALLS\"\n")
                flutter.chmod(0o700)
                for asset in ["coin_icons/png/kmd.png", "config/coins.json", "config/coins_config.json"]:
                    path = work / "sdk/packages/komodo_defi_framework/assets" / asset
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("fixture")
                calls = work / "calls.txt"
                result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script], cwd=work,
                                        env={**build_environment(work, environment), "FLUTTER_CALLS": str(calls),
                                             "BUILD_COMMAND": "flutter build web --no-pub --release" + extra},
                                        capture_output=True, text=True)
                if extra:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(calls.exists(), "Overrides must fail before running Flutter")
                    continue
                self.assertEqual(result.returncode, 0, result.stderr)
                builds = [line for line in calls.read_text().splitlines() if line.startswith("build ")]
                self.assertEqual(len(builds), 2)
                for build in builds:
                    self.assertIn("--dart-define-from-file=" + PROFILES[environment][0], build)
                    self.assertNotIn("LIFI_API_KEY", build)

    def test_docker_passes_the_profile_to_both_builds_and_rejects_unknown_profiles(self):
        for environment in [*PROFILES, "invalid"]:
            with self.subTest(environment=environment), tempfile.TemporaryDirectory() as directory:
                work = Path(directory)
                (work / "bin").mkdir()
                for name in ["tool", ".github"]:
                    (work / name).symlink_to(ROOT / name, target_is_directory=True)
                docker = work / "bin/docker"
                docker.write_text("#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$DOCKER_CALLS\"\n")
                docker.chmod(0o700)
                git = work / "bin/git"
                git.write_text("#!/bin/sh\nif [ \"$1\" = rev-parse ]; then echo abcdef0; fi\nexit 0\n")
                git.chmod(0o700)
                calls = work / "calls.txt"
                result = subprocess.run(["sh", str(ROOT / ".docker/build.sh"), "apk", "release"], cwd=work,
                                        env={**build_environment(work, environment), "DOCKER_CALLS": str(calls)},
                                        capture_output=True, text=True)
                if environment == "invalid":
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(calls.exists())
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    runs = [line for line in calls.read_text().splitlines() if line.startswith("run ")]
                    self.assertEqual(len(runs), 1)
                    self.assertEqual(runs[0].count("--dart-define-from-file=" + PROFILES[environment][0]), 2)


if __name__ == "__main__":
    unittest.main()
