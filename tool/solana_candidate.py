#!/usr/bin/env python3
"""Bind an isolated Solana test binary and coin snapshot to an evidence manifest.

This writes only the requested output file. It never rewrites the application's
build configuration, downloads an engine, or publishes a coin catalog.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


SCHEMA_VERSION = 1
REFERENCE_ENGINE = "b1ff8f05c880d6f118124cac9ef615aa9d91bb39"
REFERENCE_COINS = "ca20611537fe84f9398d1a63f3d27a4386fb161d"


class CandidateFailure(ValueError):
    """A locally authored manifest diagnostic, safe to expose in reports."""


def require(condition, message):
    if not condition:
        raise CandidateFailure(message)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def full_commit(value: str) -> str:
    require(isinstance(value, str) and re.fullmatch(r"[0-9a-f]{40}", value),
            "Commit identifiers must be full, lowercase 40-character hashes")
    return value


def matches_engine_version(version: str, commit: str) -> bool:
    """Accept only KDF's version tag, never a revision embedded in other text."""
    full_commit(commit)
    if not isinstance(version, str):
        return False
    match = re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.+-]*_([a-f0-9]{7}|[a-f0-9]{40})", version)
    return match is not None and match.group(1) in {commit, commit[:7]}


def create_manifest(binary: Path, coins: Path, engine_commit: str,
                    coins_base_commit: str) -> dict:
    """The snapshot digest also identifies uncommitted candidate catalog edits."""
    require(binary.is_file(), "Candidate KDF binary is missing")
    require(coins.is_file(), "Candidate coin snapshot is missing")
    return {
        "schema_version": SCHEMA_VERSION,
        "engine_commit": full_commit(engine_commit),
        "engine_binary_sha256": sha256_file(binary),
        "coins_base_commit": full_commit(coins_base_commit),
        "coins_snapshot_sha256": sha256_file(coins),
        "scope": "isolated-development-only",
        "production_ready": False,
    }


def load_verified_manifest(path: Path, binary: Path, coins: Path) -> dict:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(manifest, dict), "Candidate manifest must be an object")
    require(manifest.get("schema_version") == SCHEMA_VERSION,
            "Unsupported candidate manifest schema")
    full_commit(manifest.get("engine_commit"))
    full_commit(manifest.get("coins_base_commit"))
    require(manifest.get("scope") == "isolated-development-only"
            and manifest.get("production_ready") is False,
            "This runner accepts only isolated development manifests")
    require(manifest.get("engine_binary_sha256") == sha256_file(binary),
            "Candidate KDF binary does not match the manifest digest")
    require(manifest.get("coins_snapshot_sha256") == sha256_file(coins),
            "Candidate coin snapshot does not match the manifest digest")
    return manifest


def preview_defines(manifest: dict, origin: str) -> dict:
    """Build a reviewable opt-in profile; no public release gate is enabled."""
    from urllib.parse import urlsplit

    try:
        parsed = urlsplit(origin)
        valid = (parsed.scheme in {"http", "https"} and parsed.hostname
                 and parsed.username is None and parsed.password is None
                 and parsed.path in {"", "/"} and not parsed.query
                 and not parsed.fragment and parsed.port is not None
                 and 0 < parsed.port <= 65535
                 and parsed.port != {"http": 80, "https": 443}[parsed.scheme]
                 and not re.search(r"\s|\\", origin))
    except ValueError:
        valid = False
    require(valid, "Preview origin must name a dedicated HTTP(S) host and port")
    origin = origin.rstrip("/")
    digest = manifest["coins_snapshot_sha256"]
    return {
        "SOLANA_ENABLED": True,
        "SOLANA_SPL_MAX_ENABLED": False,
        "SOLANA_TOKEN_2022_ENABLED": False,
        "SOLANA_DEVNET_TRADING_ENABLED": False,
        "SOLANA_KDF_COMMIT": manifest["engine_commit"],
        "SOLANA_COINS_COMMIT": manifest["coins_base_commit"],
        "SOLANA_CATALOG_SHA256": digest,
        "KDF_COINS_STORAGE_NAMESPACE": "solana-preview-" + digest[:12],
        "SOLANA_PREVIEW_ORIGIN": origin,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--kdf", required=True, type=Path)
    parser.add_argument("--coins", required=True, type=Path)
    parser.add_argument("--engine-commit", required=True)
    parser.add_argument("--coins-base-commit", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--defines-output", type=Path)
    parser.add_argument("--preview-origin")
    args = parser.parse_args(argv)
    manifest = create_manifest(args.kdf, args.coins, args.engine_commit,
                               args.coins_base_commit)
    require((args.defines_output is None) == (args.preview_origin is None),
            "Use --defines-output and --preview-origin together")
    require(args.defines_output is None
            or args.defines_output.resolve() != args.output.resolve(),
            "Manifest and defines must use separate output files")
    defines = preview_defines(manifest, args.preview_origin) if args.defines_output else None
    require(not args.output.exists(), "Manifest output already exists")
    require(args.defines_output is None or not args.defines_output.exists(),
            "Defines output already exists")
    # Refuse accidental overwrite of an unrelated existing build configuration.
    with args.output.open("x", encoding="utf-8") as target:
        target.write(json.dumps(manifest, indent=2) + "\n")
    if defines is not None:
        with args.defines_output.open("x", encoding="utf-8") as target:
            target.write(json.dumps(defines, indent=2) + "\n")
    print("Created isolated Solana candidate manifest")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
