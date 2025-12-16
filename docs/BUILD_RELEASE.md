# Build Release version of the App

## Environment setup

Before building the app, make sure you have all the necessary tools installed. Follow the instructions in the [Environment Setup](./PROJECT_SETUP.md) document. Alternatively, you can use the Docker image as described here: (TODO!).

### Firebase Analytics Setup

Optionally, you can enable Firebase Analytics for the app. To do so, follow the instructions in the [Firebase Analytics Setup](./FIREBASE_SETUP.md) document.

## Security Considerations

⚠️ **IMPORTANT**: For all production builds, be sure to follow the security practices outlined in the [Build Security Advisory](./BUILD_SECURITY_ADVISORY.md). Always use `--enforce-lockfile` and `--no-pub` flags when building for production.

## Build for Web

```bash
flutter pub get --enforce-lockfile
flutter build web --csp --no-web-resources-cdn --no-pub
```

The release version of the app will be located in `build/web` folder. Specifying the `--release` flag is not necessary, as it is the default behavior.

## Native builds

Run `flutter build {TARGET}` command with one of the following targets:

- `apk` - builds Android APK (output to `build/app/outputs/flutter-apk` folder)
- `appbundle` - builds Android bundle (output to `build/app/outputs/bundle/release` folder)
- `ios` - builds for iOS (output to `build/ios/iphoneos` folder)
- `macos` - builds for macOS (output to `build/macos/Build/Products/Release` folder)
- `linux` - builds for Linux (output to `build/linux/x64/release/bundle` folder)
- `windows` - builds for Windows (output to `build/windows/runner/Release` folder)

Example:

```bash
flutter build apk
```

## Docker builds

Prerequisite (ensure SDK submodule is initialized to the pinned commit):

```bash
git submodule update --init --recursive
# Recommended once per clone to auto-fetch pinned commits on branch switches
git config fetch.recurseSubmodules on-demand
```

### Build for web

```bash
sh .docker/build.sh web release
```

Alternatively, you can run the docker build commands directly:

```bash
# Build the supporting images
docker build -f .docker/kdf-android.dockerfile . -t komodo/kdf-android --build-arg KDF_BRANCH=main
docker build -f .docker/android-sdk.dockerfile . -t komodo/android-sdk:34
docker build -f .docker/gleec-wallet-android.dockerfile . -t gleec/gleec-wallet
# Build the app
mkdir -p build
docker run --rm -v ./build:/app/build gleec/gleec-wallet:latest bash -c "flutter pub get --enforce-lockfile && flutter build web --no-pub --release"
```

### Build for Android

```bash
sh .docker/build.sh android release
```

Alternatively, you can run the docker build commands directly:

```bash
# Build the supporting images
docker build -f .docker/kdf-android.dockerfile . -t komodo/kdf-android --build-arg KDF_BRANCH=main
docker build -f .docker/android-sdk.dockerfile . -t komodo/android-sdk:34
docker build -f .docker/gleec-wallet-android.dockerfile . -t gleec/gleec-wallet
# Build the app
mkdir -p build
docker run --rm -v ./build:/app/build gleec/gleec-wallet:latest bash -c "flutter pub get --enforce-lockfile && flutter build apk --no-pub --release"
```
