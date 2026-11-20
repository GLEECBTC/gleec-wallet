#!/usr/bin/env python3
"""Reject local wallet fixtures in built artifacts without reading their data."""

from __future__ import annotations

import argparse
from pathlib import Path, PurePosixPath
import sys
import zipfile


FORBIDDEN_NAMES = frozenset({"debug_data.json", "key.properties"})
ARCHIVE_SUFFIXES = frozenset({".apk", ".aab", ".ipa", ".zip"})


def is_forbidden(name: str) -> bool:
    normalized = name.replace("\\", "/")
    leaf = PurePosixPath(normalized).name.lower()
    return leaf in FORBIDDEN_NAMES or leaf.endswith((".jks", ".keystore"))


def verify(path: Path) -> None:
    if not path.exists():
        raise ValueError("Requested build artifact does not exist")
    if path.is_dir():
        for child in path.rglob("*"):
            if is_forbidden(child.name):
                raise ValueError("Build contains a local wallet fixture or signing file")
            if child.is_file() and child.suffix.lower() in ARCHIVE_SUFFIXES:
                verify(child)
    elif path.suffix.lower() in ARCHIVE_SUFFIXES:
        with zipfile.ZipFile(path) as archive:
            if any(is_forbidden(name) for name in archive.namelist()):
                raise ValueError("Build contains a local wallet fixture or signing file")
    elif is_forbidden(path.name):
        raise ValueError("Build contains a local wallet fixture or signing file")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifacts", nargs="+", type=Path)
    args = parser.parse_args()
    try:
        for artifact in args.artifacts:
            verify(artifact)
    except (OSError, ValueError, zipfile.BadZipFile):
        # Never include rejected filenames, archive data, or raw platform errors.
        print("Artifact privacy check failed: missing/invalid artifact or local private fixture present.", file=sys.stderr)
        return 1
    print(f"Artifact privacy check passed for {len(args.artifacts)} build artifact(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
