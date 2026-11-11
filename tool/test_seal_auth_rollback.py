"""Negative controls for sealing rollback evidence, using only synthetic files."""

import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest

from validate_auth_rollback import NORMAL_DEFINES, ROLLBACK_DEFINES, source_inputs


SEALER = Path(__file__).with_name("seal_auth_rollback.py")
WALLET_TESTS = "test_units/services/wallet_access/"
VALIDATION_FILES = (
    "tool/prepare_auth_rollback.py",
    "tool/validate_auth_rollback.py",
    "tool/seal_auth_rollback.py",
    "tool/test_prepare_auth_rollback.py",
    "tool/test_seal_auth_rollback.py",
    WALLET_TESTS + "web_rollback_release.browser.test.js",
    WALLET_TESTS + "web_rollback_lifecycle.browser.test.js",
    WALLET_TESTS + "rollback_evidence.js",
    WALLET_TESTS + "web_release_test_driver.js",
    WALLET_TESTS + "web_credential_release.browser.test.js",
    WALLET_TESTS + "web_wallet_recovery.browser.test.js",
)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_hash(value):
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value)


def write_json(path, value):
    write(path, json.dumps(value, indent=2) + "\n")


def file_records(root):
    return [{"path": str(path.relative_to(root)), "bytes": path.stat().st_size,
             "sha256": sha256(path)}
            for path in sorted(root.rglob("*")) if path.is_file()]


class SealEvidenceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="gleec-seal-synthetic-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.candidate = self.root / "candidate"
        self.source = self.candidate / "source"
        self.validation = self.root / "validation"
        self.public_inputs = self.root / "public-inputs"

        for name in (
            "lib/reader.dart", "packages/test_vault/lib/vault.dart",
            "pubspec.yaml", "pubspec.lock", "pubspec_overrides.yaml",
            WALLET_TESTS + "rollback_test_support.dart",
            WALLET_TESTS + "wallet_access_rollback_test.dart",
        ):
            write(self.source / name, "Synthetic source fixture: " + name + "\n")
        entries = file_records(self.source)
        self.source_hash = canonical_hash(entries)
        write_json(self.candidate / "manifest.json", {
            "schema": 1, "sourceSha256": self.source_hash, "files": entries,
        })
        for name in VALIDATION_FILES:
            write(self.validation / name, "Synthetic validation fixture: " + name + "\n")

        self.build_hashes = {}
        self.directory_hashes = {}
        for profile in ("normal", "rollback"):
            build = self.candidate / (profile + "-web")
            write(build / "main.dart.js", "// Synthetic " + profile + " compilation\n")
            write(build / "services/wallet_credentials.js", "// Synthetic credential reader\n")
            write(build / "index.html", "<!doctype html><title>Synthetic release</title>\n")
            self.build_hashes[profile] = sha256(build / "main.dart.js")
            self.directory_hashes[profile] = canonical_hash(file_records(build))

        write_json(self.public_inputs / "assets/config/coins.json", {"synthetic": True})
        write_json(self.candidate / "web-build-inputs.json", {
            "files": file_records(self.public_inputs),
        })
        self.service = {
            "schema": 1, "scope": "synthetic-engine-and-vault-service-readers",
            "nativeCryptographyValidated": False,
            "sourceInputs": source_inputs(self.source),
            "validationTools": self.tool_hashes(["tool/validate_auth_rollback.py"]),
            "phases": [{"phase": phase, "passed": True, "scenarios": 19,
                        "defines": ROLLBACK_DEFINES if phase == "rollback" else NORMAL_DEFINES}
                       for phase in ("write", "rollback", "upgrade")],
        }
        self.browser = {
            **self.browser_provenance("web_rollback_release.browser.test.js"),
            "scope": "full-app-same-browser-origin-profile",
            "explicitSignOutPreserved": True,
            "rounds": [{"kind": kind, "profile": profile,
                        "identityPreserved": True, "recoveryPreserved": True,
                        "credentialEnvelopePreserved": True,
                        "newEnrollmentDisabled": profile == "rollback",
                        "challenges": 1 if kind == "passkey" else 0}
                       for kind in ("browserLocal", "passkey", "custom-password")
                       for profile in ("rollback", "normal")],
        }
        self.lifecycle = {
            **self.browser_provenance("web_rollback_lifecycle.browser.test.js"),
            "scope": "compiled-app-inactive-resumed-no-hidden",
            "storedGracePreserved": True,
            "rounds": [{"profile": profile, "graceSeconds": grace,
                        "requestedAwayMs": away, "elapsedMs": away + 10,
                        "automaticChallenges": challenges,
                        "hiddenImmediately": True, "remainedVisible": True,
                        "events": ["blur", "focus"], "identityPreserved": True,
                        "credentialEnvelopePreserved": True,
                        "cancellationStable": bool(challenges),
                        "privacyPixelsMatched": True, "privacyCoverObservedMs": 50,
                        "privacyLabelAvailable": True}
                       for profile, grace, away, challenges in (
                           ("normal", 30, 29000, 0), ("normal", 30, 31000, 1),
                           ("normal", 0, 1000, 1), ("rollback", 0, 1000, 1),
                           ("normal-after-rollback", 30, 1000, 0))],
        }

    def tool_hashes(self, names):
        return [{"path": name, "sha256": sha256(self.validation / name)} for name in names]

    def browser_provenance(self, harness):
        names = [WALLET_TESTS + name for name in (
            harness, "rollback_evidence.js", "web_release_test_driver.js",
            "web_credential_release.browser.test.js", "web_wallet_recovery.browser.test.js",
        )]
        return {"schema": 1, "sourceSha256": self.source_hash, "virtualProvider": True,
                "buildSha256": self.build_hashes.copy(),
                "buildDirectorySha256": self.directory_hashes.copy(),
                "validationTools": self.tool_hashes(names)}

    def seal(self, python_flags=(), environment=None):
        for name in ("service", "browser", "lifecycle"):
            write_json(self.root / (name + ".json"), getattr(self, name))
        command = [sys.executable, *python_flags, str(SEALER), str(self.candidate)]
        for name in ("service", "browser", "lifecycle"):
            command.extend(["--" + name + "-report", str(self.root / (name + ".json"))])
        command.extend(["--public-build-input-root", str(self.public_inputs),
                        "--validation-root", str(self.validation)])
        env = os.environ.copy()
        env.pop("PYTHONOPTIMIZE", None)
        env.update(environment or {})
        return subprocess.run(command, capture_output=True, text=True, env=env, timeout=15)

    def assert_rejected(self, result, reason="AssertionError"):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(reason, result.stderr)
        self.assertFalse((self.candidate / "source.tar.gz").exists(), result.stderr)
        self.assertFalse((self.candidate / "candidate-evidence.json").exists(), result.stderr)

    def test_complete_synthetic_evidence_seals_without_unrelated_private_files(self):
        # These are synthetic sentinels, never real profiles or credentials.
        write(self.candidate / "browser-profile/private-marker.txt", "synthetic profile sentinel")
        write(self.candidate / "fixture-state/private-marker.json", "synthetic fixture sentinel")
        result = self.seal()
        self.assertEqual(result.returncode, 0, result.stderr)
        evidence = json.loads((self.candidate / "candidate-evidence.json").read_text())
        archive = self.candidate / "source.tar.gz"
        self.assertEqual(evidence["sourceSha256"], self.source_hash)
        self.assertEqual(evidence["sourceArchiveSha256"], sha256(archive))
        self.assertIs(evidence["productionSigningValidated"], False)
        self.assertNotEqual(self.build_hashes["normal"], self.build_hashes["rollback"])
        with tarfile.open(archive) as content:
            names = content.getnames()
            self.assertIn("source/lib/reader.dart", names)
            self.assertIn("public-build-inputs/assets/config/coins.json", names)
            self.assertIn("validation-tools/" + WALLET_TESTS + "rollback_evidence.js", names)
            self.assertFalse(any("private-marker" in name for name in names))
            self.assertTrue(all(member.uid == member.gid == member.mtime == 0
                                for member in content.getmembers()))

    def test_changed_non_main_credential_artifact_is_rejected(self):
        artifact = self.candidate / "rollback-web/services/wallet_credentials.js"
        write(artifact, "// Replaced credential reader after validation\n")
        self.assertEqual(sha256(self.candidate / "rollback-web/main.dart.js"),
                         self.build_hashes["rollback"])
        self.assert_rejected(self.seal())

    def test_changed_execution_harness_or_helper_is_rejected(self):
        for name in (WALLET_TESTS + "web_rollback_release.browser.test.js",
                     WALLET_TESTS + "web_rollback_lifecycle.browser.test.js",
                     WALLET_TESTS + "web_release_test_driver.js",
                     WALLET_TESTS + "rollback_evidence.js",
                     "tool/validate_auth_rollback.py"):
            with self.subTest(name=name):
                path = self.validation / name
                original = path.read_text()
                write(path, "// Changed after report generation\n")
                self.assert_rejected(self.seal())
                write(path, original)

    def test_missing_source_inputs_are_rejected(self):
        original = self.service["sourceInputs"]
        for entries in ([], original[:-1]):
            with self.subTest(count=len(entries)):
                self.service["sourceInputs"] = entries
                self.assert_rejected(self.seal())

    def test_false_or_non_boolean_browser_results_are_rejected(self):
        for field in ("identityPreserved", "recoveryPreserved", "credentialEnvelopePreserved",
                      "newEnrollmentDisabled"):
            for value in (False, "true"):
                with self.subTest(field=field, value=value):
                    self.browser["rounds"][0][field] = value
                    self.assert_rejected(self.seal())
                    self.browser["rounds"][0][field] = True

    def test_duplicate_browser_round_is_rejected(self):
        original = copy.deepcopy(self.browser["rounds"])
        for rounds in (original + [original[0]], original[:-1] + [original[0]]):
            with self.subTest(count=len(rounds)):
                self.browser["rounds"] = rounds
                self.assert_rejected(self.seal())

    def test_missing_or_late_privacy_cover_evidence_is_rejected(self):
        for field, value in (("privacyPixelsMatched", False),
                             ("privacyCoverObservedMs", 2000)):
            with self.subTest(field=field):
                original = self.lifecycle["rounds"][0][field]
                self.lifecycle["rounds"][0][field] = value
                self.assert_rejected(self.seal())
                self.lifecycle["rounds"][0][field] = original

    def test_optimized_execution_is_refused(self):
        for flags, environment in ((("-O",), {}), ((), {"PYTHONOPTIMIZE": "1"})):
            with self.subTest(flags=flags, environment=environment):
                result = self.seal(flags, environment)
                self.assert_rejected(result, reason="remove -O/PYTHONOPTIMIZE")


if __name__ == "__main__":
    unittest.main()
