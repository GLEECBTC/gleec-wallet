"""Publish fixed native-library archives without replacing existing releases.

The legacy file-server route has no operator-provided SSH host pin. This job
records its TOFU fingerprint; independent HTTPS digest validation is mandatory.
No private source or credential material is included in the upload.
"""
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import urllib.request
import uuid
import zipfile

import paramiko

COMMIT = "f9632e0ec771668a6f21b37aede01a30110141cb"
NAMES = {
    f"kdf-macos-universal2-{COMMIT}-native-v1.zip": "libkdflib.dylib",
    f"kdf_{COMMIT}-linux-x86-64-native-v1.zip": "libkdflib.so",
}
REMOTE = "/uploads/main/"
HTTPS = "https://devbuilds.gleec.com/main/"
PUBLIC_HEADERS = {
    "User-Agent": "GleecWalletReleaseValidation/1.0 (+https://github.com/GLEECBTC/gleec-wallet)",
    "Accept": "*/*",
}


def digest(stream):
    result = hashlib.sha256()
    while block := stream.read(1024 * 1024):
        result.update(block)
    return result.hexdigest()


def validate(manifest):
    if manifest.get("sourceCommit") != COMMIT or set(manifest.get("artifacts", {})) != set(NAMES):
        raise ValueError("Unexpected publication manifest identity")
    for name, library in NAMES.items():
        path = Path("artifacts", name)
        expected = manifest["artifacts"][name]
        if not isinstance(expected, str) or len(expected) != 64:
            raise ValueError("Invalid expected digest")
        with path.open("rb") as source:
            if digest(source) != expected:
                raise ValueError("Local archive digest mismatch")
        with zipfile.ZipFile(path) as archive:
            members = archive.namelist()
            if len(members) != len(set(members)) or set(members) != {"kdf", library}:
                raise ValueError("Unexpected archive entries")
            for info in archive.infolist():
                if stat.S_ISLNK(info.external_attr >> 16):
                    raise ValueError("Archive symlink rejected")


def main():
    manifest = json.loads(Path("native-publication.json").read_text())
    validate(manifest)
    key_text = os.environ.pop("FILE_SERVER_KEY")
    key = None
    for kind in (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey):
        try:
            key = kind.from_private_key(io.StringIO(key_text))
            break
        except (paramiko.SSHException, ValueError):
            continue
    if key is None:
        raise ValueError("Unsupported file-server key format")
    client = paramiko.SSHClient()
    # Same TOFU trust model as the existing file-server publisher; the observed
    # key is retained only in this process and must not be called a trusted pin.
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    evidence = {"sourceCommit": COMMIT, "sshHostTrust": "TOFU", "artifacts": {}}
    try:
        client.connect(os.environ["FILE_SERVER_HOST"], port=int(os.environ["FILE_SERVER_PORT"]),
                       username=os.environ["FILE_SERVER_USERNAME"], pkey=key,
                       allow_agent=False, look_for_keys=False, timeout=30, auth_timeout=30, banner_timeout=30)
        server_key = client.get_transport().get_remote_server_key()
        evidence["observedHostKeySha256"] = base64.b64encode(hashlib.sha256(server_key.asbytes()).digest()).decode().rstrip("=")
        with client.open_sftp() as sftp:
            sftp.get_channel().settimeout(120)
            for name in NAMES:
                expected = manifest["artifacts"][name]
                final = REMOTE + name
                try:
                    sftp.stat(final)
                except FileNotFoundError:
                    pass
                else:
                    # Re-running after partial publication is read-only for
                    # any existing final file, and still verifies its bytes.
                    with sftp.open(final, "rb") as existing:
                        existing.prefetch(max_concurrent_requests=64)
                        if digest(existing) != expected:
                            raise ValueError("Existing artifact has different bytes")
                    continue
                staging = REMOTE + "." + name + "." + uuid.uuid4().hex + ".upload"
                created = False
                try:
                    with sftp.open(staging, "wx") as destination:
                        created = True
                        destination.set_pipelined(True)
                        with Path("artifacts", name).open("rb") as source:
                            while block := source.read(1024 * 1024):
                                destination.write(block)
                    with sftp.open(staging, "rb") as uploaded:
                        uploaded.prefetch(max_concurrent_requests=64)
                        if digest(uploaded) != expected:
                            raise ValueError("Staged upload digest mismatch")
                    sftp.chmod(staging, 0o644)
                    # Standard SFTP rename requires a nonexistent destination.
                    # Never use posix_rename, which can overwrite releases.
                    sftp.rename(staging, final)
                    created = False
                finally:
                    if created:
                        sftp.remove(staging)
    finally:
        client.close()
    for name in NAMES:
        request = urllib.request.Request(HTTPS + name, headers=PUBLIC_HEADERS)
        with urllib.request.urlopen(request, timeout=120) as response:
            final_url = response.geturl()
            if not final_url.startswith(HTTPS):
                raise ValueError("Unexpected HTTPS artifact redirect")
            actual = digest(response)
        if actual != manifest["artifacts"][name]:
            raise ValueError("Published HTTPS digest mismatch")
        evidence["artifacts"][name] = {"sha256": actual, "url": HTTPS + name}
    Path("native-publication-evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print("Both immutable artifacts verified through HTTPS")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # SSH/authentication exceptions may contain deployment configuration.
        raise SystemExit("Native publication failed (" + type(error).__name__ + "); details suppressed") from None
