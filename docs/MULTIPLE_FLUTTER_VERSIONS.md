# Managing Multiple Flutter Versions

Use the project pin **Flutter `3.50.0` / Dart `3.14.0`** for both Gleec Wallet
and its SDK. Existing installations can remain available for other projects;
there is no need to change the global default.

## FVM CLI

Install [FVM](https://fvm.app/documentation/getting-started/installation) for
your host, then run from this repository:

```bash
fvm install
fvm use 3.50.0 --skip-pub-get
fvm flutter --version
fvm flutter pub get --enforce-lockfile
```

Repeat in `sdk/` when developing the SDK independently. Its `.fvmrc` pins the
same release. Run `fvm flutter test`, `fvm flutter analyze` and `fvm dart run`
so a different global Flutter installation cannot silently change the compiler
or lockfile.

When a script invokes Flutter directly, prepend the project SDK to `PATH` for
that terminal session:

```bash
# macOS / Linux, from the app root
export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH"
```

```powershell
# Windows PowerShell, from the app root
$env:Path = "$PWD/.fvm/flutter_sdk/bin;$env:Path"
```

## Sidekick desktop

[Flutter Sidekick](https://github.com/leoafarias/sidekick) manages the same FVM
SDK cache. Install Flutter `3.50.0`, add the app worktree and SDK as projects,
and select that release for each project. Verify with `fvm flutter --version`
inside each directory. Keep the committed `.fvmrc` files on the exact release;
a moving `stable` alias can unexpectedly change dependency resolution.

## Editors

For VS Code, select the project SDK directory in `.vscode/settings.json`:

```json
{
  "dart.flutterSdkPath": ".fvm/flutter_sdk"
}
```

For Android Studio/IntelliJ, set the Flutter SDK path to the worktree's
`.fvm/flutter_sdk` directory. Restart the Dart analysis server after switching
versions. Generated FVM cache links and machine-specific paths stay untracked.

See [FLUTTER_VERSION.md](FLUTTER_VERSION.md) for lockfile rules and
[BUILD_RUN_APP.md](BUILD_RUN_APP.md) for platform prerequisites.
