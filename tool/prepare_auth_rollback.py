#!/usr/bin/env python3
"""Freeze an explicit, privacy-filtered mixed-working-tree rollback candidate.

The snapshot contains source, public assets and tests, not build outputs, Git
metadata, local wallet fixtures, profiles, signing keys, .env files or exports.
SDK tracked and nonignored new source is enumerated independently because it is
a dirty submodule. The manifest hashes the copied bytes, not an assumed commit.
"""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

from validate_auth_rollback import GASFREE_DEFINES, NORMAL_DEFINES, ROLLBACK_DEFINES


ROOT_FILES = {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "l10n.yaml",
              "pubspec_overrides.yaml", "firebase.json", ".firebaserc",
              ".metadata", ".fvmrc", "AGENTS.md"}
ROOT_DIRS = {"lib", "assets", "web", "android", "ios", "macos", "linux", "windows",
             "app_theme", "packages", "test", "test_units", "test_integration", "tool"}
SDK_DIRS = {"packages", "app_build", "tool", "scripts", "products", "playground"}
SDK_FILES = {"pubspec.yaml", "pubspec.lock", "analysis_options.yaml", "melos.yaml",
             "l10n.yaml", "AGENTS.md"}
FORBIDDEN_PARTS = {".git", ".dart_tool", ".gradle", ".idea", ".fvm", "build",
                   "node_modules", "Pods", ".symlinks", "ephemeral", "logs", "__pycache__"}
FORBIDDEN_NAMES = {"debug_data.json", "key.properties", "local.properties",
                   "google-services.json", "GoogleService-Info.plist"}
FORBIDDEN_SUFFIXES = {".zip", ".jks", ".keystore", ".p12", ".pfx",
                      ".mobileprovision", ".provisionprofile", ".log",
                      ".p8", ".pem", ".key", ".pyc"}


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args])


def selected(root, sdk=False):
    names = set(git(root, "ls-files", "-z", "--cached").decode().split("\0"))
    names.update(git(root, "ls-files", "-z", "--others", "--exclude-standard")
                 .decode().split("\0"))
    for name in sorted(names):
        item = Path(name)
        if not name or not (root / item).is_file():
            continue
        allowed = SDK_DIRS if sdk else ROOT_DIRS
        files = SDK_FILES if sdk else ROOT_FILES
        if name not in files and item.parts[0] not in allowed:
            continue
        if (set(item.parts) & FORBIDDEN_PARTS or item.name in FORBIDDEN_NAMES or
                item.suffix in FORBIDDEN_SUFFIXES or item.name.startswith(".env") or
                ".local." in item.name):
            continue
        if (root / item).is_symlink():
            raise RuntimeError(f"Source symlinks require explicit review: {name}")
        yield item


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output.resolve()
    if output.exists():
        raise SystemExit("Choose a new output directory; a frozen candidate is never overwritten")
    if root == output or root in output.parents:
        raise SystemExit("Place source snapshots outside the working tree")
    source = output / "source"
    source.mkdir(parents=True)
    entries = []
    for repository, prefix, sdk in [(root, Path(), False), (root / "sdk", Path("sdk"), True)]:
        for relative in selected(repository, sdk):
            target = source / prefix / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(repository / relative, target)
            content = target.read_bytes()
            entries.append({"path": str(prefix / relative), "bytes": len(content),
                            "sha256": hashlib.sha256(content).hexdigest()})
    entries.sort(key=lambda entry: entry["path"])
    canonical = json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()
    manifest = {"schema": 1, "description": "mixed-working-tree reader-preserving rollback candidate",
                "sourceSha256": hashlib.sha256(canonical).hexdigest(),
                "rootBaseCommit": git(root, "rev-parse", "HEAD").decode().strip(),
                "sdkBaseCommit": git(root / "sdk", "rev-parse", "HEAD").decode().strip(),
                "baseCommitsDoNotDescribeDirtySource": True,
                "flutterVersion": "3.41.4", "normalDefines": {**GASFREE_DEFINES, **NORMAL_DEFINES},
                "rollbackDefines": {**GASFREE_DEFINES, **ROLLBACK_DEFINES},
                "browserBuildOptions": ["--release", "--csp", "--no-web-resources-cdn"],
                "excluded": "ignored files; non-source roots; private fixtures; profiles; signing; exports; caches; Git metadata",
                "files": entries}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"snapshot": str(output), "sourceSha256": manifest["sourceSha256"],
                      "files": len(entries)}, indent=2))


if __name__ == "__main__":
    main()
