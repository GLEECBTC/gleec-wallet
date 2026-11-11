#!/usr/bin/env python3
"""Verify frozen source, hash both web artifacts, and retain a safe source archive.

No publication or signing is performed. The output is local release evidence.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import tarfile
from validate_auth_rollback import NORMAL_DEFINES, ROLLBACK_DEFINES, source_inputs


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    if not __debug__:
        raise SystemExit("Release gates require Python assertions; remove -O/PYTHONOPTIMIZE")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--service-report", required=True, type=Path)
    parser.add_argument("--browser-report", required=True, type=Path)
    parser.add_argument("--lifecycle-report", required=True, type=Path)
    parser.add_argument("--public-build-input-root", required=True, type=Path,
                        help="SDK framework directory containing the recorded public caches")
    parser.add_argument("--validation-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    root = args.candidate.resolve()
    manifest_path = root / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    entries = manifest["files"]
    canonical = json.dumps(entries, sort_keys=True, separators=(",", ":")).encode()
    assert hashlib.sha256(canonical).hexdigest() == manifest["sourceSha256"]
    for entry in entries:
        path = root / "source" / entry["path"]
        assert path.resolve().is_relative_to(root / "source"), "Source path escapes snapshot"
        assert path.stat().st_size == entry["bytes"] and digest(path) == entry["sha256"], \
            f"Frozen source changed: {entry['path']}"
    browser = json.loads(args.browser_report.read_text())
    lifecycle = json.loads(args.lifecycle_report.read_text())
    service = json.loads(args.service_report.read_text())
    assert browser["schema"] == lifecycle["schema"] == service["schema"] == 1
    assert browser["scope"] == "full-app-same-browser-origin-profile"
    assert service["scope"] == "synthetic-engine-and-vault-service-readers"
    assert browser["virtualProvider"] is True and lifecycle["virtualProvider"] is True
    assert service["nativeCryptographyValidated"] is False
    assert browser["sourceSha256"] == manifest["sourceSha256"]
    assert lifecycle["sourceSha256"] == manifest["sourceSha256"]
    assert lifecycle["scope"] == "compiled-app-inactive-resumed-no-hidden"
    assert lifecycle["storedGracePreserved"] is True
    assert len(lifecycle["rounds"]) == 5
    assert {(item["profile"], item["graceSeconds"], item["requestedAwayMs"],
             item["automaticChallenges"]) for item in lifecycle["rounds"]} == {
        ("normal", 30, 29000, 0), ("normal", 30, 31000, 1),
        ("normal", 0, 1000, 1), ("rollback", 0, 1000, 1),
        ("normal-after-rollback", 30, 1000, 0)}
    for item in lifecycle["rounds"]:
        assert item["hiddenImmediately"] is True and item["remainedVisible"] is True
        assert item["privacyPixelsMatched"] is True
        assert 0 <= item["privacyCoverObservedMs"] < 2000
        assert isinstance(item["privacyLabelAvailable"], bool)
        assert item["events"] == ["blur", "focus"]
        assert item["identityPreserved"] is True and item["credentialEnvelopePreserved"] is True
        if item["automaticChallenges"]:
            assert item["cancellationStable"] is True
        if item["requestedAwayMs"] == 29000:
            assert 29000 <= item["elapsedMs"] < 30000
        elif item["requestedAwayMs"] == 31000:
            assert item["elapsedMs"] >= 31000
    assert len(browser["rounds"]) == 6
    assert {(item["kind"], item["profile"]) for item in browser["rounds"]} == {
        (kind, profile) for kind in ("browserLocal", "passkey", "custom-password")
        for profile in ("rollback", "normal")}
    for item in browser["rounds"]:
        assert all(item[name] is True for name in
                   ("identityPreserved", "recoveryPreserved", "credentialEnvelopePreserved"))
        assert item["newEnrollmentDisabled"] is (item["profile"] == "rollback")
        assert item["challenges"] == (1 if item["kind"] == "passkey" else 0)
    assert browser["explicitSignOutPreserved"] is True
    assert [phase["phase"] for phase in service["phases"]] == ["write", "rollback", "upgrade"]
    assert all(phase["passed"] is True and phase["scenarios"] == 19 for phase in service["phases"])
    for phase in service["phases"]:
        assert phase["defines"] == (ROLLBACK_DEFINES if phase["phase"] == "rollback" else NORMAL_DEFINES)
    source_hashes = {entry["path"]: entry["sha256"] for entry in entries}
    overlay_files = []
    overlay_path = root / "validation-overlays.json"
    if overlay_path.exists():
        overlay = json.loads(overlay_path.read_text())
        for item in overlay["files"]:
            assert item["path"].startswith("test_units/"), "Only test fixtures may overlay a frozen runtime"
            assert source_hashes[item["path"]] == item["originalSha256"]
            path = root / item["overlayPath"]
            assert path.resolve().is_relative_to(root / "validation-overlays")
            assert digest(path) == item["sha256"]
            source_hashes[item["path"]] = item["sha256"]
            overlay_files.append(item["overlayPath"])
        overlay_files.append("validation-overlays.json")
    build_inputs_path = root / "web-build-inputs.json"
    build_inputs = json.loads(build_inputs_path.read_text())
    retained_inputs = []
    for item in build_inputs["files"]:
        relative = Path(item["path"])
        assert relative.parts[:2] in (("assets", "config"), ("assets", "coin_icons"), ("web", "kdf"))
        path = args.public_build_input_root / relative
        assert path.resolve().is_relative_to(args.public_build_input_root.resolve())
        assert digest(path) == item["sha256"] and path.stat().st_size == item["bytes"]
        retained_inputs.append((path, f"public-build-inputs/{relative}"))
    validation_names = [
        "tool/prepare_auth_rollback.py", "tool/validate_auth_rollback.py",
        "tool/seal_auth_rollback.py", "tool/test_prepare_auth_rollback.py",
        "tool/test_seal_auth_rollback.py",
        "test_units/services/wallet_access/web_rollback_release.browser.test.js",
        "test_units/services/wallet_access/web_rollback_lifecycle.browser.test.js",
        "test_units/services/wallet_access/rollback_evidence.js",
        "test_units/services/wallet_access/web_release_test_driver.js",
        "test_units/services/wallet_access/web_credential_release.browser.test.js",
        "test_units/services/wallet_access/web_wallet_recovery.browser.test.js",
    ]
    validation_tools = [{"path": name, "sha256": digest(args.validation_root / name)}
                        for name in validation_names]
    tool_hashes = {item["path"]: item["sha256"] for item in validation_tools}
    for report, harness in ((browser, "web_rollback_release.browser.test.js"),
                            (lifecycle, "web_rollback_lifecycle.browser.test.js")):
        expected_names = {f"test_units/services/wallet_access/{name}" for name in
                          (harness, "rollback_evidence.js", "web_release_test_driver.js",
                           "web_credential_release.browser.test.js", "web_wallet_recovery.browser.test.js")}
        assert len(report["validationTools"]) == len(expected_names)
        assert {item["path"] for item in report["validationTools"]} == expected_names
        assert all(tool_hashes[item["path"]] == item["sha256"] for item in report["validationTools"])
    assert service["validationTools"] == [{"path": "tool/validate_auth_rollback.py",
                                           "sha256": tool_hashes["tool/validate_auth_rollback.py"]}]
    retained_validation = [(args.validation_root / name, f"validation-tools/{name}")
                           for name in validation_names]
    expected_inputs = source_inputs(root / "source")
    assert len(service["sourceInputs"]) == len(expected_inputs)
    assert {item["path"] for item in service["sourceInputs"]} == {item["path"] for item in expected_inputs}
    for entry in service["sourceInputs"]:
        assert source_hashes[entry["path"]] == entry["sha256"], \
            f"Tested service source differs from candidate: {entry['path']}"
    artifacts = {}
    for profile in ("normal", "rollback"):
        directory = root / f"{profile}-web"
        assert digest(directory / "main.dart.js") == browser["buildSha256"][profile]
        assert digest(directory / "main.dart.js") == lifecycle["buildSha256"][profile]
        files = [{"path": str(path.relative_to(directory)), "bytes": path.stat().st_size,
                  "sha256": digest(path)} for path in sorted(directory.rglob("*")) if path.is_file()]
        assert not any("debug_data.json" in item["path"] for item in files)
        artifacts[profile] = {"files": files, "directorySha256": hashlib.sha256(
            json.dumps(files, sort_keys=True, separators=(",", ":")).encode()).hexdigest()}
        assert artifacts[profile]["directorySha256"] == browser["buildDirectorySha256"][profile]
        assert artifacts[profile]["directorySha256"] == lifecycle["buildDirectorySha256"][profile]
    archive = root / "source.tar.gz"
    if archive.exists():
        raise SystemExit("Source archive already exists; never overwrite sealed evidence")
    with archive.open("xb") as output, gzip.GzipFile(fileobj=output, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as tar:
            for filename in ["manifest.json", *[f"source/{entry['path']}" for entry in entries], *overlay_files]:
                path = root / filename
                info = tar.gettarinfo(str(path), arcname=filename)
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ""
                info.mode = 0o755 if path.stat().st_mode & 0o111 else 0o644
                with path.open("rb") as content:
                    tar.addfile(info, content)
            for path, filename in [(build_inputs_path, "web-build-inputs.json"), *retained_inputs, *retained_validation]:
                info = tar.gettarinfo(str(path), arcname=filename)
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ""
                info.mode = 0o644
                with path.open("rb") as content:
                    tar.addfile(info, content)
    evidence = {"schema": 1, "sourceSha256": manifest["sourceSha256"],
                "sourceArchiveSha256": digest(archive), "manifestSha256": digest(manifest_path),
                "scope": "local-unsigned-reader-preserving-candidate",
                "productionSigningValidated": False,
                "testOnlyOverlays": json.loads(overlay_path.read_text()) if overlay_path.exists() else None,
                "publicBuildInputsManifestSha256": digest(build_inputs_path),
                "validationTools": validation_tools,
                "serviceReport": service, "browserReport": browser,
                "lifecycleReport": lifecycle, "webArtifacts": artifacts}
    report = root / "candidate-evidence.json"
    with report.open("x") as output:
        output.write(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"evidence": str(report), "sourceArchiveSha256": digest(archive),
                      "evidenceSha256": digest(report)}, indent=2))


if __name__ == "__main__":
    main()
