"""Public provenance for the explicitly isolated Android internal build."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

apk = Path(sys.argv[1])
root = Path(__file__).resolve().parents[1]
def commit(directory):
    return subprocess.check_output(["git", "-C", str(directory), "rev-parse", "HEAD"], text=True).strip()
record = {
    "schema": 1,
    "app_commit": commit(root),
    "sdk_commit": commit(root / "sdk"),
    "application_id": "com.gleec.gleecdex.onboardinginternal",
    "signing": "Android development signer; internal testing only",
    "artifact_sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
    "run": os.environ.get("GITHUB_RUN_ID"),
    "production_approved": False,
}
(apk.parent / "auth-internal-android.json").write_text(json.dumps(record, indent=2) + "\n")
print("Verified and recorded the separate Android internal testing package.")
