# Firebase setup

The repository commits placeholder client configuration so a normal checkout
does not connect to a production Firebase project. Firebase Analytics is
registered as a provider, but initialization and collection are disabled when
the selected Dart options still contain placeholders. Linux also disables the
Firebase provider because Firebase Analytics is unsupported there.

Production configuration is supplied separately for the intended build. A
Firebase Hosting deployment target does not choose the Firebase project compiled
into the app: `.firebaserc` controls Hosting, while the client configuration below
controls Firebase initialization.

## Configure a local build

1. Install the [Firebase CLI](https://firebase.google.com/docs/cli) and the
   [FlutterFire CLI](https://firebase.google.com/docs/flutter/setup):

   ```bash
   dart pub global activate flutterfire_cli
   firebase login
   ```

2. Create or select the Firebase project intended for this build. Register an
   app for each selected platform; a web registration alone does not configure
   the Apple or Android applications.
3. From the wallet repository root, run `flutterfire configure`. Select that
   project and the platforms to build. Use the configuration belonging to those
   registered apps, rather than editing an old app's identifiers to resemble a
   different registration.
4. Review all generated changes, including `firebase.json`, the Dart options,
   native configuration files, and any Xcode project changes. Keep the existing
   Hosting settings and keep `firebase.json` valid JSON without comments.

The client configuration files used by the current local production patch are:

- `lib/firebase_options.dart`
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`
- The `flutter` platform mappings in `firebase.json`

FlutterFire may also write `ios/firebase_app_id_file.json` and
`macos/firebase_app_id_file.json` for tooling. Review those if regenerated;
they are not a replacement for the app's runtime Firebase options.

## Apple bundle IDs and Firebase App IDs

Both Xcode targets currently build with the case-sensitive bundle ID
`com.GleecDEX.wallet`. For each configured Apple target, verify that:

- The Firebase app is actually registered with that bundle ID in the selected
  Firebase project.
- `BUNDLE_ID` in its plist and `iosBundleId` in its Dart `FirebaseOptions` match
  the Xcode bundle ID.
- `GOOGLE_APP_ID` in its plist, `appId` in its Dart options, and its FlutterFire
  mappings in `firebase.json` identify the same registered Firebase app.

The Apple bundle ID and Firebase App ID are different identifiers. Changing a
bundle ID string in downloaded configuration does not create or select a
matching app in the Firebase console. Use the values supplied by the matching
registration. The console's encoded App ID is another representation of that
identifier; these runtime configuration files use the ordinary App ID.

The committed Apple plists contain placeholders and are deliberately absent
from the Xcode Resources build phases. Keep placeholder plists out of native
resource bundles: Firebase can process them before Dart starts. The wallet
initializes configured Firebase explicitly from its Dart options.

## Keep build configuration local

Firebase client configuration identifies a project; it is
[public configuration](https://firebase.google.com/docs/projects/learn-more#config-files-objects).
Keeping production values separate here prevents development and preview builds
from silently targeting production resources.

Do not use `git update-index --assume-unchanged` to manage this separation.
That flag does not untrack a file and can hide configuration changes from review.
If it was set using the previous instructions, clear it for the tracked files:

```bash
git update-index --no-assume-unchanged -- \
  android/app/google-services.json \
  ios/firebase_app_id_file.json \
  ios/Runner/GoogleService-Info.plist \
  macos/firebase_app_id_file.json \
  macos/Runner/GoogleService-Info.plist \
  lib/firebase_options.dart \
  firebase.json
```

Keep a production configuration patch outside the repository or in a local
ignored location. Check that it matches the checkout before applying it:

```bash
git apply --check /path/to/firebase-config.patch
git apply /path/to/firebase-config.patch
```

Stage shared changes by explicit path and review `git diff --cached --name-only`
before committing. Leave the production patch and its applied client values
out of shared commits. Current release workflows do not inject that production
Firebase configuration automatically; a configured release build still needs
the matching files supplied before building.

## Analytics and Hosting checks

To disable collection across analytics providers for a build, pass
`--dart-define=ANALYTICS_DISABLED=true`. The separate
`--dart-define=CI=true` flag also disables collection. These flags do not fix
incorrect native Firebase configuration or make placeholder resource bundles
safe.

Validate the shared Hosting file with a standard JSON parser:

```bash
python3 -m json.tool firebase.json > /dev/null
```

See [Web hosting topology](WEB_HOSTING_TOPOLOGY.md) for project selection,
header/cache behavior, and deployment verification; [Analytics](ANALYTICS.md)
and [Matomo setup](MATOMO_SETUP.md) cover the analytics providers.
