# Windows authentication release gate

## Implemented and checked locally

The credential vault uses user-scoped DPAPI. Windows Hello supplies a separate
application authorization check; this is **not Hello-bound decryption**. A
correct Windows account can use DPAPI independently of Hello. The envelope
authenticates its immutable credential key, protection policy and revision.

The desktop Hello ceremony is bound to the app window. Capabilities report
authentication unavailable when that interop or the user's configured device
method is unavailable. Cancellation, session locking and record replacement
revoke pending results and deletion grants. Password-manager saving currently
reports unavailable on Windows rather than silently creating another credential
copy. [Microsoft desktop verification API](https://learn.microsoft.com/en-us/windows/win32/api/userconsentverifierinterop/nf-userconsentverifierinterop-iuserconsentverifierinterop-requestverificationforwindowasync),
[DPAPI contract](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata).

Validation on 2026-11-08 used clang-cl 23.1.4, the cached Windows SDK 10.0.26100,
MSVC 14.44 CRT headers/import libraries, LLVM lld-link from Rust 1.95, and Flutter
3.41.4's actual C++ wrapper sources. No Windows API was mocked for compilation
or linking.

- The production credential channel and FlutterWindow integration compile to
  Windows x64 objects with `/W4 /WX /std:c++20`.
- A standalone x64 PE harness links against real DPAPI, WinRT and WTS imports.
  It supplies an in-memory Flutter messenger and uses Flutter's actual codec
  and ReplyManager implementation. It is not a complete Flutter application.
- Compilation found an ambiguous ABI/C++-WinRT `AsyncStatus` name; the channel
  now uses a distinct projected enum alias. The runner requests C++20 to avoid
  obsolete experimental coroutine headers.
- The installed pinned `kdflib.dll` is an x64 PE DLL and exports `mm2_main`,
  `mm2_main_status` and `mm2_stop`. Its full runtime-set digest matches the
  immutable manifest/provenance marker.
- The SDK now resolves that DLL only beside the application executable. It
  previously returned no Windows library candidates. Missing or incompatible
  libraries fail safely; credential-bearing executable argument transport is
  never restored.
- Windows CMake rejects missing DLLs, wrong commits/checksums, changed or extra
  runtime files, invalid/truncated PE files, ARM64 DLLs in this x64 distribution,
  and executable images disguised as DLLs. Ten synthetic packaging cases pass,
  including rejection of an ARM64 app paired with the x64 library.

These checks do **not** establish successful Windows execution, Hello behavior,
signed release packaging, DPAPI account isolation or GPU compatibility. No
usable Windows VM was configured on the available macOS host. The old SDK had
disabled native Windows loading with a comment about NVIDIA crashes, so a
successful KDF startup on an NVIDIA-equipped x64 PC is a specific release gate.

## Repeatable automated checks

Use explicitly supplied toolchains; the script downloads nothing and contains
no machine-specific defaults:

```sh
python3 windows/runner/test/check_windows_vault.py \
  --flutter-sdk /path/to/flutter-3.41.4 \
  --xwin-sdk /path/to/cargo-xwin/xwin \
  --compiler /path/to/clang-cl \
  --linker /path/to/lld-link \
  --output /path/to/temporary-validation-output
```

The script compiles the real channel, integration and harness, then links
`credential_vault_envelope_test.exe`. It explicitly reports that runtime tests
were not run. On a Windows host, pass `--run` or execute that file directly.
The harness uses synthetic unfunded values and temporary files; it checks
DPAPI round trips, wallet/policy/revision binding, tampering, atomic persistence,
and channel teardown/lock-message routing. It does not show a Hello dialog.

SDK package checks (set `GLEEC_CMAKE` if CMake is not on PATH):

```sh
flutter test --no-pub test/operations/native_library_paths_test.dart \
  test/operations/windows_library_packaging_test.dart
```

Run from `sdk/packages/komodo_defi_framework`. A missing CMake executable is
reported as a skipped packaging check, never counted as runtime validation.
The production packaging guard can also run independently:

```sh
cmake -DKDF_FRAMEWORK_DIR=/path/to/komodo_defi_framework \
  -P /path/to/komodo_defi_framework/windows/validate_native_library.cmake
```

## Windows host/device help required

Provide a Windows 11 **x64** PC with Windows Hello PIN configured and, for the
biometric checks, a working fingerprint reader or Hello camera. Use a disposable
unfunded wallet and keep its recovery phrase private. A second disposable Windows
account is needed for the DPAPI isolation check. Include an NVIDIA-equipped PC
because of the historical native-engine issue; do not infer ARM64 support from
these x64 artifacts.

1. Build the complete app with Flutter 3.41.4, Visual Studio 2022's Desktop C++
   workload and Windows SDK 10.0.26100. Run `flutter build windows --release`
   after the repository's normal dependency/assets setup. Verify the packaged
   directory includes `kdflib.dll`, then launch it from a different working
   directory. Create an unfunded wallet, reopen it and check balances load.
   Record OS/build, GPU/driver, app commit and whether any native crash occurs.
2. Exercise enrollment and return with biometrics and PIN, cancellation,
   repeated incorrect attempts/lockout, and unavailable/unconfigured Hello.
   Return must use the last successful immutable wallet with at most one
   automatic challenge. Cancellation must leave manual unlock and switching
   usable. Declining new enrollment must accurately retain the initial
   unprotected application state.
3. Unlock, press **Win+L**, then return: the app must require fresh unlock
   immediately. Also test ordinary 29/31-second app background returns and
   immediate-lock settings. Lock or switch wallets while a Hello prompt is
   pending; the late completion must not reopen or authorize the wrong wallet.
4. Confirm generated-password phrase backup/export/password change/deletion
   require fresh configured authorization without asking for an unknown
   password. Cancel each action. Prepare deletion, then cancel/lock/wait over
   60 seconds/change the record; the old grant must fail. Successful deletion
   must not prompt again after engine destruction; failed cleanup must remain
   visible and retryable. Verify explicit sign-out remains signed out after
   restarting the app.
5. Run the native harness under the first Windows account. For cross-account
   validation, create a **synthetic** probe with
   `credential_vault_envelope_test.exe --write-account-probe <shared-path>`.
   Under the second account, run
   `credential_vault_envelope_test.exe --verify-foreign-account <shared-path>`;
   it must report that decryption failed. Remove the probe afterward. This
   checks account isolation, not resistance to malware in the original account.
6. Change/remove Hello enrollment and exercise canceled/failed OS verification,
   restart and reinstall. Existing wallet data must survive failed unlock;
   a verified existing password or independently backed-up phrase remains the
   recovery path. Inspect synthetic canaries in process arguments, diagnostics,
   support exports and app-data files; credentials must not appear as plaintext.

Report each case as pass/fail with the OS/build and reproducible steps, without
attaching passwords, phrases, plaintext credential records or PRF output.
