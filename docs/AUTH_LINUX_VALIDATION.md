# Linux credential storage validation

This validates the Linux branch of `NativeCredentialBackend`. Linux uses Secret
Service when available, or explicitly classified app-local storage otherwise.
Neither tier promises biometric or device-passcode authorization. Secret Service
metadata reports OS-account storage protection with `enrolled: false`.

## Corrections

- A durable `.secret-service` marker now takes priority over any valid, stale or
  malformed app-local file. Provider loss cannot open the unattended shadow or
  change the same entry back to the app-local tier.
- Records must contain a string value and the protection tier appropriate to
  their actual storage location. Corrupt local data cannot claim stronger
  protection through its metadata.
- Provider, JSON and filesystem failures return a typed, redacted storage
  failure. Raw exception messages and paths are not propagated.
- App-local directories use `0700`; credential files use `0600` before writing
  the credential. Writes use a pending file, rename and read-back verification.
  Secret Service policy markers also use owner-only permissions.
- A verified protected write removes obsolete local and pending copies.
  Deletion verifies provider absence before removing local copies and the policy
  marker. Failed deletion retains the marker, allowing an explicit retry without
  weakening the stored policy.
- An optional support-directory callback permits isolated filesystem tests. The
  backend still selects Linux through `Platform.isLinux`; no platform override
  or application-level authentication Boolean was added.

## Environment and execution

Validation uses a fresh container from the already-cached image
`gleec-wallet-devcontainer:validation`, image ID
`sha256:85d6ba5c466ac4f68389c6b4f46b54b2595f2d45f1e46654460ab7e37713c05f`.
It runs Linux amd64 with Flutter **3.41.4**, Dart **3.11.1**, and its unprivileged
`komodo` user. Networking is disabled. Existing containers are not modified.

The temporary Flutter package contains copies of only:

- `lib/services/wallet_access/platform/native_credential_backend.dart`
- `lib/services/wallet_access/platform/credential_backend.dart`
- `lib/services/wallet_access/wallet_access_types.dart`
- `test_units/services/wallet_access/native_credential_backend_linux_test.dart`

Its package name is `web_dex`, with Flutter/Flutter Test from the image and exact
app dependency versions `flutter_secure_storage: 10.0.0`, `path: 1.9.1` and
`path_provider: 2.1.5`. The app lockfile is copied as the resolver's starting
point; `flutter --no-version-check pub get --offline` resolves this small
package. The host dependency cache and copied sources are mounted read-only.
The container creates a temporary writable cache of symlinks and copies the
package into its own temporary directory before testing. No app dependency or
SDK version is changed.

Run inside that package:

```sh
flutter --no-version-check test --no-pub \
  test_units/services/wallet_access/native_credential_backend_linux_test.dart \
  --reporter expanded
```

Run this suite through the app unit aggregator as well. It skips explicitly on
non-Linux hosts; a macOS skip is not Linux validation. The permission-denial
case explicitly skips if run as root, since root can bypass ordinary directory
permission checks. The validation container runs this case unprivileged.

Result on **2026-11-08**: **22 tests passed, none skipped** in the isolated Linux
container. Scoped Dart analysis reported no issues, whitespace validation passed,
and the synthetic secret canary was absent from both test output and analysis
logs. The successful run includes the real permission-denied deletion case.

## Coverage and limits

The suite exercises the actual Linux branch, real temporary files in the Linux
container filesystem, `chmod`, mode inspection, atomic replacement, read-back,
and a real permission-denied deletion. It checks provider absence, loss and
rejection; stale local shadows; restart after a failed first protected write;
malformed records; retention after failed provider deletion; successful cleanup;
honest capability reporting; and canary-secret redaction.

`FlutterSecureStorage` is replaced only at its provider boundary to inject these
conditions. That initial 22-test run did not exercise a real Secret Service
daemon and is not full application packaging evidence. Real provider and full
application checks are recorded separately below. The injected-failure suite
continues to cover cases that a successful provider round trip alone cannot
establish, including stale shadows, denied writes and failed deletion.

Application-local permissions protect against other OS accounts, not malicious
code running as the signed-in user. Secret Service is OS-account protection;
the Linux implementation must continue to describe it without claiming
biometric-bound decryption or independent wallet recovery.

## Native engine packaging

The SDK Linux plugin now requires a verified `linux/bin/libkdflib.so` or
`linux/bin/libkdflib_static.so`. Both names must contain actual shared ELF
libraries; the latter name does not authorize using a static archive. The
plugin bundles the validated libraries into the application's `lib/` directory.
It no longer bundles `kdf` or copies it into the user's `~/.local/bin` directory.
The Dart loader uses absolute paths relative to the running app executable,
including after the bundle is moved. It does not search the working directory,
the system library path or an executable fallback.

