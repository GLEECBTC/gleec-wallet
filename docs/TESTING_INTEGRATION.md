# Integration and GUI testing

This guide covers the wallet integration runner, its configuration and test-wallet
flows. See [Testing](TESTING.md) for the complete suite map and unit, SDK, replay
and performance gates. Run the commands below from the wallet checkout root.

`dart run_integration_tests.dart` wraps `flutter drive`. It starts and stops the browser
driver itself, so no manual `chromedriver` step is needed for Chrome.

## Flags

| Flag | Short | Default | Allowed | Notes |
|---|---|---|---|---|
| `--help` | `-h` | — | — | prints usage, exits 0 |
| `--verbose` | `-v` | false | — | passes `-v` to `flutter drive` |
| `--testToRun` | `-t` | `''` | path under `test_integration/tests/` | **replaces** the whole default list |
| `--browserDimension` | `-b` | `1024,1400` | `H,W` | rewritten to `HxW`. Web only |
| `--displayMode` | `-d` | `no-headless` | `headless`, `no-headless` | local default opens a visible browser. Web only |
| `--device` | `-D` | `web-server` | `web-server`, `chrome`, `linux`, `macos`, `windows`, `ios`, `android` | anything but `web-server` takes the native path |
| `--runMode` | `-m` | `profile` | `release`, `debug`, `profile` | `profile` also emits `--profile-memory=memory_profile.json` |
| `--browser-name` | `-n` | `chrome` | `chrome`, `safari`, `firefox` | `CHROME_EXECUTABLE` pins the Chrome binary |
| `--driver-port` | `-p` | `4444` | — | web only |
| `--pub` | — | false | — | `flutter pub get` before each group |
| `--concurrent` | `-c` | false | — | not recommended with the current build steps |
| `--keep-running` | `-k` | false | — | maps to `--keep-app-running` |
| `--dart-define` | — | none | `KEY=VALUE`, repeatable | forwarded to native and web Flutter builds; commas remain part of the value |

**`-d` is display mode; `-D` is device.** They are not `flutter`'s letters. Getting them
backwards is the classic mistake here.

## What the runner injects — and what it does not

Three defaults, on both the native and web paths, followed by explicitly supplied
`--dart-define` values:

```
--dart-define=testing_mode=true       # lib/shared/constants.dart -> isTestMode
--dart-define=CI=true                 # -> isCiEnvironment
--dart-define=ANALYTICS_DISABLED=true # -> analyticsDisabled
```

GasFree is compiled off unless all required `TRON_GASLESS_*` values are supplied.
`testing_mode` itself changes error handling and log verbosity; it does not supply
authentication, geo-policy or KDF configuration. Without geo-provider credentials,
policy stays unavailable and activation waits. Use the configured provider to test
live restrictions, or explicitly select the supported `GEO_BLOCK=disabled` behavior
for other wallet-flow checks. Record that choice with the result.

The balance/receive diagnostic does not submit a withdrawal:

```sh
dart run_integration_tests.dart \
  -t wallets_tests/test_withdraw_balance.dart -D web-server -d headless -m release \
  --dart-define=GEO_BLOCK=disabled
```

This mode does not validate live geo-service responses. The policy unit and Wasm
regressions separately cover delayed lookup, failure, late restrictions and recovery.

The withdrawal integration is independent of clipboard support:

```sh
dart run_integration_tests.dart \
  -t wallets_tests/test_withdraw.dart -D web-server -d headless -m release \
  --dart-define=GEO_BLOCK=disabled
```

It uses the funded test-wallet fixture and submits 0.01 MARTY. Before sending it
checks the runtime asset is MARTY with `is_testnet=true`, the amount is exactly
0.01, the max-amount option is off, and the recipient matches the entered fixture
address. It verifies the submission receipt and records its transaction hash;
it does not wait for blockchain confirmation. This exercises standard UTXO
withdrawal, not the TRON GasFree rail.

The separate receive diagnostic forwards the actual copy-button request to the
platform delegate and verifies its response and address. It bypasses Flutter's
default test clipboard mock and records success-message visibility separately.

## Suites

