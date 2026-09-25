# Flutter Version Management

## Supported Flutter Version

This project supports Flutter `3.41.4`. We aim to keep the project up-to-date with the most recent stable Flutter versions.

The version is pinned in **`.fvmrc`** at the repo root, so
[FVM](https://fvm.app) picks it up automatically - `fvm flutter <cmd>` always
uses the right one. CI installs the same version, and a check in
`.github/actions/flutter-deps` fails the build if `.fvmrc`, any workflow pin, or
this document ever disagree.

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
- Known issues with `flutter pub get` when using Flutter 3.41.4
- Difficulty switching between versions for different projects

If you still choose to use this method, you can run:

```bash
cd ~/flutter
git checkout 3.41.4
flutter doctor
```

However, we strongly encourage using the multiple Flutter versions approach instead for a better development experience.
