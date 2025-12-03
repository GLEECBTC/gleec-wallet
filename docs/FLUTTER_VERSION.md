# Flutter Version Management

## Supported Flutter Version

This project supports Flutter `3.35.3`. We aim to keep the project up-to-date with the most recent stable Flutter versions.

## Recommended Approach: Multiple Flutter Versions

For the best development experience, we recommend using a Flutter version manager rather than pinning your global Flutter installation. This allows for better isolation when working with multiple projects that may require different Flutter versions.

See our guide on [Multiple Flutter Versions](MULTIPLE_FLUTTER_VERSIONS.md) for detailed instructions on setting up a version management solution.

## Alternative: Pinning Flutter Version (Not Recommended)

While it's possible to pin your global Flutter installation to a specific version, **this approach is not recommended** due to:

- Lack of isolation between projects
- Known issues with `flutter pub get` when using Flutter 3.35.3
- Difficulty switching between versions for different projects

If you still choose to use this method, you can run:

```bash
cd ~/flutter
git checkout 3.35.3
flutter doctor
```

However, we strongly encourage using the multiple Flutter versions approach instead for a better development experience.