| Suite (`-t` path) | In the default run | Logs in via `restoreWalletToTest` |
|---|---|---|
| `wallets_tests/wallets_tests.dart` | yes | yes |
| `wallets_manager_tests/wallets_manager_tests.dart` | yes | **no** — it *is* the auth test; drives import directly |
| `dex_tests/dex_tests.dart` | yes | yes |
| `misc_tests/misc_tests.dart` | yes | yes, after the theme and feedback tests |
| `fiat_onramp_tests/fiat_onramp_tests.dart` | yes | yes |
| `nfts_tests/nfts_tests.dart` | **no** — `-t` only | yes |
| `no_login_tests/no_login_tests.dart` | **no** — `-t` only | mostly no, but see below |
| `suspended_assets_test/suspended_assets_test.dart` | **no** — hardcoded off | n/a |
| `perf_tests/perf_tests.dart` | **no** — `-t` only, by design ([frame timing](TESTING.md#7-frame-timing)) | no |

### Independent on-ramp checks

The default `fiat_onramp_tests/fiat_onramp_tests.dart` target tests **Banxa**
quotes and selection without requiring Ramp. It checks USD 50 → BTC, EUR 50 →
BTC and EUR 50 → LTC, including a positive coin amount/price, matching quoted
currencies/fiat amount and selection of the requested provider. Placeholder,
zero and stale quotes fail. Profile/release modes use production provider APIs;
debug uses their test mode.

Ramp appears as an explicitly skipped, deferred case in that target. The user
accepted its current unavailability for this release on 27 October 2026. When
Ramp authorization is restored, run its independent target:

```bash
dart run_integration_tests.dart \
  -t fiat_onramp_tests/ramp_onramp_tests.dart \
  -d headless -n chrome -m profile --dart-define GEO_BLOCK=disabled
```

The default on-ramp gate is read-only: it does not submit a provider order.
The former checkout-launch check is retained separately for a supervised run:

```bash
dart run_integration_tests.dart \
  -t fiat_onramp_tests/banxa_checkout_tests.dart \
  -d headless -n chrome -m profile --dart-define GEO_BLOCK=disabled
```

That explicit target creates a Banxa order and opens the checkout webview; it
does not enter payment details or complete a purchase. Order creation, checkout
and payment/delivery sign-off are distinct from a passing quote-only gate.
No completed purchase is claimed by either automated target.

### Live KDP browser diagnostic

The explicit `kdf_tests/lifi_proxy_quote_smoke.dart` target checks the frozen
`35f0bde` WASM engine against the live LI.FI proxy. It activates Arbitrum assets
and verifies an exact quote, a positive minimum and the included 2% commission.
Its RPC allowlist permits only version, activation and quoting. It submits no
approval or swap and is not in the default GUI suite.

```bash
dart run_integration_tests.dart \
  -t kdf_tests/lifi_proxy_quote_smoke.dart \
  -d headless -n chrome -m profile \
  --dart-define GEO_BLOCK=disabled \
  --dart-define LIFI_PROXY_URL=https://quicknode.gleec.com/lifi
```

Use the candidate's default commission settings. An intentional engine repin or
commission-policy change requires reviewing this frozen-candidate assertion.
Like the native quote smoke, this is a live connectivity check, not funded
execution or production-capacity evidence.

`no_login_tests` is not entirely login-free: `no_login_taker_form_test.dart` calls
`restoreWalletToTest` and must stay last in its group.

## The test wallet

`test_integration/helpers/restore_wallet.dart` imports wallet `my-wallet` with password
`Y7!m9pQ2rV4#sT6z` in iguana mode. The seed is a randomly chosen **funded WIF key**
from `helpers/get_funded_wif.dart` — RICK/MORTY testnet keys, not secrets, not a BIP39
mnemonic. Because it is not a mnemonic, the helper must confirm the app's custom-seed
dialog. Legal acceptance is tied to the normal Create, final Import, Log in, or hardware
Continue submission beside the linked notice. Updated terms add an inline notice
to those same forms; there is no checkbox or separate acceptance step. Opening a
form or legal document does not record acceptance. Legal state, notice, and form
regressions are included in `test_units/main.dart`.

## Web vs native

The web path (`-D web-server`, the default) serves the app and drives a real browser via
chromedriver, which issues a **fresh browser profile per session** — so storage is clean
every run. The native path (`-D macos|linux|windows|…`) first calls `clearNativeAppsData()`.
Check that the paths in `test_integration/runners/app_data.dart` match the build
being tested before assuming a clean native profile. See the
[known limitations](TESTING.md#9-known-broken-and-not-run) for native build issues.

## Recipes

```bash
dart run_integration_tests.dart -t 'wallets_tests/wallets_tests.dart'
dart run_integration_tests.dart -n safari -m release
dart run_integration_tests.dart -d headless -b '1600,1024' -n chrome -m profile  # = the Linux CI leg
dart run_integration_tests.dart -D macos -m debug
```

`Process.run` buffers all output until the run exits — nothing streams, not even the
build. With `-d no-headless` the visible browser window is your progress signal.
