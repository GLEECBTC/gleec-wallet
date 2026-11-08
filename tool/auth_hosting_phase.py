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


def uploaded_files(candidate):
    caches = list((candidate / ".firebase").glob("hosting.*.cache"))
    if len(caches) != 1 or caches[0].name != "hosting.cHVibGlj.cache":
        raise GateError("Fresh hosting upload cache missing or ambiguous")
    files = {}
    for line in caches[0].read_text().splitlines():
        fields = line.rsplit(",", 2)
        if len(fields) != 3:
            raise GateError("Malformed upload cache record")
        path, mtime, digest = fields
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", mtime):
            raise GateError("Malformed upload-cache modification time")
        parsed = PurePosixPath(path)
        if parsed.is_absolute() or ".." in parsed.parts or str(parsed) != path or "\\" in path:
            raise GateError("Invalid upload cache path")
        path = "/" + path
        if path in files or not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise GateError("Duplicate path or invalid upload digest")
        files[path] = digest
    if not files:
        raise GateError("Empty upload cache")
    return files


def expected_version_config(hosting):
    result = {}
    if "appAssociation" in hosting:
        result["appAssociation"] = hosting["appAssociation"]
    if "headers" in hosting:
        result["headers"] = [{"glob": entry["source"], "headers": {value["key"]: value["value"] for value in entry["headers"]}}
                             for entry in hosting["headers"]]
    if "rewrites" in hosting:
        result["rewrites"] = [{"glob": entry["source"], "path": entry["destination"]} for entry in hosting["rewrites"]]
    return result


def verify_uploaded_version(request, version, candidate, hosting, generated):
    expected = uploaded_files(candidate)
    allowed = {"/__/firebase/init.js", "/__/firebase/init.json"}
    if set(generated) - allowed:
        raise GateError("Unexpected generated-file exception")
    for path, digest in generated.items():
        if path in expected or not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise GateError("Invalid generated-file pin")
        expected[path] = digest
    prepared = request(version)
    if prepared.get("status") != "FINALIZED" or prepared.get("config") != expected_version_config(hosting):
        raise GateError("Preview finalization or complete configuration mismatch")
    actual = {}
    page = ""
    pages = set()
    while True:
        query = urllib.parse.urlencode({"status": "ACTIVE", "pageSize": 1000, "pageToken": page})
        result = request(version + "/files?" + query)
        for row in result.get("files", []):
            path, digest = row.get("path"), row.get("hash")
            if not isinstance(path, str) or not path.startswith("/") or path in actual or not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
                raise GateError("Invalid remote file inventory")
            actual[path] = digest
        page = result.get("nextPageToken", "")
        if not page:
            break
        if page in pages:
            raise GateError("Repeated remote inventory page")
        pages.add(page)
    if actual != expected:
        raise GateError("Preview complete file inventory differs from uploaded candidate")


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
            if created_version == "":
                # CLI 15.22.3 can omit this when its API response has a different
                # resource prefix. Bind every uploaded byte and config field.
                created_version = None
            elif re.fullmatch(r"[a-zA-Z0-9]+", created_version):
                created_version = f"sites/{SITE}/versions/{created_version}"
            elif not re.fullmatch(r"sites/gleec-wallet-official/versions/[a-zA-Z0-9]+", created_version):
                raise GateError("Unexpected created version identity")
            preview = request(f"sites/{SITE}/channels/{CHANNEL}")
            version = preview["release"]["version"]["name"]
            if not re.fullmatch(r"sites/gleec-wallet-official/versions/[a-zA-Z0-9]+", version):
                raise GateError("Unexpected preview resource identity")
            if created_version is not None and version != created_version:
                raise GateError("Preview version changed during deployment")
            url = preview["url"]
            if url != completed["url"]:
                raise GateError("Preview URL changed during deployment")
            if not re.fullmatch(r"https://gleec-wallet-official--auth-security-20261108-[a-z0-9]+\.web\.app", url):
                raise GateError("Unexpected preview URL")
            verify_uploaded_version(request, version, destination, hosting, config.get("generatedFiles", {}))
            final_preview = request(f"sites/{SITE}/channels/{CHANNEL}")
            if final_preview["release"]["version"]["name"] != version or final_preview["url"] != url:
                raise GateError("Preview changed during full verification")
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
