#!/usr/bin/env python3
"""Reject APKs advertising architectures without the wallet's native runtime.

Usage: python3 android/verify_apk.py build/app/outputs/flutter-apk/app-release.apk
"""

import argparse
from pathlib import Path
import sys
import zipfile
import zlib


SUPPORTED_ABIS = frozenset({"armeabi-v7a", "arm64-v8a"})
REQUIRED_LIBRARIES = frozenset(
    {"libapp.so", "libflutter.so", "libkomodo_defi_framework.so"}
)


class ApkValidationError(ValueError):
    """The APK cannot run the wallet on every architecture it advertises."""


def verify_apk(path: Path) -> None:
    try:
        with zipfile.ZipFile(path) as archive:
            entries = [entry for entry in archive.infolist() if not entry.is_dir()]
            names = [entry.filename for entry in entries]
            if len(names) != len(set(names)):
                raise ApkValidationError("APK contains duplicate archive entries")
            if "AndroidManifest.xml" not in names:
                raise ApkValidationError("APK is missing AndroidManifest.xml")

            native_entries = {}
            for entry in entries:
                if not entry.filename.startswith("lib/"):
                    continue
                parts = entry.filename.split("/")
                if len(parts) != 3 or not parts[1] or not parts[2]:
                    raise ApkValidationError(
                        f"Malformed native library path: {entry.filename}"
                    )
                native_entries.setdefault(parts[1], {})[parts[2]] = entry

            actual_abis = set(native_entries)
            if actual_abis != SUPPORTED_ABIS:
                missing = ", ".join(sorted(SUPPORTED_ABIS - actual_abis)) or "none"
                extra = ", ".join(sorted(actual_abis - SUPPORTED_ABIS)) or "none"
                raise ApkValidationError(
                    f"APK ABI mismatch (missing: {missing}; unsupported: {extra})"
                )

            for abi in sorted(SUPPORTED_ABIS):
                libraries = native_entries[abi]
                for library in sorted(REQUIRED_LIBRARIES):
                    entry = libraries.get(library)
                    if entry is None or entry.file_size == 0:
                        raise ApkValidationError(
                            f"APK is missing a nonempty lib/{abi}/{library}"
                        )

            corrupt_entry = archive.testzip()
            if corrupt_entry is not None:
                raise ApkValidationError(f"APK has a corrupt entry: {corrupt_entry}")
    except (OSError, zipfile.BadZipFile, zlib.error, RuntimeError, NotImplementedError) as error:
        raise ApkValidationError(f"Cannot read APK: {error}") from error


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path, help="Release APK to verify")
    args = parser.parse_args()
    try:
        verify_apk(args.apk)
    except ApkValidationError as error:
        print(f"APK validation failed: {error}", file=sys.stderr)
        return 1
    print("APK verified: ARM32/ARM64 each contain Flutter, app AOT, and KDF libraries")
    return 0


if __name__ == "__main__":
    sys.exit(main())
