# Flutter 3.50 / Dart 3.14 migration

The app and SDK are upgraded together from the app's Flutter 3.41.4 pin to
Flutter **3.50.0**, Dart **3.14.0** (stable, November 11, 2026).
Framework revision: `ab2912035e160d9cad6306df307576da6128ebdb`.

## Toolchain and dependency changes

- FVM selects the exact release for both repositories. CI must agree with both
  `.fvmrc` files; the app checks the SDK pin before installing Flutter.
- Workspace packages require Dart 3.14 and Flutter packages require Flutter
  3.50. BLoC lint and SDK code generators are upgraded to support the analyzer
  required by Flutter's pinned test packages.
- The obsolete `intl` override is removed; the app uses the version range
  required by Flutter localizations. Lockfiles are resolved by the new SDK.
- Old generated Freezed parameters must be regenerated: Dart 3.13 and later
  reject `final` on ordinary parameters. Mutable nullable local promotion may
  also be lost across `await`; capture stable task identifiers explicitly.

## Platforms

| Platform | Migration |
| --- | --- |
| Android | AGP 9.3.1, Gradle 9.5.0, Kotlin 2.4.20; Java 17 bytecode with JDK 21 in CI. Retain Flutter's legacy Kotlin/DSL compatibility flags for current plugins. SDK example hosts use the declarative plugin loader. KDF hosts constrain `defaultConfig` to ARM32/ARM64; build-type filters merge with Flutter's new defaults and can otherwise advertise an x86_64 runtime without KDF. |
| iOS | The app already has UIScene engine/plugin registration and an iOS 15.6 minimum. SDK examples gain UIScene manifests and implicit-engine registration, with at least iOS 15. |
| macOS | The app already targets macOS 13.5. SDK examples and plugin specifications require at least macOS 12. Retain Intel support. |
| Windows | Preserve the app's Visual Studio 2022 CI runner for its existing plugins. SDK product CMake projects install native assets and pass the target platform to Flutter. |
| Linux | Retain the GTK/WebKit build configuration and existing CI build. Native Linux compilation requires a Linux host. |
| Web | Retain JavaScript and Wasm build paths. The app does not opt into `viewport-fit=cover`, so the new cutout behavior needs no viewport change. |

## Behavior and compatibility

Accessibility headings now provide explicit levels while preserving desktop
header semantics. `ListTile` surfaces use `Material` instead of an opaque
decoration between the tile and its Material ancestor.

The latest stable `flutter_inappwebview_android` still requests the old ProGuard
configuration; its documented AGP compatibility property is retained until the
plugin migrates. CocoaPods remains supported in this release and is retained for
plugins that do not yet support Swift Package Manager.

The Docker image reads `.fvmrc` directly, uses Android API/build-tools 36 and the
same NDK as the app, and preserves local SDK edits. Both Android artifact paths
run `android/verify_apk.py` before upload to reject incomplete native runtimes.

Flutter's bundled Material/Cupertino imports are deprecated but still supported
in 3.50. Their extracted packages expose distinct types; moving the app and SDK
public APIs requires a coordinated migration of third-party packages. This
upgrade retains the existing imports. Analysis reports those deprecations; CI
continues its existing policy of failing on errors rather than all lint infos.

## Validation

Validated with the pinned FVM toolchain on November 15, 2026:

| Check | Result |
| --- | --- |
| App unit/widget aggregator with the four production GasFree defines | 4,015 passed, 4 skipped |
| App-owned UI and persistence package suites | 2 passed; persistence verifies real Hive close/reopen, update and deletion |
| SDK package suites | All 16 suites passed: 3,130 tests, 14 skipped |
| SDK Chrome/Wasm cases | 215 SDK cases and 10 framework cases passed |
| Release app bundle | Passed after the expected first-pass asset refresh |
| Android release APK | Passed; exactly ARM32/ARM64 with Flutter, app and KDF libraries; ZIP and arm64 ELF segments verified for 16 KB pages |
| iOS release | Unsigned device build passed with Xcode 27.2 |
| macOS release | Unsigned universal x86_64/arm64 app and bundled KDF helper passed |
| Web release | Wasm and JavaScript fallback build passed |
| Signed-out browser smoke | Release/headless Chrome passed app-bar, wallet-row, maker/taker and settings navigation; the test uses the dialog's real Cancel control |
| App/SDK lockfiles | Enforced resolution passed |
| Supporting gates | LI.FI production configuration, Docker regressions, APK-verifier regressions, theme-role checks, hosting URL parsing and Bitrefill bridge tests passed |

The full app analysis has zero errors, 64 warnings and 3,203 infos. These remain, including
Material/Cupertino deprecations; the existing CI policy passes, while plain
`flutter analyze` still returns nonzero. See the SDK toolchain guide for its
separate diagnostic counts.

Independent adversarial reviews covered native configuration, generated code,
dependency/CI integrity, widget behavior, and final APK contents. Findings were
fixed before opening the draft PRs. Windows/Linux native builds and the full
network-backed integration matrix are left to their CI hosts; local native
build results do not claim those platforms have passed.

The SDK dependency is proposed in
[SDK PR #447](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/447).
Merge the SDK change before the wallet change and retain a reachable submodule
commit (repin if the SDK PR is squash-merged).

## References

- [Flutter 3.50 announcement](https://flutter.dev/blog/whats-new-in-flutter-3-50)
- [Dart changelog](https://dart.dev/changelog)
- [Supported platforms](https://docs.flutter.dev/reference/supported-platforms)
- [Android Kotlin migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)
- [UIScene migration](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)
- [Material/Cupertino extraction](https://docs.flutter.dev/release/breaking-changes/material-ui-and-cupertino-ui)