The CMake guard verifies the immutable commit, approved archive checksum set,
extracted executable digest and complete runtime-set digest against the existing
build-transformer marker. The executable remains part of the archive's identity,
but is not an application runtime entry point. Every supported library present
must pass validation; symlinks and stale companion files fail. The current
artifact target is Linux x64 only. ELF validation requires little-endian ELF64,
`ET_DYN`, load/dynamic segments and defined global function exports `mm2_main`,
`mm2_main_status` and `mm2_stop`. It rejects `PT_INTERP` and the `DF_1_PIE` flag:
a PIE executable also has `ET_DYN`, so that header value alone is insufficient.
The build requires GNU `readelf` or `llvm-readelf`; cross-packaging can supply
`-DKDF_READELF=/path/to/llvm-readelf`. Inspection never executes the artifact.

On 2026-11-08, the real ELF fixture matrix passed **31 tests, none skipped**
using host clang, LLVM `readelf`, Rust's `ld.lld` and CMake 3.22.1. The fixtures
are freestanding x64/ARM64 ELF images compiled without a Linux sysroot. They
cover archive/commit/runtime mismatches, stale libraries, symlinks, wrong
architecture, truncated/corrupt ELF, both PIE forms, missing/ineligible exports
and misleading symbol names containing spaces or newlines. The validator checks
the complete symbol table's count and sequential indices before accepting export
names. A real plugin CMake configuration verifies that the bundle contains only
the shim and validated libraries, with no home-directory installation. Flutter
3.41.4's wrapper test plus all six native-library path tests passed (**7 Flutter
tests**, including the wrapper for those 31 cases). A separate run inside the
Linux amd64 application container also passed **31/31 with no skips**, using
GNU `readelf` 2.38, clang/lld 14 and the actual plugin CMake configuration. Both
LLVM and GNU symbol-table formats are therefore exercised.

The fixture suite is `sdk/packages/komodo_defi_framework/test/operations/
linux_library_packaging_test.py`, with an automatically discovered Flutter test
wrapper alongside it. It accepts `GLEEC_CMAKE`, `GLEEC_READELF`, `GLEEC_CLANG`
and `GLEEC_LLD` tool-path overrides and explicitly skips when required tools are
unavailable. A skipped run is not packaging validation.

## Exact-source native artifact

The old canonical archive for commit
`f9632e0ec771668a6f21b37aede01a30110141cb` has SHA-256
`dac943647d2f307204a6a01a6a5c34e33c00e8695b88e1ceaf2a7893eba50ff2`
and contains only `kdf` (SHA-256
`d561ce7fed4ff564917d2f6b63cee3c44b2bdb7bd600296d3457870a91283c6a`).
It is an x64 PIE with an interpreter, and correctly fails the shared-library
packaging guard. The source already defines `kdflib` as a `cdylib`; the original
Linux workflow simply omitted that library from its ZIP.

On 2026-11-08 the missing library was built from the exact source archive
SHA-256 `86c8d10d6d6c7644de6011c65f5362baabb5c441539db6fe713d7b45b448e0bf`,
with all **1,203 source files unchanged**, Rust **1.98.0**, protoc **25.3** and
unchanged `Cargo.lock` SHA-256
`f160ec23242893eae6f65634eb10628b760fe1027ce11d801a253d9d6d1a428a`.
The immutable Linux amd64 build image is
`sha256:12c3051c751b99c5c6cad08e1c4ab9298be213e1f9d58c6b8c18e21ef9d6a8e4`
(Debian 11, glibc 2.31). After official build dependencies were installed, the
container network was disconnected. The source and dependency cache were
mounted read-only; no host credentials were mounted. The successful command was:

```sh
cargo +1.98.0 build --offline --locked --release --package mm2_bin_lib --lib \
  --target x86_64-unknown-linux-gnu --jobs 4
```

It used the unmodified upstream release profile and no additional features.
The build finished in 16 minutes 56 seconds. The reproducible procedure and
source verifier are in `tool/auth_native_artifacts/`; upstream embeds build
time, so identical inputs are not a claim of bit-for-bit repeatable output.

