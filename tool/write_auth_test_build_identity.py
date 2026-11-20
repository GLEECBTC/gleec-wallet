"""Write only public build provenance beside the tested browser bundle."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def commit(path):
    value = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
    if not re.fullmatch(r"[a-f0-9]{40}", value):
        raise ValueError("Unexpected source identity")
    return value


def main():
    root = Path(__file__).resolve().parents[1]
    source = os.environ.get("AUTH_SOURCE_HEAD", commit(root))
    if not re.fullmatch(r"[a-f0-9]{40}", source):
        raise ValueError("Unexpected source head")
    bundle = root / "build/web/main.dart.js"
    clean = all(not subprocess.check_output(
        ["git", "-C", str(directory), "status", "--porcelain", "--untracked-files=no"],
        text=True,
    ).strip() for directory in (root, root / "sdk"))
    if os.environ.get("GITHUB_ACTIONS") == "true" and not clean:
        raise ValueError("The built source differs from its recorded commit")
    record = {
        "schema": 1,
        "feature": "instant-wallet-onboarding",
        "source_head": source,
        "app_merge_commit": commit(root),
        "sdk_commit": commit(root / "sdk"),
        "javascript_sha256": hashlib.sha256(bundle.read_bytes()).hexdigest(),
        "sdk_configuration_sha256": hashlib.sha256((root / "sdk/packages/komodo_defi_framework/app_build/build_config.json").read_bytes()).hexdigest(),
        "run": os.environ.get("GITHUB_RUN_ID"),
        "source_worktree_clean": clean,
        "production_approved": False,
        "physical_device_acceptance": "pending",
    }
    (bundle.parent / "auth-test-build.json").write_text(json.dumps(record, indent=2) + "\n")
    print("Bound the browser bundle to its source and SDK identities.")


if __name__ == "__main__":
    main()
