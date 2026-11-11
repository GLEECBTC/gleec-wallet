#!/usr/bin/env python3
"""Run real wallet-access readers in three separately compiled Flutter profiles.

All credentials are synthetic, kept in an owner-only temporary directory and
removed on exit. This does not inspect a real application data directory.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROLLBACK_DEFINES = {
    "WALLET_DEVICE_ENROLLMENT_ENABLED": "false",
    "WALLET_PASSKEY_ENROLLMENT_ENABLED": "false",
    "WALLET_IMMEDIATE_LOCK_REQUIRED": "true",
}
NORMAL_DEFINES = {key: ("false" if key.endswith("REQUIRED") else "true")
                  for key in ROLLBACK_DEFINES}
GASFREE_DEFINES = {
    "TRON_GASLESS_ENABLED": "true",
    "TRON_GASLESS_RECEIVE_ENABLED": "true",
    "TRON_GASLESS_BASE_URL": "https://quicknode.gleec.com/gasfree/tron",
    "TRON_GASLESS_SERVICE_PROVIDER": "TLntW9Z59LYY5KEi9cmwk3PKjQga828ird",
}


def source_inputs(root):
    """Exact Dart implementation/dependency/test inputs compiled by this gate."""
    inputs = set()
    for directory in ("lib", "packages", "app_theme", "sdk/packages"):
        inputs.update(path for path in (root / directory).rglob("*.dart")
                      if not {".dart_tool", "build", "example", "test", "test_driver"}
                      .intersection(path.relative_to(root).parts))
    for name in ("pubspec.yaml", "pubspec.lock", "pubspec_overrides.yaml",
                 "test_units/services/wallet_access/rollback_test_support.dart",
                 "test_units/services/wallet_access/wallet_access_rollback_test.dart"):
        inputs.add(root / name)
    return [{"path": str(path.relative_to(root)),
             "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            for path in sorted(inputs)]


def main():
    if not __debug__:
        raise SystemExit("Release gates require Python assertions; remove -O/PYTHONOPTIMIZE")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    report = {"schema": 1, "scope": "synthetic-engine-and-vault-service-readers",
              "nativeCryptographyValidated": False, "phases": []}
    # Bind the executed Dart sources, dependency versions and test adapters to
    # the frozen candidate without assuming a clean Git commit.
    report["sourceInputs"] = source_inputs(args.root)
    report["validationTools"] = [{"path": "tool/validate_auth_rollback.py",
        "sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}]
    with tempfile.TemporaryDirectory(prefix="gleec-auth-rollback-synthetic-") as state:
        for phase in ("write", "rollback", "upgrade"):
            profile = ROLLBACK_DEFINES if phase == "rollback" else NORMAL_DEFINES
            defines = {**GASFREE_DEFINES, **profile,
                       "AUTH_ROLLBACK_PHASE": phase,
                       "AUTH_ROLLBACK_STATE_DIR": state}
            command = [args.flutter, "test", "--no-pub", "--reporter=expanded",
                       "test_units/services/wallet_access/wallet_access_rollback_test.dart"]
            command.extend(f"--dart-define={key}={value}" for key, value in defines.items())
            print(f"Compiling and exercising {phase} profile", flush=True)
            completed = subprocess.run(command, cwd=args.root, text=True, capture_output=True)
            # Never emit fixture contents. Test code only reports booleans and
            # public metadata; no state files are included in the report.
            if completed.returncode:
                print(completed.stdout)
                print(completed.stderr)
                raise SystemExit(completed.returncode)
            files = sorted(Path(state).glob("*.json"))
            assert len(files) == 19, "Every scenario must persist across all three processes"
            report["phases"].append({"phase": phase, "defines": profile,
                                      "scenarios": len(files), "passed": True,
                                      "testOutputSha256": hashlib.sha256(
                                          completed.stdout.encode()).hexdigest()})
            print(f"PASS: {phase}: 19 persisted scenarios and compiled-profile assertion", flush=True)
    assert source_inputs(args.root) == report["sourceInputs"], "Compiled inputs changed during validation"
    assert hashlib.sha256(Path(__file__).read_bytes()).hexdigest() == report["validationTools"][0]["sha256"]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Evidence: {args.report}")


if __name__ == "__main__":
    main()
