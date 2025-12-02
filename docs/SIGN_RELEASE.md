# Signing builds

## Android

1. Generate keystore file:

    ```bash
    keytool -genkey -v -keystore gleec-wallet.jks -keyalg RSA -keysize 2048 -validity 10000 -alias gleec
    ```

2. Convert keystore to base64:

    ```bash
    base64 -i gleec-wallet.jks -o keystore-base64.txt
    ```

3. Validate

    ```bash
    keytool -list -v -keystore gleec-wallet.jks
    ```

Example secrets:

```yaml
ANDROID_KEYSTORE_BASE64: "/u3+7QAAAAIAAAABAAAAAQAHa29tb2RvAAABjK6LSU8AAAUBMIIE..."
ANDROID_KEY_ALIAS: "komodo"
ANDROID_STORE_PASSWORD: "your-keystore-password"
ANDROID_KEY_PASSWORD: "your-key-password"
```

Documentation:

- [Android Signing Guide](https://developer.android.com/studio/publish/app-signing)

## iOS/macOS

1. Create Apple Developer Account
2. Generate certificates in Apple Developer Portal:
    iOS: App Store and Ad Hoc distribution certificate
    macOS: Mac App Store certificate
3. Export P12:

    ```bash
    # Export from Keychain and convert to base64
    base64 -i certificate.p12 -o cert-base64.txt
    ```

4. Create App Store Connect API Key
5. Validate

    ```bash
    security find-identity -v -p codesigning
    ```

Example secrets:

```yaml
IOS_P12_BASE64: "MIIKsQIBAzCCCnsGCSqGSIb3DQEHAaCCCmwEggpo..."
IOS_P12_PASSWORD: "your-p12-password"
MACOS_P12_BASE64: "MIIKsQIBAzCCCnsGCSqGSIb3DQEHAaCCCmwEggpo..."
MACOS_P12_PASSWORD: "your-p12-password"
APPSTORE_ISSUER_ID: "57246542-96fe-1a63-e053-0824d011072a"
APPSTORE_KEY_ID: "2X9R4HXF34"
APPSTORE_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMG..."
```

Documentation:

- [iOS Code Signing Guide](https://medium.com/@bingkuo/a-beginners-guide-to-code-signing-in-ios-development-d3d5285f0960)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [Provisioning Profiles](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)

## Windows

1. Purchase a code signing certificate from a trusted CA (like DigiCert)
2. Export as PFX with private key
3. Convert to base64:

    ```Powershell
    certutil -encode certificate.pfx cert-base64.txt
    ```

4. Validate

    ```Powershell
    signtool verify /pa your-app.exe
    ```

Example secrets:

```yaml
WINDOWS_PFX_BASE64: "MIIKkgIBAzCCClYGCSqGSIb3DQEHAaCCCkcEggpD..."
WINDOWS_PFX_PASSWORD: "your-pfx-password"
```

Documentation:

- [Windows Code Signing Guide](https://learn.microsoft.com/en-us/windows/win32/appxpkg/how-to-sign-a-package-using-signtool)
- [Microsoft Authenticode](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/authenticode)

## Linux

1. Generate GPG key:

    ```bash
    gpg --full-generate-key
    ```

2. Export private key:

    ```bash
    gpg --export-secret-keys --armor YOUR_KEY_ID | base64 > gpg-key-base64.txt
    ```

3. Validate

    ```bash
    gpg --verify your-package.deb.asc your-package.deb
    ```

Example secrets:

```yaml

```

Documentation:

- [GPG Guide](https://gnupg.org/documentation/guides.html)
- [Debian Package Signing](https://wiki.debian.org/SecureApt)

## Summary of Github Workflow Secrets

### Shared between iOS and macOS

| **Name**               | **Description**                                                                                       |
| ---------------------- | ----------------------------------------------------------------------------------------------------- |
| `APPSTORE_ISSUER_ID`   | The Issuer ID from your Apple Developer account, used to authenticate with App Store APIs.           |
| `APPSTORE_KEY_ID`      | The Key ID associated with your App Store Connect API key.                                           |
| `APPSTORE_PRIVATE_KEY` | The private key (Base64 encoded) for your App Store Connect API key, used for signing releases.      |

### iOS (mobile builds)

| **Name**             | **Description**                                                                                       |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| `IOS_P12_BASE64`     | The iOS distribution certificate encoded in Base64 for signing iOS builds.                            |
| `IOS_P12_PASSWORD`   | The password for the iOS distribution certificate (`.p12` file).                                       |

### macOS (desktop builds)

| **Name**               | **Description**                                                                                       |
| ---------------------- | ----------------------------------------------------------------------------------------------------- |
| `MACOS_P12_BASE64`     | The macOS distribution certificate encoded in Base64 for signing macOS builds.                         |
| `MACOS_P12_PASSWORD`   | The password for the macOS distribution certificate (`.p12` file).                                     |

### Android (mobile builds)

| **Name**                   | **Description**                                                                                     |
| -------------------------- | --------------------------------------------------------------------------------------------------- |
| `ANDROID_KEYSTORE_BASE64`  | The Android Keystore file encoded in Base64 for signing Android applications.                       |
| `ANDROID_KEY_ALIAS`        | The alias name of the key within the Android Keystore.                                             |
| `ANDROID_STORE_PASSWORD`   | The password for the Android Keystore.                                                             |
| `ANDROID_KEY_PASSWORD`     | The password for the specific key within the Android Keystore.                                     |

### Windows (desktop builds)

| **Name**               | **Description**                                                                                       |
| ---------------------- | ----------------------------------------------------------------------------------------------------- |
| `WINDOWS_PFX_BASE64`   | The Windows code signing certificate in PFX format, encoded in Base64.                               |
| `WINDOWS_PFX_PASSWORD` | The password for the Windows PFX certificate (`.pfx` file).                                          |

### Linux (desktop builds)

| **Name**             | **Description**                                                                                       |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| `LINUX_GPG_KEY`      | The GPG private key for signing Linux packages, encoded in Base64.                                   |
| `LINUX_GPG_KEY_ID`   | The ID of the GPG key used to sign Linux packages.                                                  |
