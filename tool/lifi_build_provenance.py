#!/usr/bin/env python3
"""Record public release inputs and artifact hashes; never read credentials."""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

from lifi_build_config import load_build_defines, require, select_build_config


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def artifact_hashes(root, artifact):
    files = set()
    for match in glob.glob(str(root / artifact)):
        path = Path(match)
        files.update(p for p in (path.rglob("*") if path.is_dir() else [path]) if p.is_file())
    if not files:
        raise ValueError("No build artifacts found; refusing to record a successful build")
    for path in files:
        if not path.resolve().is_relative_to(root / "build"):
            raise ValueError("Build artifacts must remain inside the build directory")
    return {str(path.relative_to(root)).replace(os.sep, "/"): sha256(path)
            for path in sorted(files)}


def checkout_identity(root):
    def git(*args):
        return subprocess.check_output(["git", *args], cwd=root, text=True,
                                       stderr=subprocess.PIPE).strip()

    sdk_commit = git("-C", "sdk", "rev-parse", "HEAD")
    if sdk_commit != git("rev-parse", "HEAD:sdk"):
        raise ValueError("The SDK checkout must match the recorded submodule revision")
    config_path = root / "sdk/packages/komodo_defi_framework/app_build/build_config.json"
    config = json.loads(config_path.read_text())
    return {
        "app_commit": git("rev-parse", "HEAD"),
        "sdk_commit": sdk_commit,
        "kdf_commit": config["api"]["api_commit_hash"],
        "coins_commit": config["coins"]["bundled_coins_repo_commit"],
        "kdf_config_sha256": sha256(config_path),
        "flutter_version": json.loads((root / ".fvmrc").read_text())["flutter"],
    }


DEPENDENCY_FILES = {"wallet-pubspec.lock": "pubspec.lock",
                    "sdk-pubspec.lock": "sdk/pubspec.lock"}


def record(environment, artifact, output, root=Path.cwd()):
    root = root.resolve()
    profile = select_build_config(environment, root)
    hashes = artifact_hashes(root, artifact)
    identity = checkout_identity(root)
    output = root / output
    output.mkdir(parents=True, exist_ok=True)
    dependencies = {}
    for name, source in DEPENDENCY_FILES.items():
        path = root / source
        if path.is_file():
            shutil.copyfile(path, output / name)
            dependencies[name] = sha256(path)
    require("wallet-pubspec.lock" in dependencies, "The resolved Wallet lockfile is required")
    metadata = {
        "schema_version": 1,
        "lifi_environment": environment,
        "lifi_build_defines": load_build_defines(root / profile),
        "lifi_profile_sha256": sha256(root / profile),
        **identity,
        "dependency_snapshots": dependencies,
        "artifact_sha256": hashes,
    }
    (output / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (output / "SHA256SUMS").write_text("".join(f"{digest}  {name}\n" for name, digest in hashes.items()))


def verify(environment, artifact, evidence, expected_commit, root=Path.cwd()):
    """Compare trusted build evidence with the checkout and files to publish.

    This checks consistency, not authenticity or the compiled application's
    behavior. The release owner must obtain the evidence from the trusted build.
    """
    require(bool(re.fullmatch(r"[0-9a-f]{40}", expected_commit or "")),
            "Supply the approved full release commit")
    root = root.resolve()
    profile = select_build_config(environment, root)
    evidence = root / evidence
    metadata = json.loads((evidence / "build.json").read_text())
    require(isinstance(metadata, dict), "Invalid build evidence")
    require(metadata.get("schema_version") == 1, "Unsupported build evidence version")
    require(metadata.get("lifi_environment") == environment, "Build profile does not match")
    require(metadata.get("lifi_build_defines") == load_build_defines(root / profile)
            and metadata.get("lifi_profile_sha256") == sha256(root / profile),
            "Public build profile does not match its evidence")
    identity = checkout_identity(root)
    require(identity["app_commit"] == expected_commit, "Checkout is not the approved release")
    require(all(metadata.get(key) == value for key, value in identity.items()),
            "Checkout inputs do not match the recorded build")
    dependencies = metadata.get("dependency_snapshots")
    require(isinstance(dependencies, dict) and "wallet-pubspec.lock" in dependencies
            and set(dependencies) <= set(DEPENDENCY_FILES), "Invalid dependency evidence")
    for name, digest in dependencies.items():
        require(digest == sha256(evidence / name)
                and digest == sha256(root / DEPENDENCY_FILES[name]),
                "Resolved dependencies do not match the recorded build")
    require(metadata.get("artifact_sha256") == artifact_hashes(root, artifact),
            "Artifact files differ from the recorded build")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("environment")
    parser.add_argument("--artifact", required=True)
    parser.add_argument("--output", default="build-provenance")
    parser.add_argument("--verify", type=Path, help="Verify an existing evidence directory")
    parser.add_argument("--expected-commit", help="Approved full release commit; required with --verify")
    args = parser.parse_args()
    try:
        if args.verify is not None:
            verify(args.environment, args.artifact, args.verify, args.expected_commit)
            print("Public build evidence and artifact verification passed")
        else:
            require(args.expected_commit is None, "Use --expected-commit with --verify")
            record(args.environment, args.artifact, Path(args.output))
    except (ValueError, OSError, subprocess.CalledProcessError):
        # Do not print arbitrary command/configuration data in error paths.
        parser.exit(1, "Public build provenance check failed; verify the release inputs and artifacts\n")


if __name__ == "__main__":
    main()
