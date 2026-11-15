# Flutter Version Management

## Supported Flutter Version

The app and SDK support Flutter `3.50.0` with Dart `3.14.0`, released on
November 11, 2026. See the [official release announcement](https://flutter.dev/blog/whats-new-in-flutter-3-50).

The version is pinned in **`.fvmrc`** at the repo root, so
[FVM](https://fvm.app) picks it up automatically - `fvm flutter <cmd>` always
uses the right one. CI installs the same version, and a check in
`.github/actions/flutter-deps` fails the build if `.fvmrc`, any workflow pin, or
this document ever disagree. The SDK also pins the same version in `sdk/.fvmrc`.

```bash
fvm install
fvm use 3.50.0 --skip-pub-get
fvm flutter --version
fvm flutter pub get --enforce-lockfile
```

Use `fvm flutter` and `fvm dart` for builds, tests, analysis and generators.
For scripts that spawn Flutter, prepend the project SDK to the current shell's
path: `export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"`.

See [the upgrade record](FLUTTER_3_50_UPGRADE.md) for migrations and validation.

> **Regenerate `pubspec.lock` with the pinned version, never with whatever
> `flutter` is on your PATH.** A newer Flutter ships a newer bundled Dart and
> resolves some packages higher than the pinned version can accept. The lockfile
> then looks fine locally and fails `flutter pub get --enforce-lockfile` in CI,
> which every job runs before it does any work - so the whole pipeline goes red
> for a reason that has nothing to do with the change. Use
> `fvm flutter pub get`.

## Recommended Approach: Multiple Flutter Versions

For the best development experience, we recommend using a Flutter version manager rather than pinning your global Flutter installation. This allows for better isolation when working with multiple projects that may require different Flutter versions.

See our guide on [Multiple Flutter Versions](MULTIPLE_FLUTTER_VERSIONS.md) for detailed instructions on setting up a version management solution.

## Alternative: Pinning Flutter Version (Not Recommended)

While it's possible to pin your global Flutter installation to a specific version, **this approach is not recommended** due to:

- Lack of isolation between projects
- Difficulty switching between versions for different projects

If you still choose to use this method, you can run:

```bash
cd ~/flutter
git checkout 3.50.0
flutter doctor
```

However, we strongly encourage using the multiple Flutter versions approach instead for a better development experience.
