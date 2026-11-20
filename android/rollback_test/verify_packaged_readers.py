#!/usr/bin/env python3
"""Bind Android rollback reader-retention checks to actual signed APKs.

These markers establish packaging coverage, not cryptographic correctness or
successful recovery. Pair the report with the same-install runtime exercise.
No wallet data, platform error payloads or signing credentials are read.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import zipfile


DART_READERS = (
    "wallet_access_records_v1",
    "wallet_access_pending_v1",
    "wallet_access_last_v1",
    "wallet_access_signed_out_v1",
    "wallet_access_cleanup_v1",
    "wallet_access_grace_seconds_v1",
    "gleec.password-rotation.v1",
    "gleec.wallet/credential_vault",
)
NATIVE_READERS = (
    "gleec_wallet_credential_vault_v1",
    "gleec.wallet.credential.v1.",
    "gleec.wallet/credential_vault",
    "AndroidKeyStore",
    "AES/GCM/NoPadding",
    "prepareDelete",
    "repairInvalidated",
    "perUse",
)
REQUIRED_ABIS = {"arm64-v8a": 183, "armeabi-v7a": 40}
LEGACY_MARKERS = (b"KdfOperationsLocalExecutable", b"--passphrase")
DIAGNOSTIC_MARKERS = (b"wallet_rollback_lifecycle:", b"wallet_delete_result:", b"wallet_delete_guard:")
FORBIDDEN_NAMES = {
    "debug_data.json", "key.properties", "kdf", "mm2", "kdf.exe", "mm2.exe"
}


class VerificationFailure(Exception):
    """Closed, non-secret validation failure."""


def inspect_payloads(payloads: dict[str, bytes]) -> dict:
    """Inspect an APK's public application code and packaged assets."""
    for name in payloads:
        base = PurePosixPath(name).name.lower()
        if base in FORBIDDEN_NAMES or base.endswith((".jks", ".keystore")):
            raise VerificationFailure("forbidden_packaged_file")
    dex = b"".join(payloads[name] for name in sorted(payloads) if name.endswith(".dex"))
    if not dex or any(marker.encode() not in dex for marker in NATIVE_READERS):
        raise VerificationFailure("native_reader_missing")
    abis = {}
    for abi, machine in REQUIRED_ABIS.items():
        app = payloads.get(f"lib/{abi}/libapp.so", b"")
        if any(marker.encode() not in app for marker in DART_READERS):
            raise VerificationFailure("dart_reader_missing")
        if any(marker in app for marker in LEGACY_MARKERS):
            raise VerificationFailure("legacy_executable_marker_present")
        if any(marker in app for marker in DIAGNOSTIC_MARKERS):
            raise VerificationFailure("temporary_diagnostic_marker_present")
        engine = payloads.get(f"lib/{abi}/libkomodo_defi_framework.so", b"")
        if (
            len(engine) < 20
            or engine[:4] != b"\x7fELF"
            or engine[5] != 1
            or int.from_bytes(engine[16:18], "little") != 3
            or int.from_bytes(engine[18:20], "little") != machine
            or any(symbol + b"\0" not in engine for symbol in (
                b"mm2_main", b"mm2_main_status", b"mm2_stop"
            ))
        ):
            raise VerificationFailure("bundled_native_engine_missing_or_invalid")
        abis[abi] = {
            "dartReaderMarkersPresent": True,
            "legacyExecutableMarkersAbsent": True,
            "temporaryDiagnosticMarkersAbsent": True,
            "nativeEnginePresent": True,
            "appLibrarySha256": hashlib.sha256(app).hexdigest(),
            "nativeEngineSha256": hashlib.sha256(engine).hexdigest(),
        }
    return {
        "nativeReaderMarkersPresent": True,
        "nativeBytecodeSha256": hashlib.sha256(dex).hexdigest(),
        "abis": abis,
    }


def inspect_apk(apk: Path, aapt: Path, apksigner: Path) -> dict:
    try:
        with zipfile.ZipFile(apk) as archive:
            names = archive.namelist()
            if len(names) != len(set(names)):
                raise VerificationFailure("duplicate_archive_entry")
            payloads = {name: archive.read(name) for name in names if not name.endswith("/")}
        result = inspect_payloads(payloads)
        package = subprocess.run(
            [str(aapt), "dump", "badging", str(apk)], capture_output=True,
            text=True, check=False, timeout=30,
        )
        match = re.search(r"^package: name='([^']+)' versionCode='([^']+)'", package.stdout, re.M)
        if package.returncode or not match or match[1] != "com.gleec.gleecdex":
            raise VerificationFailure("application_identity_mismatch")
        signed = subprocess.run(
            [str(apksigner), "verify", "--print-certs", str(apk)],
            capture_output=True, text=True, check=False, timeout=30,
        )
        digests = re.findall(r"certificate SHA-256 digest: ([0-9a-fA-F]{64})", signed.stdout)
        if signed.returncode or len(digests) != 1:
            raise VerificationFailure("single_signer_verification_failed")
        result.update({
            "apkSha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
            "applicationId": match[1], "versionCode": match[2],
            "signerSha256": digests[0].lower(),
        })
        return result
    except (OSError, zipfile.BadZipFile, subprocess.TimeoutExpired):
        raise VerificationFailure("artifact_or_tool_unavailable") from None


def verify_pair(normal: Path, rollback: Path, aapt: Path, apksigner: Path) -> dict:
    normal_result = inspect_apk(normal, aapt, apksigner)
    rollback_result = inspect_apk(rollback, aapt, apksigner)
    for field in ("applicationId", "versionCode", "signerSha256"):
        if normal_result[field] != rollback_result[field]:
            raise VerificationFailure("install_identity_not_preserved")
    if normal_result["nativeBytecodeSha256"] != rollback_result["nativeBytecodeSha256"]:
        raise VerificationFailure("native_bytecode_changed_between_profiles")
    for abi in REQUIRED_ABIS:
        if normal_result["abis"][abi]["nativeEngineSha256"] != rollback_result["abis"][abi]["nativeEngineSha256"]:
            raise VerificationFailure("native_engine_changed_between_profiles")
    return {
        "schema": 1, "result": "passed", "sameInstallIdentity": True,
        "normal": normal_result, "rollback": rollback_result,
        "scope": "packaged reader markers and native-library structure; runtime and source-profile verification are separate",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--normal", type=Path, required=True)
    parser.add_argument("--rollback", type=Path, required=True)
    parser.add_argument("--aapt", type=Path, required=True)
    parser.add_argument("--apksigner", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = verify_pair(args.normal, args.rollback, args.aapt, args.apksigner)
    except VerificationFailure as error:
        print(json.dumps({"result": "failed", "code": str(error)}))
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"result": "passed", "sameInstallIdentity": True, "abis": sorted(REQUIRED_ABIS)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
