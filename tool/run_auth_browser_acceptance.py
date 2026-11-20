#!/usr/bin/env python3
"""Run the complete browser gate and retain only public pass/fail metadata."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


SUITES = (
    "web_credential_release",
    "web_wallet_recovery",
    "web_missing_data",
    "web_passkey_replacement",
    "web_browser_support",
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", default="node")
    parser.add_argument("--report", type=Path,
                        default=Path("build/auth-browser-acceptance.json"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    commit = os.environ.get("GITHUB_SHA", "")
    report = {"schema": 1, "tested_commit": commit if re.fullmatch(r"[a-f0-9]{40}", commit) else None,
              "lifecycle": True, "all_passed": False, "suites": []}

    def save():
        args.report.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.report.with_suffix(args.report.suffix + ".tmp")
        temporary.write_text(json.dumps(report, indent=2) + "\n")
        temporary.replace(args.report)

    save()
    bundle = root / "build/web/main.dart.js"
    if not bundle.is_file():
        report["build_unavailable"] = True
        save()
        return 1
    report["javascript_sha256"] = hashlib.sha256(bundle.read_bytes()).hexdigest()
    save()
    try:
        version = subprocess.run([args.node, "--version"], check=True,
                                 capture_output=True, text=True).stdout.strip()
        match = re.fullmatch(r"v(\d+)\.\d+\.\d+", version)
        if not match or int(match[1]) < 22:
            report["runtime_unavailable"] = True
            save()
            return 127
    except (OSError, subprocess.CalledProcessError):
        report["runtime_unavailable"] = True
        save()
        return 127

    # Child output stays in the job's normal log. Never capture credentials,
    # provider errors, console output or arbitrary evidence in this artifact.
    environment = dict(os.environ, GLEEC_TEST_LIFECYCLE="true",
                       GLEEC_TEST_EXPECTED_BUILD_SHA256=report["javascript_sha256"])
    for suite in SUITES:
        report["current_suite"] = suite
        save()
        started = time.monotonic()
        result = subprocess.run(
            [args.node, str(root / "test_units/services/wallet_access" /
                            (suite + ".browser.test.js"))],
            cwd=root, env=environment,
        )
        report["suites"].append({"name": suite, "exit_code": result.returncode,
                                 "seconds": round(time.monotonic() - started, 2)})
        save()
        if result.returncode:
            return result.returncode if result.returncode > 0 else 1
    report.pop("current_suite", None)
    if hashlib.sha256(bundle.read_bytes()).hexdigest() != report["javascript_sha256"]:
        report["build_changed_during_validation"] = True
        save()
        return 1
    report["all_passed"] = True
    save()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
