# Build Release version of the App

For 0.10.0, follow the [production build](RELEASE_0.10.0_PRODUCTION_BUILD.md).
Its defines, flags and output checks were verified against that release and
take precedence where this generic guide differs.

## Environment setup

Before building the app, make sure you have all the necessary tools installed. Follow the instructions in the [Environment Setup](./PROJECT_SETUP.md) document. Alternatively, you can use the Docker image as described here: (TODO!).

### Firebase Analytics Setup

Optionally, you can enable Firebase Analytics for the app. To do so, follow the instructions in the [Firebase Analytics Setup](./FIREBASE_SETUP.md) document.

## Security Considerations

⚠️ **IMPORTANT**: For all production builds, be sure to follow the security practices outlined in the [Build Security Advisory](./BUILD_SECURITY_ADVISORY.md). Always use `--enforce-lockfile` and `--no-pub` flags when building for production.

## GitHub release preflight

Run this check from a clean checkout of the exact app release commit before
creating the app tag or GitHub release. It verifies that the SDK package version
used by the pinned submodule has already been tagged in the upstream SDK
repository.

```bash
(
set -euo pipefail
git submodule update --init sdk

SDK_VERSION="$(sed -n 's/^version: //p' sdk/packages/komodo_defi_sdk/pubspec.yaml)"
SDK_TAG="komodo_defi_sdk-v${SDK_VERSION}"
SDK_PIN="$(git rev-parse HEAD:sdk)"

git -C sdk fetch origin "refs/tags/${SDK_TAG}:refs/tags/${SDK_TAG}"
SDK_TAG_COMMIT="$(git -C sdk rev-list -n 1 "${SDK_TAG}")"
TAGGED_SDK_VERSION="$(git -C sdk show "${SDK_TAG}:packages/komodo_defi_sdk/pubspec.yaml" | sed -n 's/^version: //p')"

test "${TAGGED_SDK_VERSION}" = "${SDK_VERSION}"
git -C sdk merge-base --is-ancestor "${SDK_TAG_COMMIT}" "${SDK_PIN}"
)
```

The remote tag fetch fails when the tag is missing. The version comparison
fails when the tag names a commit with different package metadata, and the
ancestry check fails when the app's pinned SDK commit does not contain the
tagged release. The tagged commit may be an ancestor rather than the exact pin
when the app includes reviewed post-release SDK fixes.

Any failure blocks the app release. Complete the SDK release and create the
correct upstream package tag first; do not create a placeholder app release or
tag to bypass this check.

## Build for Web

### Standard build

```bash
flutter pub get --enforce-lockfile
flutter build web --csp --no-web-resources-cdn --no-pub
```

### WebAssembly build (recommended)

```bash
flutter pub get --enforce-lockfile
flutter build web --csp --no-web-resources-cdn --no-pub --wasm
```

The release version of the app will be located in `build/web` folder. Specifying the `--release` flag is not necessary, as it is the default behavior.

WebAssembly builds require COEP/COOP headers on the hosting layer (see [WebAssembly hosting headers](#webassembly-hosting-headers)).

## Native builds

Run `flutter build {TARGET}` command with one of the following targets:

- `apk` - builds Android APK (output to `build/app/outputs/flutter-apk` folder)
- `appbundle` - builds Android bundle (output to `build/app/outputs/bundle/release` folder)
- `ios` - builds for iOS (output to `build/ios/iphoneos` folder)
- `macos` - builds for macOS (output to `build/macos/Build/Products/Release` folder). Distribution builds add `--flavor production`, which outputs to `Release-production` and signs for notarization; see [contrib/README.md](../contrib/README.md).
- `linux` - builds for Linux (output to `build/linux/x64/release/bundle` folder)
- `windows` - builds for Windows (output to `build/windows/x64/runner/Release` folder)

Example:

```bash
flutter build apk
```

### GasFree TRON settings

GasFree TRON (sending and receiving TRC-20 tokens without holding TRX) is on by default: the app's defaults are these production values, which CI and `.docker/build.sh` also pass explicitly.

```bash
--dart-define=TRON_GASLESS_ENABLED=true \
--dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
--dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
--dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
```

To build without it, pass `--dart-define=TRON_GASLESS_ENABLED=false` and `--dart-define=TRON_GASLESS_RECEIVE_ENABLED=false`.

To check a finished web build, read its build-policy marker; it must say
`send=enabled;receive=enabled`:

```bash
grep -a -o -h 'gleec-gasfree-build-policy-v1:[a-z=;]*' build/web/main.dart.js | sort -u
```

The marker is only compiled into web builds. Don't check for the GasFree base
URL: it is compiled in whether or not GasFree is on.

## Docker builds

Prerequisite (ensure SDK submodule is initialized to the pinned commit):

```bash
git submodule update --init --recursive
# Recommended once per clone to auto-fetch pinned commits on branch switches
git config fetch.recurseSubmodules on-demand
```

`.docker/build.sh <target> <mode>` builds the `komodo/android-sdk:35` and
`komodo/komodo-wallet` images from `.docker/android-sdk.dockerfile` and
`.docker/komodo-wallet-android.dockerfile`. It then runs
`flutter build <target> --no-pub --<mode>` twice inside the container, writing
to `./build`. The target is a `flutter build` subcommand:

```bash
sh .docker/build.sh web release
sh .docker/build.sh apk release
sh .docker/build.sh appbundle release
```

## WebAssembly hosting headers

For Flutter web `--wasm` builds with multi-threading, set these response headers:

- `Cross-Origin-Embedder-Policy: credentialless` (or `require-corp`)
- `Cross-Origin-Opener-Policy: same-origin`

`roles/nginx/templates/airdex.conf.j2` (the nginx deployment template) sets
them. `firebase.json` does not; read
[WEB_HOSTING_TOPOLOGY.md](WEB_HOSTING_TOPOLOGY.md) before adding COEP to
Firebase Hosting.
