# WASM Compatibility Audit

> **Audited**: 2026-03-23
> **Scope**: Full codebase (`lib/`, `sdk/`, `packages/`, `app_theme/`, `web/`, CI/CD, dependencies)
> **Build target**: `flutter build web --no-pub --release --wasm`
> **Dart SDK constraint**: `>=3.8.1 <4.0.0` | **Flutter**: `>=3.41.4 <4.0.0`

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Background: How WASM Compilation Differs](#2-background-how-wasm-compilation-differs)
3. [Critical: Unconditional `dart:io` Imports in `lib/`](#3-critical-unconditional-dartio-imports-in-lib)
4. [Critical: Transitive `dart:io` via Import Chains](#4-critical-transitive-dartio-via-import-chains)
5. [Correct: Files Protected by Conditional Imports](#5-correct-files-protected-by-conditional-imports)
6. [High: `dartify()` / `jsify()` Number Type Coercion](#6-high-dartify--jsify-number-type-coercion)
7. [High: Hive CE / IndexedDB WASM Data-Type Issues](#7-high-hive-ce--indexeddb-wasm-data-type-issues)
8. [High: `ZLibCodec` from `dart:io`](#8-high-zlibcodec-from-dartio)
9. [Medium: Deferred Import Regression](#9-medium-deferred-import-regression)
10. [Medium: `compute()` and Isolate Limitations](#10-medium-compute-and-isolate-limitations)
11. [Medium: COOP/COEP Cross-Origin Isolation Headers](#11-medium-coopcoep-cross-origin-isolation-headers)
12. [Medium: Third-Party Plugin WASM Compatibility](#12-medium-third-party-plugin-wasm-compatibility)
13. [Medium: SDK Package Issues](#13-medium-sdk-package-issues)
14. [Low: JS Interop Correctness (Passing)](#14-low-js-interop-correctness-passing)
15. [Low: Build Pipeline Validation](#15-low-build-pipeline-validation)
16. [Informational: analysis_options.yaml](#16-informational-analysis_optionsyaml)
17. [Complete File Inventory](#17-complete-file-inventory)
18. [Dependency Flow Diagrams](#18-dependency-flow-diagrams)
19. [Remediation Priority Matrix](#19-remediation-priority-matrix)
20. [Appendix A: dart:io Symbol Usage Map](#appendix-a-dartio-symbol-usage-map)
21. [Appendix B: Conditional Import Reference](#appendix-b-conditional-import-reference)
22. [Appendix C: WASM vs dart2js Behavioural Differences](#appendix-c-wasm-vs-dart2js-behavioural-differences)

---

## 1. Executive Summary

The Gleec Wallet builds and deploys to production with `flutter build web --wasm` via CI
(`.github/actions/generate-assets/action.yml`). The Dart SDK constraint (`>=3.8.1`)
satisfies the minimum Dart 3.3 requirement for WASM support.

**Positive findings:**

- All JS interop uses the modern `dart:js_interop` / `package:web` APIs. Zero legacy
  `dart:html`, `dart:js`, or `dart:js_util` imports were found.
- Platform-critical paths (KDF operations, event streaming, file loading, window management,
  platform info) are properly split behind conditional imports.
- The KDF WASM binary and bootstrapper are correctly loaded in `web/index.html`.
- COOP/COEP headers are configured in `firebase.json` for `SharedArrayBuffer` support.

**Findings requiring action:**

| Severity | Count | Category |
| -------- | ----- | -------- |
| **Critical (P0)** | 11 files | Unconditional `dart:io` imports reachable from `main()` |
| **Critical (P0)** | 1 file | Transitive `dart:io` via import chain (`time_provider_registry`) |
| **High (P1)** | 2 files | `dartify()` number type coercion in financial RPC path |
| **High (P1)** | 1 area | Hive CE `int`->`double` coercion in WASM |
| **High (P1)** | 1 file | `ZLibCodec` from `dart:io` used in `zip.dart` |
| **Medium (P2)** | 1 file | Deferred import regression risk in `main.dart` |
| **Medium (P2)** | 4 packages | Third-party plugin WASM compatibility gaps |
| **Medium (P2)** | 1 file | SDK `auth_service.dart` unconditional `dart:io` |
| **Low (P3)** | 0 | JS interop correctness (all passing) |

---

## 2. Background: How WASM Compilation Differs

### 2.1 `dart:io` Is Not Available

`dart:io` provides platform I/O primitives (`File`, `Socket`, `Platform`, `HttpClient`,
`ZLibCodec`, etc.). It is available on native targets (Android, iOS, macOS, Windows, Linux)
but **not** in browser environments. Under `dart2js`, importing `dart:io` on web would fail
at compile time. Under `dart2wasm`, the same restriction applies -- any unconditional
`import 'dart:io'` in a file reachable from the compilation entry point will fail.

**The import itself is the problem**, not just usage of the symbols. Even if every
`Platform.isAndroid` call is guarded by `if (!kIsWeb)`, the `import 'dart:io'` statement
at the top of the file causes the compiler to attempt to resolve the library, which fails.

### 2.2 Number Type Distinction

`dart2js` compiles both `int` and `double` to JavaScript's single `number` type. `dart2wasm`
preserves Dart's true `int64` and `double` distinction internally, but when values cross
the JS interop boundary (via `dartify()`, `jsify()`, or `JSNumber`), all numbers become
JavaScript doubles. This means:

- `dartify()` returns `double` for any numeric JS value, even integers.
- `is int` checks on values from JS will return `false` in WASM but `true` in dart2js.
- Financial calculations relying on `int` types from RPC responses are at risk.

### 2.3 Conditional Import Mechanics

Dart supports compile-time conditional imports:

```dart
import 'stub.dart'
    if (dart.library.io) 'native_impl.dart'
    if (dart.library.js_interop) 'web_impl.dart';
```

| Condition | Native VM | dart2js | dart2wasm |
| --------- | --------- | ------- | --------- |
| `dart.library.io` | true | false | false |
| `dart.library.html` | false | true | **false** |
| `dart.library.js_interop` | false | true | true |
| `dart.tool.dart2wasm` | false | false | true |

`dart.library.js_interop` matches **both** dart2js and dart2wasm. To distinguish between
them, use `dart.library.html` (true only for dart2js) or `dart.tool.dart2wasm` (true only
for dart2wasm, available in newer SDKs).

### 2.4 Isolates and `compute()`

`Isolate.spawn`, `Isolate.spawnUri`, and Flutter's `compute()` helper are **not available**
in browser environments (both dart2js and dart2wasm). Code using these must either be behind
a conditional import or use Web Workers via a cross-platform abstraction.

---

## 3. Critical: Unconditional `dart:io` Imports in `lib/`

These 11 files in `lib/` unconditionally import `dart:io` and are reachable from `main()`.
Each one is a compilation blocker under standard `dart2wasm` toolchains.

### 3.1 `lib/services/storage/get_storage.dart`

```dart
import 'dart:io';                              // line 1

final BaseStorage _storage = kIsWeb ||
        Platform.isWindows ||                  // line 9 -- dart:io Platform
        !Platform.environment.containsKey('FLUTTER_TEST')  // line 10
    ? AppStorage()
    : MockStorage();
```

**Problem**: Top-level initializer calls `Platform.isWindows` and `Platform.environment`
directly. The `kIsWeb` short-circuit does not prevent the `dart:io` import from being
resolved at compile time.

**Remediation**: Split into `get_storage.dart` (interface + conditional import),
`get_storage_native.dart` (current logic), `get_storage_web.dart` (always returns
`AppStorage()`).

---

### 3.2 `lib/services/logger/get_logger.dart`

```dart
import 'dart:io';                              // line 2

LoggerInterface _getLogger() {
  if (kIsWeb ||
      Platform.isWindows ||                    // line 22
      Platform.isMacOS ||                      // line 23
      Platform.isLinux ||                      // line 24
      Platform.isAndroid ||                    // line 25
      Platform.isIOS) {                        // line 26
    return UniversalLogger(platformInfo: platformInfo);
  }
  return const MockLogger();
}
```

**Problem**: Same pattern -- `Platform.is*` usage is guarded at runtime but the import is
unconditional. The intent of this code is to return `UniversalLogger` on every known
platform and `MockLogger` as fallback; on web this always takes the `kIsWeb` branch, but
the compiler still needs to resolve `dart:io`.

**Remediation**: Split into conditional import pattern. The web implementation can
simply return `UniversalLogger` directly.

---

### 3.3 `lib/bloc/system_health/providers/binance_time_provider.dart`

```dart
import 'dart:io';                              // line 3

} on SocketException catch (e, s) {            // line 47
  ...
throw HttpException(                           // line 79
  'HTTP error from $url: ${response.statusCode}',
  uri: Uri.parse(url),
);
```

**Problem**: Uses `SocketException` and `HttpException` from `dart:io`. These exception
types do not exist in the web compilation target.

**Remediation**: Replace with cross-platform equivalents. `SocketException` can be replaced
with a generic `Exception` catch or a custom `NetworkException`. `HttpException` can be
replaced with a custom exception class since the `http` package does not throw `dart:io`
exceptions on web.

---

### 3.4 `lib/bloc/system_health/providers/http_head_time_provider.dart`

```dart
import 'dart:io';                              // line 2

} on SocketException catch (e, s) {            // line 59
} on HttpException catch (e, s) {              // line 63
throw HttpException(                           // line 86
final parsed = HttpDate.parse(dateHeader);     // line 98
```

**Problem**: Uses `SocketException`, `HttpException`, and `HttpDate` from `dart:io`.
`HttpDate.parse` is the most complex dependency -- it parses RFC 1123 / RFC 850 date
strings from HTTP `Date` headers.

**Remediation**: Replace `HttpDate.parse` with a custom or package-based HTTP date parser.
Replace exception types as described in 3.3.

---

### 3.5 `lib/bloc/system_health/providers/http_time_provider.dart`

```dart
import 'dart:io';                              // line 2

throw HttpException(                           // line 49
  'API request failed with status ${response.statusCode}',
  uri: Uri.parse(url),
);
```

**Problem**: Uses `HttpException` from `dart:io`.

**Remediation**: Replace with custom exception class.

---

### 3.6 `lib/bloc/system_health/providers/ntp_time_provider.dart`

```dart
import 'dart:io';                              // line 2

} on SocketException catch (e) {               // line 57
```

**Problem**: Uses `SocketException` from `dart:io`. Additionally, the `ntp` package itself
depends on `dart:io` sockets. However, `NtpTimeProvider` is only constructed when
`!kIsWeb && !kIsWasm` -- the real problem is this file being **imported** unconditionally.

**Remediation**: Move `NtpTimeProvider` behind a conditional import so it is never resolved
on web. See Section 4 for the import chain analysis.

---

### 3.7 `lib/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart`

```dart
import 'dart:io' show Platform;                // line 2

final bool isLinux = !kIsWeb && !kIsWasm && Platform.isLinux;  // line 239
```

**Problem**: Explicit `show Platform` still causes `dart:io` to be resolved.

**Remediation**: Use `defaultTargetPlatform == TargetPlatform.linux` from
`package:flutter/foundation.dart` instead. This is already the pattern used in
`platform_tuner.dart` and works on all targets.

---

### 3.8 `lib/views/fiat/webview_dialog.dart`

```dart
import 'dart:io';                              // line 1

final bool isLinux = !kIsWeb && !kIsWasm && Platform.isLinux;  // line 51
```

**Problem**: Same `Platform.isLinux` pattern as 3.7.

**Remediation**: Same as 3.7 -- use `defaultTargetPlatform`.

---

### 3.9 `lib/views/nfts/details_page/withdraw/nft_withdraw_form.dart`

```dart
import 'dart:io';                              // line 1

suffixIcon: (!kIsWeb && (Platform.isAndroid || Platform.isIOS))  // line 144
    ? IconButton(icon: const Icon(Icons.qr_code_scanner), ...)
    : null,
```

**Problem**: Uses `Platform.isAndroid` / `Platform.isIOS` to conditionally show QR scanner.

**Remediation**: Use `defaultTargetPlatform == TargetPlatform.android` etc., guarded by
`!kIsWeb`.

---

### 3.10 `lib/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fill_form_recipient_address.dart`

```dart
import 'dart:io';                              // line 1

suffixIcon: (!kIsWeb && (Platform.isAndroid || Platform.isIOS))  // line 74
    ? IconButton(icon: const Icon(Icons.qr_code_scanner), ...)
    : null,
```

**Problem**: Identical pattern to 3.9.

**Remediation**: Same as 3.9.

---

### 3.11 `lib/shared/utils/zip.dart`

```dart
import 'dart:io';                              // line 2

final compressedBytes =
    Uint8List.fromList(ZLibCodec(raw: true).encode(originalBytes));  // line 15
```

**Problem**: `ZLibCodec` is a `dart:io` class. It is not available on web/WASM targets.
See Section 8 for full analysis.

---

## 4. Critical: Transitive `dart:io` via Import Chains

### 4.1 `time_provider_registry.dart` -> All 4 Time Providers

`lib/bloc/system_health/providers/time_provider_registry.dart` imports all four time
provider files at the top level:

```dart
import 'package:web_dex/bloc/system_health/providers/binance_time_provider.dart';   // line 2
import 'package:web_dex/bloc/system_health/providers/http_head_time_provider.dart'; // line 3
import 'package:web_dex/bloc/system_health/providers/http_time_provider.dart';      // line 4
import 'package:web_dex/bloc/system_health/providers/ntp_time_provider.dart';       // line 5
```

Even though `NtpTimeProvider` and `HttpHeadTimeProvider` are only **constructed** inside
`if (!kIsWeb && !kIsWasm)` guards (lines 29, 33), the **imports** are unconditional. This
means every file that imports `time_provider_registry.dart` transitively pulls in `dart:io`
from all four providers.

**Import chain to `main()`**:
`main.dart` -> `app_bootstrapper.dart` -> (via various BLoC/service registrations) ->
`system_health_bloc.dart` -> `time_provider_registry.dart` -> all 4 time providers ->
`dart:io`.

**Remediation options**:

1. **Best**: Remove `dart:io` from `binance_time_provider.dart`, `http_time_provider.dart`,
   and `http_head_time_provider.dart` by replacing `dart:io` exception types with
   cross-platform alternatives. Move `ntp_time_provider.dart` behind a conditional import
   since the `ntp` package itself requires `dart:io`.

2. **Alternative**: Create a conditional import barrel that only exports native-only
   providers on native targets and web-only providers on web targets.

### 4.2 `get_logger.dart` -> `get_storage.dart`

`get_logger.dart` (line 14) imports `get_storage.dart`, which itself imports `dart:io`.
Both files are imported from `main.dart`. This creates a double-import chain for `dart:io`.

---

## 5. Correct: Files Protected by Conditional Imports

These files demonstrate the correct pattern and do **not** need changes:

| Barrel File | Native Implementation | Web Implementation | Stub |
| ----------- | -------------------- | ------------------ | ---- |
| `lib/platform/platform.dart` | `platform_native.dart` | `platform_web.dart` | -- |
| `lib/services/file_loader/file_loader.dart` | `file_loader_native.dart` | `file_loader_web.dart` | `file_loader_stub.dart` |
| `lib/shared/utils/window/window.dart` | `window_native.dart` | `window_web.dart` | `window_stub.dart` |
| `lib/services/platform_info/platform_info.dart` | `native_platform_info.dart` | `web_platform_info.dart` | `stub.dart` |
| `lib/services/platform_web_api/platform_web_api.dart` | `platform_web_api_stub.dart` | `platform_web_api_web.dart` | `platform_web_api_implementation.dart` |
| `lib/sdk/widgets/window_close_handler.dart` | `dart:io` (for `exit()`) | `window_close_handler_exit_stub.dart` | -- |

SDK-level correct patterns:

| Barrel File | Native | Web/WASM |
| ----------- | ------ | -------- |
| `sdk/.../kdf_operations_factory.dart` | `kdf_operations_native.dart` | `kdf_operations_wasm.dart` |
| `sdk/.../event_streaming_service.dart` | `event_streaming_platform_io.dart` | `event_streaming_platform_web.dart` |
| `sdk/.../dragon_logs/.../log_storage.dart` | `log_storage_native_platform.dart` | `log_storage_web_platform.dart` / `log_storage_wasm_platform.dart` |

---

## 6. High: `dartify()` / `jsify()` Number Type Coercion

### 6.1 `lib/mm2/rpc_web.dart` (line 17)

```dart
final JSAny? jsResponse = await wasmRpc(reqStr).toDart;
final dynamic response = jsResponse?.dartify();    // line 17
```

**Impact**: This is the primary RPC communication path for all KDF operations on web. Every
RPC response passes through `dartify()`. In WASM:

- Integer fields (block heights, timestamps, satoshi amounts, nonces) become `double`.
- Downstream code performing `value is int` checks will get `false`.
- Precision loss is possible for values exceeding `2^53` (unlikely for most fields but
  theoretically possible for some blockchain data).

**Current mitigation**: Lines 22-33 check `if (response is String)` and fall through to
`jsonDecode(payload)`, which **does** correctly parse numbers from JSON strings. If the
WASM RPC always returns a string response, this path avoids the `dartify()` number issue.
However, if the response is a non-string JS object, `dartify()` applies and numbers are
coerced.

**Remediation**: Convert the JS response to a Dart `String` explicitly and always use
`jsonDecode`. Replace `dartify()` with `(jsResponse as JSString).toDart` or similar typed
conversion, since KDF RPC responses are JSON strings.

### 6.2 `lib/services/file_loader/file_loader_web.dart` (line 173)

```dart
final dartResult = result.dartify();
if (dartResult case final String content) { ... }
```

**Impact**: Lower risk -- this reads file contents via `FileReader.readAsText`, which
returns a string. The `dartify()` call will return a `String` in practice. The `case`
pattern match ensures only strings are accepted. No numeric data flows through this path.

**Remediation**: Replace with `(result as JSString).toDart` for type safety and
to avoid potential future issues if the `FileReader` API changes.

---

## 7. High: Hive CE / IndexedDB WASM Data-Type Issues

### 7.1 `int` -> `double` Coercion

Hive CE uses IndexedDB as its backing store on web. In WASM builds, `int` values saved to
Hive boxes are retrieved as `double`. This is a known issue
([hive_ce#46](https://github.com/IO-Design-Team/hive_ce/issues/46)).

**Affected areas**:
- `packages/komodo_persistence_layer/` -- Hive-based persistence
- `lib/main.dart` -> `app_bootstrapper.dart` lines 98-106 -- Hive initialization
- Any BLoC or repository that stores/retrieves integer values via Hive

**Remediation**:
- Use `Box<int>` with explicit type annotations where possible.
- Add `.toInt()` coercion when reading values from Hive boxes.
- Audit all Hive read operations for `int` expectations.

### 7.2 Multi-Tab IndexedDB Locking

Opening the app in multiple browser tabs with Hive boxes causes IndexedDB locking issues
([hive_ce#30](https://github.com/IO-Design-Team/hive_ce/issues/30)). If one tab deletes
a box, other tabs freeze.

**Remediation**: Consider using the `BroadcastChannel` API or `SharedWorker` for
cross-tab coordination, or document single-tab usage as a known limitation.

### 7.3 Persistence Not Guaranteed

IndexedDB data may not persist across browser sessions without explicit persistence API
calls ([hive_ce#73](https://github.com/IO-Design-Team/hive_ce/issues/73)). Disabling the
service worker with `--pwa-strategy=none` has been reported to resolve this.

**Current state**: No `--pwa-strategy` flag is set in the build command.

---

## 8. High: `ZLibCodec` from `dart:io`

`lib/shared/utils/zip.dart` (line 2, 15):

```dart
import 'dart:io';
// ...
final compressedBytes =
    Uint8List.fromList(ZLibCodec(raw: true).encode(originalBytes));
```

`ZLibCodec` is part of `dart:io` and is not available on web/WASM targets. This file is
used for creating zip archives of log files for export.

**Remediation options**:

1. Use the `archive` package, whose `ZLibEncoder` auto-detects the platform and falls back
   to a pure-Dart Deflate implementation on web.
2. Use the `CompressionStream` / `DecompressionStream` Web APIs via `dart:js_interop` on
   web targets, with `ZLibCodec` on native targets (conditional import).
3. Use a pure-Dart zlib implementation (e.g., from the `archive` package or `package:lzma`).

---

## 9. Medium: Deferred Import Regression

`lib/main.dart` (line 19):

```dart
import 'package:web_dex/bloc/app_bloc_root.dart' deferred as app_bloc_root;
```

Dart 3.11.0 introduced a regression where deferred imports crash `dart2wasm` with exit
code 255 ([dart-lang/sdk#62683](https://github.com/dart-lang/sdk/issues/62683)). The error
is: `CheckLibraryIsLoaded should be lowered by modular transformer`.

**Current state**: The SDK constraint is `>=3.8.1`, so the exact Dart version used in CI
determines whether this is hit. If using Dart 3.10.x or earlier, this works. If CI updates
to Dart 3.11.0, this will break.

**Remediation**:
- Pin Dart SDK version in CI to avoid accidental breakage.
- Monitor the upstream fix and remove the deferred import if it becomes a blocker.
- Alternatively, remove the deferred import entirely (trading startup performance for
  reliability).

---

## 10. Medium: `compute()` and Isolate Limitations

### 10.1 Usage in SDK (Safe)

| File | Usage | Protected? |
| ---- | ----- | ---------- |
| `sdk/.../kdf_operations_native.dart` | `compute()` at ~line 198, 250 | Yes -- behind `dart.library.io` conditional import |
| `sdk/.../dragon_logs/.../file_log_storage.dart` | `compute()` at ~line 147 | Yes -- native-only path |

### 10.2 No Isolate Usage

No `Isolate.spawn` or `Isolate.spawnUri` calls were found anywhere in the codebase.

### 10.3 `gap.dart` False Positives

`lib/shared/ui/gap.dart` (line 317) and `packages/komodo_ui_kit/lib/src/utils/gap.dart`
(line 318) define a local `compute` callback parameter. These are **not** Flutter's
`foundation.compute` and are safe.

---

## 11. Medium: COOP/COEP Cross-Origin Isolation Headers

`firebase.json` (lines 10-23):

```json
"headers": [
  {
    "source": "**",
    "headers": [
      { "key": "Cross-Origin-Embedder-Policy", "value": "credentialless" },
      { "key": "Cross-Origin-Opener-Policy", "value": "same-origin" }
    ]
  }
]
```

### 11.1 Current Configuration

- `COEP: credentialless` -- less strict than `require-corp`. Allows cross-origin no-CORS
  requests without requiring the target to send `Cross-Origin-Resource-Policy` headers.
- `COOP: same-origin` -- restricts `window.opener` to same-origin pages.

This combination enables `self.crossOriginIsolated === true` in supporting browsers, which
is required for `SharedArrayBuffer` and multi-threaded WASM.

### 11.2 Compatibility Risks

- `credentialless` was added in Chrome 96, Firefox 119, and Safari 18.2.
- Older browsers that do not support `credentialless` will **not** be cross-origin isolated,
  causing WASM to fall back to single-threaded execution.
- `require-corp` would be stricter but would break cross-origin fetches to APIs that do not
  set CORP headers (Binance API, CEX data endpoints, Banxa/Ramp iframes).

### 11.3 Recommendation

The current `credentialless` approach is the correct trade-off for a wallet app that needs
to fetch from many third-party APIs. Document the browser version requirements.

---

## 12. Medium: Third-Party Plugin WASM Compatibility

| Package | Version | WASM Status | Risk | Notes |
| ------- | ------- | ----------- | ---- | ----- |
| `flutter_inappwebview` | `6.1.5` | Partial | Medium | pubspec.yaml comment: "Web (currently broke, open issue)". Uses iframe-based approach on web. |
| `window_size` | git dep | Desktop-only | None | No web implementation. Guarded by `PlatformTuner.isNativeDesktop` check. |
| `ntp` | `^2.0.0` | Not web-compatible | High | Uses `dart:io` sockets. Only instantiated when `!kIsWeb && !kIsWasm` but **imported unconditionally** via `ntp_time_provider.dart`. |
| `file_picker` | (from lockfile) | Needs verification | Medium | Older versions used `dart:html`. Verify current version uses `package:web`. |
| `path_provider` | (from lockfile) | Web stub | Low | Returns empty/stub paths on web. Used in `app_config.dart` behind `kIsWeb` check. |
| `hive_ce` / `hive_ce_flutter` | `^2.19.3` | WASM-aware | Medium | See Section 7 for data-type caveats. |
| `flutter_web_plugins` | SDK | Full support | None | Part of Flutter SDK, WASM-compatible. |
| `url_launcher` | (from lockfile) | Full support | None | Web implementation available. |
| `matomo_tracker` | `^6.1.0` | Needs verification | Low | HTTP-based, likely works but verify no `dart:io` dependency. |
| `feedback` | `^3.2.0` | Needs verification | Low | UI-only package, likely works. |

---

## 13. Medium: SDK Package Issues

### 13.1 `komodo_defi_local_auth` -- Unconditional `dart:io`

`sdk/packages/komodo_defi_local_auth/lib/src/auth/auth_service.dart` (line 2):

```dart
import 'dart:io';
```

This package is consumed by the app via `komodo_defi_sdk`. The `dart:io` import is
unconditional and will propagate through the dependency chain to the web compilation target.

**Also in** `auth_service_operations_extension.dart`:
```dart
kIsWeb || Platform.isWindows  // uses Platform from dart:io
```

**Remediation**: This is in the SDK submodule. A fix requires either:
1. A PR to the SDK repo to add conditional imports.
2. A platform abstraction that avoids `dart:io` on web.

### 13.2 `komodo_defi_framework` -- Properly Split (OK)

The factory pattern in `kdf_operations_factory.dart` correctly uses conditional imports:

```dart
import 'kdf_operations_wasm.dart'
    if (dart.library.io) 'kdf_operations_native.dart'
    if (dart.library.js_interop) 'kdf_operations_wasm.dart'
    as local;
```

FFI code (`dart:ffi`) is only in `kdf_operations_native.dart`, which is never resolved on
web targets.

### 13.3 `dragon_logs` -- Uses `dart.tool.dart2wasm` (Best Practice)

`sdk/packages/dragon_logs/lib/src/storage/log_storage.dart`:

```dart
import 'log_storage_web_platform.dart'
    if (dart.library.io) 'log_storage_native_platform.dart'
    if (dart.tool.dart2wasm) 'log_storage_wasm_platform.dart';
```

This is the most precise conditional import pattern available, distinguishing between
dart2js (web platform), native, and dart2wasm.

---

## 14. Low: JS Interop Correctness (Passing)

All JS interop in the codebase uses the modern `dart:js_interop` API with `@JS()`
extension types. No legacy APIs were found.

| File | Interop Pattern |
| ---- | --------------- |
| `lib/platform/platform_web.dart` | `@JS('kdf')` extension type for KDF WASM bindings |
| `lib/shared/utils/browser_helpers.dart` | `@JS('navigator.brave.isBrave')` for Brave detection |
| `lib/services/platform_web_api/platform_web_api_web.dart` | `@JS()` extension type for CSS style access |
| `web/kdf/res/kdf_wrapper.dart` | `@JS('mm2_main')` etc. for KDF wrapper (comment: not currently used) |
| `sdk/.../dragon_logs/.../opfs_interop.dart` | `@JS()` extension types for OPFS async iterators |

**Verification**: Grep for `dart:html`, `dart:js`, `dart:js_util` returned zero matches in
all `.dart` files across the repository.

---

## 15. Low: Build Pipeline Validation

### 15.1 CI Build Command

`.github/actions/generate-assets/action.yml` (line 11):

```yaml
default: "flutter build web --no-pub --release --wasm"
```

The `--wasm` flag is the default build command. This means every CI build already validates
WASM compilation.

### 15.2 Build Validation

`.github/actions/validate-build/action.yml` checks for:
- WASM binary at `build/web/kdf/kdf/bin/*.wasm`
- `web/index.html` matches `build/web/index.html`
- `AssetManifest.bin` exists
- KDF config files present under `build/web/assets/packages/komodo_defi_framework/`

### 15.3 Workflows Using Web Build

| Workflow | Trigger |
| -------- | ------- |
| `firebase-hosting-merge.yml` | Push to `dev` |
| `firebase-hosting-pull-request.yml` | PR preview |
| `sdk-integration-preview.yml` | SDK integration PR |
| `ui-tests-on-pr.yml` | PR (Chrome + Safari matrix) |

---

## 16. Informational: `analysis_options.yaml`

The current `analysis_options.yaml` includes `bloc_lint/recommended.yaml` and
`flutter_lints/flutter.yaml` but has **no WASM-specific lint rules**.

**Recommendation**: Consider adding custom lint rules or analysis plugins that detect:
- Unconditional `dart:io` imports in files not behind conditional import barrels.
- `Platform.is*` usage without `kIsWeb` guards.
- `dartify()` / `jsify()` usage in financial calculation paths.

---

## 17. Complete File Inventory

### 17.1 Files with Unconditional `dart:io` in `lib/` (Action Required)

| # | File | `dart:io` Symbols Used | Reachable from `main()`? |
| - | ---- | ---------------------- | ----------------------- |
| 1 | `lib/services/storage/get_storage.dart` | `Platform.isWindows`, `Platform.environment` | Yes |
| 2 | `lib/services/logger/get_logger.dart` | `Platform.is*` (all 5) | Yes |
| 3 | `lib/bloc/system_health/providers/binance_time_provider.dart` | `SocketException`, `HttpException` | Yes (via registry) |
| 4 | `lib/bloc/system_health/providers/http_head_time_provider.dart` | `SocketException`, `HttpException`, `HttpDate` | Yes (via registry) |
| 5 | `lib/bloc/system_health/providers/http_time_provider.dart` | `HttpException` | Yes (via registry) |
| 6 | `lib/bloc/system_health/providers/ntp_time_provider.dart` | `SocketException` | Yes (via registry) |
| 7 | `lib/bloc/fiat/fiat_onramp_form/fiat_form_bloc.dart` | `Platform.isLinux` | Yes |
| 8 | `lib/views/fiat/webview_dialog.dart` | `Platform.isLinux` | Yes |
| 9 | `lib/views/nfts/details_page/withdraw/nft_withdraw_form.dart` | `Platform.isAndroid`, `Platform.isIOS` | Yes |
| 10 | `lib/views/wallet/.../fill_form_recipient_address.dart` | `Platform.isAndroid`, `Platform.isIOS` | Yes |
| 11 | `lib/shared/utils/zip.dart` | `ZLibCodec` | Yes |

### 17.2 Files with Conditional `dart:io` in `lib/` (No Action Required)

| # | File | Conditional Pattern |
| - | ---- | ------------------- |
| 1 | `lib/platform/platform.dart` | `if (dart.library.js_interop)` |
| 2 | `lib/services/file_loader/file_loader.dart` | `if (dart.library.io)` / `if (dart.library.js_interop)` |
| 3 | `lib/shared/utils/window/window.dart` | `if (dart.library.io)` / `if (dart.library.js_interop)` |
| 4 | `lib/services/platform_info/platform_info.dart` | `if (dart.library.js_interop)` / `if (dart.library.io)` |
| 5 | `lib/services/platform_web_api/platform_web_api.dart` | `if (dart.library.js_interop)` / `if (dart.library.io)` |
| 6 | `lib/sdk/widgets/window_close_handler.dart` | `if (dart.library.js_interop)` |

### 17.3 Native-Only Files (Never Resolved on Web)

These files are only resolved via conditional imports on native targets:

- `lib/platform/platform_native.dart`
- `lib/services/file_loader/file_loader_native.dart`
- `lib/services/file_loader/file_loader_native_desktop.dart`
- `lib/services/file_loader/mobile/file_loader_native_android.dart`
- `lib/services/file_loader/mobile/file_loader_native_ios.dart`
- `lib/services/platform_info/native_platform_info.dart`
- `lib/shared/utils/window/window_native.dart`
- `lib/services/platform_web_api/platform_web_api_stub.dart`

### 17.4 Web-Only Files (Only Resolved on Web)

- `lib/platform/platform_web.dart`
- `lib/services/file_loader/file_loader_web.dart`
- `lib/services/platform_web_api/platform_web_api_web.dart`
- `lib/shared/utils/window/window_web.dart`
- `lib/shared/utils/browser_helpers.dart`
- `lib/mm2/rpc_web.dart`

### 17.5 SDK Files with `dart:io` (For Awareness)

| File | Protected? |
| ---- | ---------- |
| `sdk/.../komodo_defi_local_auth/.../auth_service.dart` | **No** -- unconditional |
| `sdk/.../komodo_defi_framework/.../kdf_operations_native.dart` | Yes -- conditional |
| `sdk/.../komodo_defi_framework/.../komodo_defi_framework_bindings_generated.dart` | Yes -- conditional |
| `sdk/.../komodo_defi_framework/.../event_streaming_platform_io.dart` | Yes -- conditional |
| `sdk/.../dragon_logs/.../file_log_storage.dart` | Yes -- native-only |
| `sdk/.../komodo_defi_sdk/.../zcash_params_downloader_factory.dart` | Partially -- uses `kIsWeb` guard |

### 17.6 Clean Packages (No WASM Issues)

- `app_theme/` -- zero `dart:io`, `Platform`, or WASM-related imports.
- `packages/komodo_ui_kit/` -- zero `dart:io` imports.
- `packages/komodo_persistence_layer/` -- zero `dart:io` imports (uses Hive CE).

---

## 18. Dependency Flow Diagrams

### 18.1 `dart:io` Contamination from Time Providers

```
main.dart
  └─> app_bootstrapper.dart (part of main.dart)
        └─> (service registration chain)
              └─> system_health_bloc.dart (or similar consumer)
                    └─> time_provider_registry.dart
                          ├─> binance_time_provider.dart ──> dart:io (SocketException, HttpException)
                          ├─> http_head_time_provider.dart ──> dart:io (SocketException, HttpException, HttpDate)
                          ├─> http_time_provider.dart ──> dart:io (HttpException)
                          └─> ntp_time_provider.dart ──> dart:io (SocketException) + ntp package (dart:io sockets)
```

### 18.2 `dart:io` Contamination from Storage/Logger

```
main.dart
  ├─> get_storage.dart ──> dart:io (Platform.isWindows, Platform.environment)
  └─> get_logger.dart ──> dart:io (Platform.is*)
        └─> get_storage.dart ──> dart:io (double import)
```

### 18.3 `dart:io` Contamination from UI Components

```
main.dart
  └─> (navigation/routing)
        ├─> webview_dialog.dart ──> dart:io (Platform.isLinux)
        ├─> fiat_form_bloc.dart ──> dart:io (Platform.isLinux)
        ├─> nft_withdraw_form.dart ──> dart:io (Platform.isAndroid/isIOS)
        └─> fill_form_recipient_address.dart ──> dart:io (Platform.isAndroid/isIOS)
```

### 18.4 Correct Conditional Import Flow (for Reference)

```
main.dart
  └─> platform/platform.dart
        ├─ [dart.library.io] ──> platform_native.dart ──> (native KDF, dart:io OK)
        └─ [dart.library.js_interop] ──> platform_web.dart ──> (WASM KDF, dart:js_interop)
```

---

## 19. Remediation Priority Matrix

### P0 -- Compilation Blockers

These must be fixed to ensure WASM compilation does not break under standard Dart toolchains.

| # | Issue | Files | Effort | Approach |
| - | ----- | ----- | ------ | -------- |
| 1 | `get_storage.dart` unconditional `dart:io` | 1 file | Low | Split into conditional import pattern (web always returns `AppStorage()`) |
| 2 | `get_logger.dart` unconditional `dart:io` | 1 file | Low | Split into conditional import pattern (web always returns `UniversalLogger`) |
| 3 | Time providers using `dart:io` exceptions | 4 files | Medium | Replace `SocketException`/`HttpException`/`HttpDate` with cross-platform equivalents; move `NtpTimeProvider` behind conditional import |
| 4 | `time_provider_registry.dart` transitive imports | 1 file | Low | Restructure imports to use conditional import barrel or lazy provider registration |
| 5 | `zip.dart` using `ZLibCodec` | 1 file | Medium | Replace with `archive` package `ZLibEncoder` or pure-Dart deflate implementation |
| 6 | UI files using `Platform.is*` | 4 files | Low | Replace with `defaultTargetPlatform` from `package:flutter/foundation.dart` |
| 7 | SDK `auth_service.dart` unconditional `dart:io` | 1 file (SDK) | Medium | PR to SDK repo adding conditional imports |

### P1 -- Runtime Correctness

These compile but produce incorrect behavior in WASM.

| # | Issue | Files | Effort | Approach |
| - | ----- | ----- | ------ | -------- |
| 8 | `dartify()` number coercion in RPC path | 1 file | Medium | Replace with explicit `(jsResponse as JSString).toDart` + `jsonDecode` |
| 9 | Hive CE `int`->`double` coercion | Multiple | High | Audit all Hive read operations; add `.toInt()` coercion; use typed boxes |
| 10 | `file_loader_web.dart` `dartify()` | 1 file | Low | Replace with `(result as JSString).toDart` |
| 11 | `file_picker` package WASM compatibility | 1 dep | Low | Verify current version in lockfile uses `package:web` |

### P2 -- Robustness and Future-Proofing

| # | Issue | Files | Effort | Approach |
| - | ----- | ----- | ------ | -------- |
| 12 | Deferred import regression in `main.dart` | 1 file | Low | Pin Dart SDK version in CI; monitor upstream fix |
| 13 | No WASM-specific lint rules | 1 file | Low | Add custom lint rules to `analysis_options.yaml` |
| 14 | `credentialless` COEP browser support | Config | Low | Document minimum browser versions; add graceful fallback |
| 15 | `ntp` package `dart:io` dependency | 1 dep | Low | Already guarded at runtime; ensure import-level isolation |
| 16 | `flutter_inappwebview` web support broken | 1 dep | Low | Document known limitation; monitor upstream fixes |

### P3 -- Nice-to-Have

| # | Issue | Effort | Approach |
| - | ----- | ------ | -------- |
| 17 | Add `dart.tool.dart2wasm` condition to app-level conditional imports | Low | Follow `dragon_logs` pattern for finer-grained WASM detection |
| 18 | Add WASM integration smoke test to CI | Medium | Create a minimal web test that verifies WASM binary loads and RPC responds |
| 19 | Create shared `PlatformUtils` for `Platform.is*` replacements | Low | Centralize `defaultTargetPlatform` checks with `kIsWeb` guards |
| 20 | Multi-tab Hive locking mitigation | Medium | Investigate `BroadcastChannel` API for cross-tab coordination |
| 21 | Hive persistence guarantee | Low | Consider adding `--pwa-strategy=none` to build command |

---

## Appendix A: dart:io Symbol Usage Map

Exhaustive mapping of every `dart:io` symbol used in `lib/`:

| Symbol | Files Using It |
| ------ | -------------- |
| `Platform.isWindows` | `get_storage.dart`, `get_logger.dart` |
| `Platform.isMacOS` | `get_logger.dart` |
| `Platform.isLinux` | `get_logger.dart`, `fiat_form_bloc.dart`, `webview_dialog.dart` |
| `Platform.isAndroid` | `get_logger.dart`, `nft_withdraw_form.dart`, `fill_form_recipient_address.dart` |
| `Platform.isIOS` | `get_logger.dart`, `nft_withdraw_form.dart`, `fill_form_recipient_address.dart` |
| `Platform.environment` | `get_storage.dart` |
| `SocketException` | `binance_time_provider.dart`, `http_head_time_provider.dart`, `ntp_time_provider.dart` |
| `HttpException` | `binance_time_provider.dart`, `http_head_time_provider.dart`, `http_time_provider.dart` |
| `HttpDate` | `http_head_time_provider.dart` |
| `ZLibCodec` | `zip.dart` |
| `exit()` | `window_native.dart` (behind conditional import -- safe) |
| `File` | `file_loader_native_*.dart` (behind conditional import -- safe) |

---

## Appendix B: Conditional Import Reference

### Recommended Pattern for New Files

```dart
// my_service.dart (barrel)
import 'my_service_stub.dart'
    if (dart.library.io) 'my_service_native.dart'
    if (dart.library.js_interop) 'my_service_web.dart';

abstract class MyService {
  factory MyService() => createMyService();  // defined in each implementation
}
```

### Evaluation Order

Conditions are evaluated top-to-bottom. The first matching condition wins:

1. `dart.library.io` -- matches native VM (Android, iOS, macOS, Windows, Linux)
2. `dart.library.js_interop` -- matches dart2js AND dart2wasm
3. `dart.library.html` -- matches dart2js only (NOT dart2wasm)
4. `dart.tool.dart2wasm` -- matches dart2wasm only

### Replacing `Platform.is*` Without `dart:io`

```dart
import 'package:flutter/foundation.dart';

bool get isNativeMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
     defaultTargetPlatform == TargetPlatform.iOS);

bool get isNativeDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
     defaultTargetPlatform == TargetPlatform.windows ||
     defaultTargetPlatform == TargetPlatform.linux);

bool get isNativeLinux =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
```

This is already the pattern used in `lib/shared/utils/platform_tuner.dart`.

---

## Appendix C: WASM vs dart2js Behavioural Differences

| Behaviour | dart2js | dart2wasm |
| --------- | ------- | --------- |
| `int` and `double` distinction | None (both JS `number`) | True `int64` + `double` internally |
| `dartify()` on JS integers | Returns `int` | Returns `double` |
| `is int` on JS number | `true` | `false` |
| `Isolate` / `compute()` | Not available | Not available |
| `dart:html` | Available | **Not available** |
| `dart:js` | Available (deprecated) | **Not available** |
| `dart:js_util` | Available (deprecated) | **Not available** |
| `dart:js_interop` | Available | Available |
| `package:web` | Available | Available |
| `dart:io` | Not available | Not available |
| `dart:ffi` | Not available | Not available |
| `dart:mirrors` | Not available | Not available |
| Deferred imports | Supported | Supported (regression in 3.11.0) |
| `SharedArrayBuffer` | Requires COOP/COEP | Requires COOP/COEP |
| Multi-threading | N/A | Via `SharedArrayBuffer` |
| Integer overflow | Wraps at 2^53 | True 64-bit integers |
| String representation | JS strings | WTF-16 strings |

---

*End of audit. All files in `lib/`, `sdk/`, `packages/`, `app_theme/`, `web/`, and CI
configuration have been reviewed.*