The resulting `libkdflib.so` is 76,781,752 bytes, SHA-256
`6c86d74567695361ae101b8892cb33076470d27a116d0488e22b9959f7b8f7f4`.
It has all required exports and no PIE interpreter. Its highest required glibc
symbol version is **2.30**. Dynamic dependencies are `libudev.so.1`,
`libgcc_s.so.1`, `libpthread.so.0`, `libm.so.6`, `libdl.so.2`, `libc.so.6` and
the x64 ELF loader. Inspection does not certify every older distribution;
runtime checks below identify the environments actually exercised.

The new immutable archive is
`kdf_f9632e0ec771668a6f21b37aede01a30110141cb-linux-x86-64-native-v1.zip`,
SHA-256 `beb961fe98dbb3d0b1542fb530c749317ecd573b57f94d63b720f4908841d899`.
It contains exactly `kdf` and `libkdflib.so`, preserving the matching approved
executable solely as artifact identity. Old archives are not replaced. The
`native-v1` selector requires a full 40-character commit token; the downloader
also binds that token to the configured immutable source commit and verifies
the exact ZIP checksum. Completed publication and canonical pin checks are
recorded below.

## Real native lifecycle

The exact library passed all **eight phases** inside disconnected Linux amd64
Debian 11 using native FFI and authenticated loopback RPC:

1. Load and initial engine status.
2. No-login start, empty catalog, pinned version, stop.
3. Fresh generated HD wallet creation.
4. Fresh correct-password proof and wrong-password rejection.
5. Wrong-password cold start preserves the original wallet; correct return
   preserves public identity and the recovery phrase.
6. Password rotation rejects the old password and preserves identity after
   a cold return with the replacement password.
7. Synthetic credential/phrase canaries are absent from real process arguments,
   process environment and temporary persisted wallet files.
8. No-login deletion rejects the wrong password, accepts the correct password,
   leaves an empty catalog and stops cleanly.

The harness is `tool/auth_native_artifacts/runtime_smoke.py`, SHA-256
`33e6999fb5c02f4d0f16354eb78ffaa15d80c1323cb9c481773f79f220c9bd28`.
It creates only temporary, unfunded wallets with no enabled coins and disabled
P2P. Passwords and the phrase remain in process memory; raw native output is
discarded, and the report contains only closed phase/failure categories. It
clears mutable FFI configuration buffers after startup returns. This is not a
claim that Python strings or all KDF session memory can be erased.

## Full application and provider validation

The full Linux release build passed in **46.0 seconds** in a disposable
Ubuntu 22.04 amd64 container with Flutter **3.41.4** and Dart **3.11.1**. Its
sanitized source snapshot obtained the new ZIP through the normal prefetch
tool, which created a real provenance marker. The final bundled library digest
matches the exact source build above. The root dependency lockfile did not
change. No fabricated marker, executable fallback or source workaround was used.

The final Flutter build had network access because Flutter's nested named-package
Dart invocation repeatedly fetched pub.dev security-advisory metadata, even
following an online prewarm and an offline dependency resolution. KDF asset
downloads were disabled for packaging and all native pins remained verified.
All 449 coin configuration/icon files remained byte-identical to the source
snapshot, and the artifact privacy scan passed. Network traffic was not captured,
so this is not a claim that every request was an advisory lookup. Only the Rust
engine build was fully disconnected. The application container was disconnected
again before runtime checks.

The uninstrumented release bundle then passed actual startup under Xvfb with
software rendering and a real unlocked GNOME Keyring on a private D-Bus session.
The GTK window rendered the **Open your wallet** onboarding screen, and the
process mapped the exact verified library from the bundle. No startup error
categories remained. The screen correctly reported unavailable legal documents
while disconnected; this UI check did not create a wallet.

The first startup attempt exposed a fixture prerequisite: this minimal image
lacked `xdg-user-dirs`, including the `xdg-user-dir` executable used by
`path_provider_linux`. A standard Documents mapping alone was insufficient.
Installing that Ubuntu package and creating a task-owned `user-dirs.dirs`
mapping resolved `MissingPlatformDirectoryException` before Hive initialization.
The container's existing user home was retained; runtime, data, configuration,
cache and Documents paths were all test-owned. No host desktop profile or
production source was changed. Minimal Linux installations require this normal
desktop directory support in addition to GTK, libsecret and the engine's shared
library dependencies.

The real Secret Service integration then passed **five fresh-process phases**
with networking disconnected. It used the unchanged production
`NativeCredentialBackend`, Flutter Secure Storage's actual Linux plugin,
libsecret and GNOME Keyring. Each phase started a new Flutter process against
the same disposable keyring and support directory:

1. Write and read the synthetic credential.
2. Reopen it in a separate process.
3. Stop the provider; read, metadata and write fail closed, retain the policy
   marker and never create or read an app-local fallback.
