# Installing Flutter SDK

Gleec Wallet requires a specific Flutter version to build and run. The required version can be seen
on [FLUTTER_VERSION.md](FLUTTER_VERSION.md).

While it should be possible to go a few bugfixes versions over that version without issues,
it's generally intended to use that exact version.

To install the Flutter SDK, you can use the [Flutter extension for VS Code](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter) (recommended), or download and install the Flutter bundle yourself from the [SDK Archive](https://docs.flutter.dev/release/archive), or use the [Flutter Version Manager (FVM)](https://fvm.app/documentation/getting-started/installation). The [official guide](https://docs.flutter.dev/get-started/install/linux/web) goes into further detail.

## Use VS Code to install

The recommended approach is to install the [Flutter extension for VSCode](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter) (or the [Flutter extension for Android Studio/IntelliJ](https://plugins.jetbrains.com/plugin/9212-flutter)) and installing the Flutter SDK via the extension to simplify the process.

## Download and install

The second way is via downloading the desired version from the SDK Archives.
Here are [Windows](https://docs.flutter.dev/release/archive?tab=windows), [Mac](https://docs.flutter.dev/release/archive?tab=macos)
and [Linux](https://docs.flutter.dev/release/archive?tab=linux) download links.
Remember to extract the file into a convenient place, such as `~/flutter`.

Choose the option that is more convenient for you at the time.

Add the flutter binaries subfolder `flutter/bin` to your system PATH. This process differs for each OS:

For macOS:

```bash
nano ~/.zshrc
export PATH="$PATH:$HOME/flutter/bin"
```

For Linux:

```bash
vim ~/.bashrc
export PATH="$PATH:$HOME/flutter/bin"
```

For Windows, follow the instructions below (from [flutter.dev](https://docs.flutter.dev/get-started/install/windows#update-your-path)):

- From the Start search bar, enter `env` and select **Edit environment variables for your account**.
- Under **User variables** check if there is an entry called **Path**:
  - If the entry exists, append the full path to flutter\bin using ; as a separator from existing values.
  - If the entry doesn't exist, create a new user variable named Path with the full path to flutter\bin as its value.

You might need to logout and re-login (or source the shell configuration file, if applicable) to make changes apply.

On macOS and Linux it should also be possible to confirm it's been added to the PATH correctly by running `which flutter`.

## Use Flutter Version Manager (FVM)

Should you need to install and manage multiple versions of the Flutter SDK, it is recommended to use [FVM](https://fvm.app/documentation/getting-started/installation). See [MULTIPLE_FLUTTER_VERSIONS.md](MULTIPLE_FLUTTER_VERSIONS.md) for more details.
