#!/usr/bin/env python3
"""Compile/link the real Windows vault against an explicitly supplied SDK.

Uses a cargo-xwin/xwin-layout Windows SDK/CRT and Flutter's bundled engine
sources; downloads nothing and never runs a Windows binary unless --run is set.
"""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flutter-sdk", required=True, type=Path)
    parser.add_argument("--xwin-sdk", required=True, type=Path)
    parser.add_argument("--compiler", default=shutil.which("clang-cl"))
    parser.add_argument("--linker", default=shutil.which("lld-link"))
    parser.add_argument("--output", type=Path)
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()
    if not args.compiler or not args.linker or not shutil.which(args.compiler) or not shutil.which(args.linker):
        parser.error("clang-cl and lld-link are required; supply --compiler and --linker.")
    if args.run and os.name != "nt":
        parser.error("--run requires a Windows host; cross-compilation does not execute DPAPI/Hello.")

    project = Path(__file__).resolve().parents[3]
    engine = args.flutter_sdk / "engine/src/flutter/shell/platform"
    common = engine / "common/client_wrapper"
    sdk = args.xwin_sdk
    includes = [
        sdk / "crt/include",
        *[sdk / "sdk/include" / name for name in ["ucrt", "um", "shared", "winrt", "cppwinrt"]],
    ]
    flutter_includes = [
        common / "include", common / "include/flutter", engine / "common/public",
        engine / "windows/client_wrapper/include", engine / "windows/public",
        project / "windows",
    ]
    libraries = [sdk / "crt/lib/x86_64", sdk / "sdk/lib/um/x86_64", sdk / "sdk/lib/ucrt/x86_64"]
    for path in [*includes, *flutter_includes, *libraries]:
        if not path.is_dir():
            parser.error(f"required toolchain directory is unavailable: {path}")
    output = args.output or Path(tempfile.mkdtemp(prefix="gleec-windows-vault-"))
    output.mkdir(parents=True, exist_ok=True)
    # The standalone harness supplies an in-memory BinaryMessenger, so it needs
    # Flutter's actual ReplyManager but not the engine's C messenger/texture
    # entrypoints. Extract that unmodified implementation from the supplied SDK
    # instead of stubbing any Windows or vault API or requiring flutter_windows.dll.
    wrapper_source = (common / "core_implementations.cc").read_text()
    beginning = "// ========== engine_method_result.h =========="
    ending = "// ========== method_channel.h =========="
    if beginning not in wrapper_source or ending not in wrapper_source:
        parser.error("Flutter ReplyManager source layout changed; update this harness explicitly.")
    reply_manager = wrapper_source.split(beginning, 1)[1].split(ending, 1)[0]
    reply_source = output / "flutter_reply_manager.cc"
    reply_source.write_text(
        '// Flutter implementation from the supplied SDK; original BSD license applies.\n'
        '#include <cassert>\n#include <iostream>\n'
        '#include <flutter/engine_method_result.h>\n'
        'namespace flutter {\n' + reply_manager + '\n}\n'
    )
    flags = [
        "--target=x86_64-pc-windows-msvc", "/nologo", "/std:c++20", "/EHsc",
        "/W4", "/WX", "/wd4100", "/MT", "/Gy", "/Gw", "/c",
        "/DUNICODE", "/D_UNICODE", "/DNOMINMAX", "/D_HAS_EXCEPTIONS=0",
        *[f"/imsvc{path}" for path in includes],
        *[f"/I{path}" for path in flutter_includes],
    ]
    sources = {
        "vault": project / "windows/runner/credential_vault_channel.cpp",
        "window": project / "windows/runner/flutter_window.cpp",
        "envelope_test": Path(__file__).with_name("credential_vault_envelope_test.cpp"),
        "standard_codec": common / "standard_codec.cc",
        "reply_manager": reply_source,
    }
    for name, source in sources.items():
        subprocess.run([args.compiler, *flags, f"/Fo{output / (name + '.obj')}", "--", str(source)], check=True)
        print(f"Compiled {name} for Windows x64.", flush=True)
    executable = output / "credential_vault_envelope_test.exe"
    subprocess.run([
        args.linker, "/nologo", "/machine:x64", "/subsystem:console", "/opt:ref",
        f"/out:{executable}", *[f"/libpath:{path}" for path in libraries],
        *[str(output / (name + ".obj")) for name in ["envelope_test", "standard_codec", "reply_manager"]],
        "crypt32.lib", "bcrypt.lib", "windowsapp.lib", "wtsapi32.lib",
        "shell32.lib", "ole32.lib", "user32.lib", "advapi32.lib", "uuid.lib",
    ], check=True)
    print(f"Linked Windows validation harness: {executable}", flush=True)
    if args.run:
        subprocess.run([str(executable)], check=True)
    else:
        print("Runtime checks were NOT run. Execute this harness on Windows; Hello still requires device testing.")


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.exit(error.returncode)
