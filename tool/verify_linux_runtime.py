"""Reject missing Linux dependencies and binaries above the supported glibc ABI."""
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
if not root.is_dir():
    raise SystemExit("Missing Linux application bundle")
binaries = [path for path in root.rglob("*")
            if path.is_file() and (path.suffix == ".so" or path.name == "GleecDEX")]
if not binaries or not (root / "lib/libkdflib.so").is_file():
    raise SystemExit("The Linux bundle is incomplete")
for path in sorted(binaries):
    symbols = subprocess.check_output(["objdump", "-T", str(path)], text=True)
    versions = [tuple(map(int, value.split(".")))
                for value in re.findall(r"GLIBC_([0-9]+(?:\.[0-9]+)+)", symbols)]
    if versions and max(versions) > (2, 35):
        raise SystemExit("Linux binary exceeds the Ubuntu 22.04 glibc baseline: " + str(path.relative_to(root)))
    result = subprocess.run(["ldd", str(path)], capture_output=True, text=True)
    if result.returncode or "not found" in result.stdout + result.stderr:
        raise SystemExit("Unresolved Linux runtime dependencies: " + str(path.relative_to(root)))
# The security-key bridge loads libfido2 when first used, so a missing library
# only hides the option. A build without its headers compiles a stub instead.
runner = root / "GleecDEX"
if b"libfido2.so.1\0" not in runner.read_bytes():
    raise SystemExit("The Linux build lacks the security-key bridge (install libfido2-dev)")
if re.search(r"NEEDED\s+libfido2", subprocess.check_output(["objdump", "-p", str(runner)], text=True)):
    raise SystemExit("libfido2 must be loaded at runtime, not linked")
print("Verified Linux bundle dependencies, Ubuntu 22.04 glibc compatibility and the security-key bridge.")
