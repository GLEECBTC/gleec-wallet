# Manual testing and debugging

## Debug login

In order to simplify login during debug session `Debug login` button provided in gui (debug mode only).

Please create `assets/debug_data.json` file with wallet credentials to use it.

File structure example bellow:

```json
{
  "wallet": {
    "name": "wasmtest",
    "password": "debugpassword",
    "seed": "test seed phrase please change with your actual debug seed",
    "activated_coins": ["RICK", "MORTY"],
    "automateLogin": true
  },
  "swaps": {
    "import": []
  }
}
```

## Manual testing

[Manual testing plan](https://docs.google.com/spreadsheets/d/1EiFwI00VJFj5lRm-x-ybRoV8r17EW3GnhzTBR628XjM/edit#gid=0)

## Debugging web version on desktop

## HTTP

```bash
flutter run -d chrome --web-hostname=0.0.0.0 --web-port=7777
```

## HTTPS

### Generate self-signed certificate with openssl

```bash
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem -sha512 -days 3650 -nodes -subj "/C=XX/ST=StateName/L=CityName/O=CompanyName/OU=CompanySectionName/CN=http://localhost.com"
```

### Run flutter with self-signed certificate

```bash
flutter run -d chrome --web-hostname=0.0.0.0 --web-port=7777 --web-tls-cert-key-path=key.pem --web-tls-cert-path=cert.pem
```

Or as a standalone web server for use with any browser:

```bash
flutter run -d web-server --web-hostname=0.0.0.0 --web-port=7777 --web-tls-cert-key-path=key.pem --web-tls-cert-path=cert.pem
```

## Debugging web version on physical mobile devices

Since app behavior in mobile browser on physical device may differ from its behavior in Chrome Desktop mobile emulator, sometimes it is necessary to run local app build on a physical mobile phone.

### Mac + iPhone

1. On your mac:
   1.2. Plug in your iPhone to Mac with cable
   1.3. Go to System Preferences -> Sharing
   1.4. Uncheck 'Internet Sharing' checkbox on the left side, if checked
   1.5. Check 'iPhone USB' checkbox on the right
   1.6. Check 'Internet Sharing' checkbox on the left again
   1.7. At the top of the window you'll see message, similar to 'Computers on your local network can access your computer at: %yourMacName%.local'. You can press 'Edit' button and change `%yourMacName%` with shorter value.
   1.8. Run `flutter run -d web-server --web-hostname 0.0.0.0 --web-port 53875` in project directory. You can use different port if needed.
2. On your iPhone:
   2.1. Open Safari
   2.2. Switch to 'Private' mode (to avoid caching)
   2.3. Enter `%yourMacName%.local:53875` in the address bar (`%yourMacName%.local` is the value from 1.7, port is from 1.8)
   2.4. You should see app running in your mobile browser

### More platforms TBD

## Useful for testing

1. Server for static files on node.js:

   ```js
   const express = require("express");
   const path = require("path");
   var app = express();

   app.use(express.static(path.join(__dirname, "/build/web")));
   app.get("/", (req, res) => {
     res.sendFile(path.join(__dirname, "/build/web/index.html"));
   });

   app.listen(53875);
   ```

2. Change `updateCheckerEndpoint` in `lib/app_config/constants.dart` to use your custom version checker endpoint
3. Decrease time for checking of version, see `init` method in `update_bloc.dart`

### To create a recoverable swap

At the time of writing used branch [gen-recoverable-swap](https://github.com/GLEECBTC/komodo-defi-framework/pull/1428)

1. Setup atomicDex-API, [see](https://github.com/GLEECBTC/komodo-defi-framework/tree/dev#building-from-source)
2. Setup dev environment, [see](https://github.com/GLEECBTC/komodo-defi-framework/blob/dev/docs/DEV_ENVIRONMENT.md#running-native-tests)
3. Run command below

   ```bash
   BOB_PASSPHRASE="seedphrase1" ALICE_PASSPHRASE="seedphrase2" TAKER_FAIL_AT="taker_payment_refund" MAKER_FAIL_AT="taker_payment_spend" cargo test --package mm2_main --lib mm2::lp_swap::lp_swap_tests::gen_recoverable_swap -- --exact --ignored --nocapture
   ```

4. In the end of test you should see in the console JSON-files with swaps data

   ```bash
   Maker swap path <kdf-repo>/mm2src/mm2_main/DB/<maker-pubkey>/SWAPS/MY/<swap-uuid>.json
   Taker swap path <kdf-repo>/mm2src/mm2_main/DB/<taker-pubkey>/SWAPS/MY/<swap-uuid>.json
   ```

5. Copy swap with for your seedphrase to 'assets/debug_data.json', see [Debug Login](#debug-login)
6. Run Gleec Wallet in debug mode and click 'Debug Login' button in the top right corner
7. Imported swaps should appear in history on the DEX page

Explanation for env variables:

1. ALICE_PASSPHRASE uses for taker
2. BOB_PASSPHRASE uses for maker
3. TAKER_FAIL_AT values see [here](https://github.com/GLEECBTC/komodo-defi-framework/pull/1428/files#diff-3b58e25a3c557aa8a502011591e9a7d56441fd147c2ab072e108902a06ef3076R481)
4. MAKER_FAIL_AT values see [here](https://github.com/GLEECBTC/komodo-defi-framework/pull/1428/files#diff-608240539630bec8eb43b211b0b74ec3580b34dda66e339bac21c04b1db6da43R1861)

### iOS Crash Logs

Look for entries starting with or containing "Runner" or "GLEEC"

- On a real device: Go to Settings -> Privacy -> Analytics & Improvements -> Analytics Data
- In Simulator: ~/Library/Logs/DiagnosticReports/

## Visual Studio Code Configuration

### launch.json

Replace `$HOME` with your home directory if there are any issues with the path.

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "GW (debug)",
      "program": "lib/main.dart",
      "request": "launch",
      "type": "dart",
      "args": ["--web-port", "6969"]
    },
    {
      "name": "GW (debug,https)",
      "program": "lib/main.dart",
      "request": "launch",
      "type": "dart",
      "args": [
        "--web-port",
        "6970",
        "--web-tls-cert-path",
        "$HOME/.ssh/debug/server.crt",
        "--web-tls-cert-key-path",
        "$HOME/.ssh/debug/server.key"
      ]
    },
    {
      "name": "GW (debug,https,no-web-security)",
      "program": "lib/main.dart",
      "request": "launch",
      "type": "dart",
      "args": [
        "--web-port",
        "6971",
        "--web-browser-flag",
        "--disable-web-security",
        "--web-tls-cert-path",
        "$HOME/.ssh/debug/server.crt",
        "--web-tls-cert-key-path",
        "$HOME/.ssh/debug/server.key"
      ]
    },
    {
      "name": "GW (profile)",
      "program": "lib/main.dart",
      "request": "launch",
      "type": "dart",
      "flutterMode": "profile",
      "args": ["--web-port", "6972"]
    },
    {
      "name": "GW (profile,https)",
      "program": "lib/main.dart",
      "request": "launch",
      "type": "dart",
      "flutterMode": "profile",
      "args": [
        "--web-port",
        "6973",
        "--web-tls-cert-path",
        "$HOME/.ssh/debug/server.crt",
        "--web-tls-cert-key-path",
        "$HOME/.ssh/debug/server.key"
      ]
    },
    {
      "name": "GW (release)",
      "program": "lib/main.dart",
      "request": "launch",
      "type": "dart",
      "flutterMode": "release",
      "args": ["--web-port", "8080"]
    },
    {
      "name": "GW (release,https)",
      "program": "lib/main.dart",
      "request": "launch",
      "type": "dart",
      "flutterMode": "release",
      "args": [
        "--web-port",
        "8081",
        "--web-tls-cert-path",
        "$HOME/.ssh/debug/server.crt",
        "--web-tls-cert-key-path",
        "$HOME/.ssh/debug/server.key"
      ]
    }
  ]
}
```

### settings.json

```json
{
  "dart.flutterSdkPath": ".fvm/versions/stable",
  "[dart]": {
    "editor.defaultFormatter": "Dart-Code.dart-code",
    "editor.formatOnSave": true
  }
}
```
