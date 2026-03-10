# Managing Multiple Flutter Versions

For the best development experience with Komodo DeFi SDK, we recommend using a Flutter version manager to easily switch between different Flutter versions. This document outlines two recommended approaches:

1. **Flutter Sidekick** - A user-friendly GUI application (recommended for beginners)
2. **FVM (Flutter Version Manager)** - A command-line tool (recommended for advanced users)

## Before You Begin: Remove Existing Flutter Installations

Before installing a version manager, you should remove any existing Flutter installations to avoid conflicts:

### macOS

```bash
# If installed via git
rm -rf ~/flutter

# If installed via Homebrew
brew uninstall flutter

# Remove from PATH in ~/.zshrc or ~/.bash_profile
# Find and remove any lines containing flutter/bin
```

### Windows

```powershell
# If installed manually, delete the Flutter folder
# Remove from PATH in Environment Variables
# Start → Edit environment variables for your account → Path → Remove Flutter entry

# If installed via winget
winget uninstall flutter
```

### Linux

```bash
# If installed via git
rm -rf ~/flutter

# If installed via package manager
sudo apt remove flutter  # for Ubuntu/Debian
sudo pacman -R flutter   # for Arch

# Remove from PATH in ~/.bashrc
# Find and remove any lines containing flutter/bin
```

## Option 1: Flutter Sidekick (Recommended for Beginners)

[Flutter Sidekick](https://github.com/leoafarias/sidekick) is a GUI application for managing Flutter versions across Windows, macOS, and Linux.

### Installation Steps

1. Download and install Flutter Sidekick from the [GitHub releases page](https://github.com/leoafarias/sidekick/releases)

2. Launch Flutter Sidekick

3. Click on "Versions" in the sidebar and download Flutter version `3.41.3`

4. Set this version as the global default by clicking the "Set as Global" button

5. Add Flutter to your PATH:

   - Click on "Settings" in the sidebar
   - Find the path to the FVM installation directory (typically `~/.fvm/default/bin` on macOS/Linux or `%LOCALAPPDATA%\fvm\default\bin` on Windows)
   - Add this path to your system's PATH environment variable

6. Restart your terminal/IDE for the changes to take effect

7. Verify the installation:

   ```bash
   flutter --version
   ```

## Option 2: FVM Command Line

[FVM](https://fvm.app) is a command-line tool for managing Flutter versions. While most developers will be well-served by Flutter Sidekick's graphical interface, the command-line version might be preferable in specific scenarios:

- If you need to integrate Flutter version management into CI/CD pipelines or scripts
- When working in environments without a graphical interface (e.g., remote servers)
- If you prefer terminal-based workflows and want to avoid graphical applications
- For automation in team environments where consistent versions need to be enforced programmatically

### macOS and Linux

1. Install FVM using the installation script:

   ```bash
   curl -fsSL https://fvm.app/install.sh | bash
   ```

2. Install and use Flutter 3.41.3:

   ```bash
   fvm install 3.41.3
   fvm global 3.41.3
   ```

3. Add FVM's default Flutter version to your PATH by adding the following to your `~/.bashrc`, `~/.zshrc`, or equivalent:

   ```bash
   export PATH="$PATH:$HOME/.fvm/default/bin"
   ```

4. Reload your shell configuration:

   ```bash
   source ~/.bashrc  # or ~/.zshrc
   ```

5. Verify the installation:

   ```bash
   flutter --version
   ```

### Windows

1. Install Chocolatey (if not already installed):

   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
   ```

2. Install FVM:

   ```powershell
   choco install fvm
   ```

3. Install and use Flutter 3.41.3:

   ```powershell
   fvm install 3.41.3
   fvm global 3.41.3
   ```

4. Add FVM's Flutter version to your PATH:

   - Open "Edit environment variables for your account"
   - Edit the Path variable
   - Add `%LOCALAPPDATA%\fvm\default\bin`

5. Restart your terminal/PowerShell and verify the installation:

   ```powershell
   flutter --version
   ```

## Project-Specific Flutter Version

To use a specific Flutter version for a project:

1. Navigate to your project directory
2. Run:

   ```bash
   fvm use 3.41.3
   ```

This will create a `.fvmrc` file in your project, which specifies the Flutter version to use for this project.

## Using with VS Code

For optimal integration with VS Code:

1. Install the [Flutter FVM](https://marketplace.visualstudio.com/items?itemName=leoafarias.fvm) extension to automatically use the project-specific Flutter version.

2. If you're using a project-specific Flutter version, you need to specify the Flutter SDK path in your VS Code settings:

   - Open the project in VS Code
   - Create or edit the `.vscode/settings.json` file in your project root and add:

     ```json
     {
       "dart.flutterSdkPath": ".fvm/flutter_sdk"
       // Or if you're using a global FVM version:
       // "dart.flutterSdkPath": "${userHome}/.fvm/default/bin/flutter"
     }
     ```

3. Restart VS Code after making these changes.

This ensures VS Code uses the correct Flutter SDK version for your project, including for features like code completion, diagnostics, and debugging.