4. Restart and unlock the provider; reopen the original credential unchanged.
5. Delete it, verify absence and remove the local policy marker.

Assertions required `osAccountProtected`, `deviceAuthentication: false` and
`enrolled: false`. Credential canaries were absent from process arguments,
environment, disposable persisted files and captured diagnostics. Runtime
versions were GNOME Keyring **40.0-3ubuntu3**, libsecret **0.20.5-2**,
Xvfb **21.1.4-2ubuntu1.7~22.04.16** and xdg-user-dirs **0.17-2ubuntu4**.

The probe's Dart AOT compilation succeeded, but a later repeated asset-transformer
step hit GitHub's unauthenticated coin-metadata rate limit. For this test only,
the successfully compiled probe AOT replaced `lib/libapp.so` in a **copy** of the
preserved successful full bundle. Its plugins and native backend were unchanged;
the uninstrumented production bundle was not modified. The separate full-app
startup proof above therefore remains distinct from this integration harness.
The probe source SHA-256 is
`d8765d7adb732cbd6780e870afb5d193ff1c537b04739602d20d22ee77b99c0f`.

This closes the nonphysical provider write/read/restart/loss/delete checks. It
does not claim a physical desktop login-keyring prompt, login/logout behavior,
interactive collection unlocking or cross-account testing.

## Canonical publication and package refresh

The immutable archive is publicly available at
[`kdf_f9632e0ec771668a6f21b37aede01a30110141cb-linux-x86-64-native-v1.zip`](https://devbuilds.gleec.com/main/kdf_f9632e0ec771668a6f21b37aede01a30110141cb-linux-x86-64-native-v1.zip).
Independent full HTTPS verification confirmed SHA-256
`beb961fe98dbb3d0b1542fb530c749317ecd573b57f94d63b720f4908841d899`
and 61,332,510 bytes. The normal shipped Dart prefetch subsequently downloaded,
verified and extracted both new Linux and macOS archives from the public host,
without credentials or an SDK HTTP-client change. It generated the actual
provenance markers; Linux's runtime-set SHA-256 is
`094ff14489f885d81181531ee4ad1c8a12473c8ceb4d96349fdd0ac034f36599`.

Only the Mac/Linux selectors and checksums changed in the SDK's canonical JSON
and reference YAML. The JSON SHA-256 is
`038d8e8cc047aa1177feec0ee276b97353f65f90123b69f55cd0f8f570dbb3b8`.
The API sections agree. The source commit, other platform pins and all coin
settings were preserved. Fifteen focused manifest/filename-selection tests
passed with no skips.

Full HTTPS downloads also verified that old published archives were not changed:
`kdf_f9632e0-linux-x86-64.zip` still has SHA-256
`dac943647d2f307204a6a01a6a5c34e33c00e8695b88e1ceaf2a7893eba50ff2`
(29,708,903 bytes), and `kdf_f9632e0-mac-universal.zip` still has SHA-256
`6dfc9149ac7b1017e518163788fe8c8a6d45c1270aae66cc74b83f8e20d34835`
(55,991,315 bytes).

The final package refresh passed in **83.5 seconds**, using the published
canonical configuration, both
publicly prefetched caches, and corrected lock coordinator SHA-256
`ca9fa0477176670f1d1d312028198cd458e30cf75a88a7b7c7856bc816e5dbcd`.
All recorded inputs and all 449 coin assets remained unchanged. The final
artifact privacy scan passed, and the uninstrumented package again rendered
onboarding offline with the exact bundled engine and canonical manifest.
The expected offline legal-document warning remained visible; no wallet was
created and no funds were used in this UI check.

Final package fingerprints:

- Runner: `f090cd5e16435995bfb1afdccfeea05fd2280325e9afa319ca00a61898e1d60d`.
- App AOT: `a309766f552a3e2deb858e970800b394e00fb3709f1c39c122f816d0b5714bbf`.
- Engine: `6c86d74567695361ae101b8892cb33076470d27a116d0488e22b9959f7b8f7f4`.
- Validation record: `db235b1ef420c7dc49cbfc97db124bab06dd9e68d1fa1e9c7416d1ab5fc4eb91`.

Sanitized final provenance is retained in
`tool/auth_native_artifacts/provenance/linux-f9632e0-native-v1.json`.
The full evidence/package are under
`/private/tmp/gleec-linux-app-validation/`; the container remains disconnected.
These checks cover the nonphysical engine, packaging and provider gates, while
the physical desktop/prompt limits above remain explicit.
