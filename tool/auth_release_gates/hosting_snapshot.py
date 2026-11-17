"""Read-only, allowlisted Firebase Hosting release evidence. Never export credentials."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request

SITE = "gleec-wallet-official"
BASE = "https://firebasehosting.googleapis.com/v1beta1/"


def main():
    secret = os.environ.pop("HOSTING_SERVICE_ACCOUNT")
    account = json.loads(secret)
    if account.get("project_id") != SITE or account.get("type") != "service_account":
        raise SystemExit("Unexpected service account project or type")
    with tempfile.TemporaryDirectory(prefix="hosting-auth-") as directory:
        credentials = Path(directory, "credentials.json")
        credentials.write_text(secret)
        credentials.chmod(0o600)
        env = dict(os.environ, CLOUDSDK_CONFIG=str(Path(directory, "gcloud")))
        activated = subprocess.run(
            ["gcloud", "auth", "activate-service-account", "--key-file", str(credentials), "--quiet"],
            env=env, capture_output=True,
        )
        if activated.returncode:
            raise SystemExit("Service-account activation failed; credential details suppressed")
        result = subprocess.run(["gcloud", "auth", "print-access-token"], env=env, capture_output=True, text=True)
        if result.returncode:
            raise SystemExit("Service-account token request failed; details suppressed")
        token = result.stdout.strip()

        def get(path):
            request = urllib.request.Request(BASE + path, headers={"Authorization": "Bearer " + token})
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    return json.load(response)
            except urllib.error.HTTPError as error:
                raise SystemExit(f"Hosting metadata request failed with HTTP {error.code}; response suppressed") from None

        releases = get(f"sites/{SITE}/channels/live/releases?pageSize=10").get("releases", [])
        if not releases:
            raise SystemExit("Live release not found")
        current = get(f"sites/{SITE}/channels/live")["release"]
        version_name = current["version"]["name"]
        if not version_name.startswith(f"sites/{SITE}/versions/"):
            raise SystemExit("Unexpected version identity")
        version = get(version_name)
        files = []
        page = ""
        while True:
            query = urllib.parse.urlencode({"status": "ACTIVE", "pageSize": 1000, "pageToken": page})
            result = get(version_name + "/files?" + query)
            files.extend({key: row[key] for key in ("path", "hash", "status") if key in row} for row in result.get("files", []))
            page = result.get("nextPageToken", "")
            if not page:
                break
        site = get(f"projects/{SITE}/sites/{SITE}")
        domain = get(f"projects/{SITE}/sites/{SITE}/customDomains/dex.gleec.com")
        latest = get(f"sites/{SITE}/channels/live")["release"]
        if latest.get("name") != current.get("name") or latest.get("version", {}).get("name") != version_name:
            raise SystemExit("Live release changed during capture; retry required")
        evidence = {
            "site": {key: site[key] for key in ("name", "defaultUrl", "type") if key in site},
            "customDomains": [{key: domain[key] for key in ("name", "hostState", "ownershipState") if key in domain}],
            "currentRelease": {"name": current.get("name"), "version": version_name, "releaseTime": current.get("releaseTime")},
            "releases": [{"name": row.get("name"), "releaseTime": row.get("releaseTime"), "type": row.get("type"), "version": row.get("version", {}).get("name")} for row in releases],
            "version": {key: version[key] for key in ("name", "status", "config", "fileCount", "versionBytes", "createTime", "finalizeTime") if key in version},
            "files": sorted(files, key=lambda row: row["path"]),
        }
        Path("hosting-live-snapshot.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps({"version": version_name, "files": len(files), "readOnly": True}))


if __name__ == "__main__":
    main()
