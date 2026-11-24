#!/usr/bin/env python3
"""Run the signed internal passkey bridge contract checks on an emulator."""

import argparse
import os
from pathlib import Path
import re
import subprocess


APP = "com.gleec.gleecdex.onboardinginternal"
RUNNER = "com.gleec.gleecdex.PasskeyBridgeInstrumentation"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--apkanalyzer", default="apkanalyzer")
    parser.add_argument("--serial", required=True, help="An emulator serial, such as emulator-5554")
    parser.add_argument("--apk", required=True, type=Path)
    parser.add_argument("--test-apk", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"emulator-\d+", args.serial):
        parser.error("Use a disposable emulator serial.")

    try:
        # Validate packaging before installing, even on a disposable device.
        for artifact, expected in ((args.apk, APP), (args.test_apk, APP + ".test")):
            package = subprocess.check_output(
                [args.apkanalyzer, "manifest", "application-id", os.fspath(artifact)],
                text=True, timeout=30,
            ).strip()
            if package != expected:
                parser.error(f"{artifact.name} must use package {expected}.")
        adb = [args.adb, "-s", args.serial]
        is_emulator = subprocess.check_output(
            [*adb, "shell", "getprop", "ro.kernel.qemu"], text=True, timeout=10,
        ).strip()
        if is_emulator != "1":
            parser.error("The selected Android target must be an emulator.")

        for artifact in (args.apk, args.test_apk):
            subprocess.run(
                [*adb, "install", "-r", os.fspath(artifact)], check=True, timeout=120,
            )
        result = subprocess.run(
            [*adb, "shell", "am", "instrument", "-w", "-r", f"{APP}.test/{RUNNER}"],
            check=True, capture_output=True, text=True, timeout=90,
        )
    except (OSError, subprocess.SubprocessError) as error:
        print(f"Android bridge runner could not complete ({type(error).__name__})")
        return 1
    # The runner emits only test status and a redacted invariant label.
    print(result.stdout.strip())
    return 0 if ("INSTRUMENTATION_RESULT: passkey_bridge=passed" in result.stdout
                 and "INSTRUMENTATION_CODE: -1" in result.stdout) else 1


if __name__ == "__main__":
    raise SystemExit(main())
