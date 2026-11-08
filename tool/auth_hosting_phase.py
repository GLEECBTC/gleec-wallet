"""Fixed-site hosting preview/promotion with exact release preconditions."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

SITE = "gleec-wallet-official"
BASE = "https://firebasehosting.googleapis.com/v1beta1/"
CHANNEL = "auth-security-20261108"


class GateError(ValueError):
    """A static diagnostic that is safe to report without provider details."""


def main():
    config = json.loads(Path("hosting-operation.json").read_text())
    if config["mode"] not in ("preview", "promote"):
        raise GateError("Unexpected operation")
    for key in ("expectedLiveVersion",):
        if not re.fullmatch(r"sites/gleec-wallet-official/versions/[a-zA-Z0-9]+", config[key]):
            raise GateError("Invalid version identity")
    account_text = os.environ.pop("HOSTING_SERVICE_ACCOUNT")
    account = json.loads(account_text)
    if account.get("project_id") != SITE or account.get("type") != "service_account":
        raise GateError("Unexpected service account project or type")
    with tempfile.TemporaryDirectory(prefix="hosting-phase-") as directory:
        credentials = Path(directory, "credentials.json")
        credentials.write_text(account_text)
        credentials.chmod(0o600)
        env = dict(os.environ, CLOUDSDK_CONFIG=str(Path(directory, "gcloud")),
                   GOOGLE_APPLICATION_CREDENTIALS=str(credentials))
        result = subprocess.run(["gcloud", "auth", "activate-service-account", "--key-file", str(credentials), "--quiet"], env=env, capture_output=True)
        if result.returncode:
            raise RuntimeError("Service-account activation failed")
        result = subprocess.run(["gcloud", "auth", "print-access-token"], env=env, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError("Service-account token request failed")
        token = result.stdout.strip()

        def request(path, body=None):
            headers = {"Authorization": "Bearer " + token}
            data = None
            if body is not None:
                headers["Content-Type"] = "application/json"
                data = json.dumps(body).encode()
            req = urllib.request.Request(BASE + path, data=data, headers=headers)
            with urllib.request.urlopen(req, timeout=60) as response:
                return json.load(response)

        def current(channel="live"):
            return request(f"sites/{SITE}/channels/{channel}")["release"]["version"]["name"]

        def guard_live():
            if current() != config["expectedLiveVersion"]:
                raise GateError("Live release changed; operation rejected")
            with urllib.request.urlopen("https://dex.gleec.com/main.dart.js", timeout=120) as response:
                if hashlib.file_digest(response, "sha256").hexdigest() != config["expectedLiveMainSha256"]:
                    raise GateError("Live application changed; operation rejected")
            if current() != config["expectedLiveVersion"]:
                raise GateError("Live release changed during content check")

        print("Checking unchanged live release")
        guard_live()
        if config["mode"] == "preview":
            print("Validating exact static candidate")
            archive_path = Path("hosting-candidate.zip")
            with archive_path.open("rb") as source:
                if hashlib.file_digest(source, "sha256").hexdigest() != config["candidateSha256"]:
                    raise GateError("Candidate digest mismatch")
            destination = Path(directory, "candidate")
            destination.mkdir()
            with zipfile.ZipFile(archive_path) as archive:
                names = archive.namelist()
                if len(names) != len(set(names)):
                    raise GateError("Duplicate archive entry")
                if not {"firebase.json", "public/index.html", "public/main.dart.js", "public/flutter_bootstrap.js", "public/.well-known/apple-app-site-association"}.issubset(names):
                    raise GateError("Required hosting files missing")
                total = 0
                for entry in archive.infolist():
                    path = PurePosixPath(entry.filename)
                    if path.is_absolute() or ".." in path.parts or "\\" in entry.filename or stat.S_ISLNK(entry.external_attr >> 16):
                        raise GateError("Unsafe archive path")
                    if str(path) != entry.filename.rstrip("/"):
                        raise GateError("Non-canonical archive path")
                    if entry.filename != "firebase.json" and not entry.filename.startswith("public/"):
                        raise GateError("Unexpected archive member")
                    total += entry.file_size
                    if total > 1024 * 1024 * 1024:
                        raise GateError("Oversized hosting candidate")
                archive.extractall(destination)
            firebase_config = json.loads((destination / "firebase.json").read_text())
            if set(firebase_config) != {"hosting"}:
                raise GateError("Non-hosting configuration rejected")
            hosting = firebase_config["hosting"]
            if not isinstance(hosting, dict) or hosting.get("site") != SITE or hosting.get("public") != "public" or "target" in hosting:
                raise GateError("Unexpected hosting destination")
            if set(hosting) - {"site", "public", "appAssociation", "ignore", "headers", "rewrites"}:
                raise GateError("Unexpected hosting behavior or deploy hooks")
            for rewrite in hosting.get("rewrites", []):
                if set(rewrite) != {"source", "destination"} or not rewrite["destination"].startswith("/"):
                    raise GateError("Dynamic or external hosting rewrite rejected")
            command = ["npx", "--yes", "firebase-tools@15.22.3", "hosting:channel:deploy", CHANNEL,
                       "--project", SITE, "--config", str(destination / "firebase.json"),
                       "--expires", "7d", "--non-interactive", "--no-authorized-domains", "--json"]
            print("Deploying isolated preview")
            result = subprocess.run(command, env=env, cwd=destination, capture_output=True, text=True, timeout=1200)
            if result.returncode:
                raise RuntimeError("Hosting preview deployment failed; command output suppressed")
            print("Verifying returned preview identity")
            output = json.loads(result.stdout)
            if output.get("status") != "success" or set(output["result"]) != {SITE}:
                raise GateError("Unexpected deployment result")
            completed = output["result"][SITE]
            created_version = completed["version"]
            if re.fullmatch(r"[a-zA-Z0-9]+", created_version):
                created_version = f"sites/{SITE}/versions/{created_version}"
            elif not re.fullmatch(r"sites/gleec-wallet-official/versions/[a-zA-Z0-9]+", created_version):
                raise GateError("Unexpected created version identity")
            preview = request(f"sites/{SITE}/channels/{CHANNEL}")
            version = preview["release"]["version"]["name"]
            if version != created_version:
                raise GateError("Preview version changed during deployment")
            url = preview["url"]
            if url != completed["url"]:
                raise GateError("Preview URL changed during deployment")
            if not re.fullmatch(r"https://gleec-wallet-official--auth-security-20261108-[a-z0-9]+\.web\.app", url):
                raise GateError("Unexpected preview URL")
            if current() != config["expectedLiveVersion"]:
                raise GateError("Live version changed during preview")
            evidence = {"mode": "preview", "url": url, "version": version,
                        "rollbackVersion": config["expectedLiveVersion"], "candidateSha256": config["candidateSha256"]}
        else:
            version = config["previewVersion"]
            if not re.fullmatch(r"sites/gleec-wallet-official/versions/[a-zA-Z0-9]+", version):
                raise GateError("Unexpected preview identity")
            if current(CHANNEL) != version:
                raise GateError("Preview release changed; promotion rejected")
            prepared = request(version)
            if prepared.get("status") != "FINALIZED":
                raise GateError("Preview version is not finalized")
            guard_live()
            query = urllib.parse.urlencode({"versionName": version})
            try:
                release = request(f"sites/{SITE}/releases?{query}", {"message": "Browser security only; preserved October 20 wallet features and engine"})
            except (urllib.error.URLError, TimeoutError):
                # A lost response can follow a successful release. Reconcile
                # the exact target; never retry or undo an unknown write.
                release = request(f"sites/{SITE}/channels/live")["release"]
                if release.get("version", {}).get("name") != version:
                    raise RuntimeError("Promotion response lost; current version requires review") from None
            if current() != version:
                raise GateError("Live release verification failed")
            evidence = {"mode": "promote", "url": "https://dex.gleec.com", "version": version,
                        "release": release.get("name"), "rollbackVersion": config["expectedLiveVersion"]}
        Path("hosting-operation-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(json.dumps(evidence))


if __name__ == "__main__":
    try:
        main()
    except GateError as error:
        raise SystemExit("Hosting gate rejected operation: " + str(error)) from None
    except Exception as error:
        raise SystemExit("Hosting operation failed (" + type(error).__name__ + "); sensitive details suppressed") from None
