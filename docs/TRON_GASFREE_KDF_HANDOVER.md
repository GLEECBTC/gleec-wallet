# TRON GasFree integration handover

## Authoritative inputs

- KDF repository:
  `GLEECBTC/komodo-defi-framework`
- KDF source:
  `bd413dcfea73c9de2e85903323946a378b180fa7`
- KDF documentation path:
  `komodo-docs-mdx`
- Documentation revision:
  `d175558a6c5d33a4f7ce4843227f0b54cc3dbc9b`
- Published builds:
  `https://devbuilds.gleec.com/feat-tron-gasfree/`

Rust request/response definitions at the pinned KDF source take precedence if
an MDX example differs from runtime serialization.

## Artifact promotion

The SDK's canonical manifest is
`packages/komodo_defi_framework/app_build/build_config.json`. Run from the SDK
root:

```sh
dart run packages/komodo_wallet_cli/bin/update_api_config.dart \
  --branch feat/tron-gasfree \
  --commit bd413dcfea73c9de2e85903323946a378b180fa7 \
  --source mirror \
  --mirror-url https://devbuilds.gleec.com \
  --platform all \
  --config packages/komodo_defi_framework/app_build/build_config.json \
  --output-dir packages/komodo_defi_framework/app_build/temp_downloads \
  --strict \
  --verbose
```

The updater computes archive hashes itself. The aggregate mirror
`SHA256SUMS` file is stale and is not an authority. Synchronize the reference
YAML after the JSON update and run the build transformer to extract all
platform outputs and regenerate provenance markers.

Expected archives:

| Platform | Archive | SHA-256 |
| --- | --- | --- |
| Web | `kdf_bd413dc-wasm.zip` | `9242cbba06eda6e82fc057897781cea2adf85f67f0cf5710f4feaf0a5e6d844c` |
| iOS | `kdf_bd413dc-ios-aarch64.zip` | `0cc494a8ff7b3f926cebc6956cda61c9928c7366624d592c71e29f080a3255bd` |
| macOS | `kdf_bd413dc-mac-universal.zip` | `f1d8a52c7c34d9721761733586f7262177b5362f911d8a220b2550e1f9844bbe` |
| Android armv7 | `kdf_bd413dc-android-armv7.zip` | `929d57312908544c9e6ae94d660d8ae14c21fb84547821ba0e0aba26c4daf29a` |
| Android arm64 | `kdf_bd413dc-android-aarch64.zip` | `9953572e03956a751dcef365df76b6b84a3675800323220d50409dbd8175f037` |
| Linux | `kdf_bd413dc-linux-x86-64.zip` | `ec5e2c801520e00ed1fd18c82c0edc0ade30716c6a4fb8aab453f265ce6afb33` |
| Windows | `kdf_bd413dc-win-x86-64.zip` | `04062cf1a271888eab9a757fa1a19e41038beea15b19484a21e5731d4dfc05e0` |

## Layer ownership

- `komodo_defi_rpc_methods` owns exact wire serialization and endpoint error
  parsing.
- `komodo_defi_types` owns public activation, fee, authorization, result, and
  durable-transfer types.
- `komodo_defi_sdk` owns capability validation, streaming, encrypted recovery,
  wallet-session races, and the Standard-versus-GasFree result rail.
- Wallet BLoCs own product gating and localized state mapping. They do not
  parse raw RPC JSON or provider strings.

## Mainnet deployment and release-master hand-over

The approved public mainnet deployment identity is:

| Setting | Value |
| --- | --- |
| `TRON_GASLESS_BASE_URL` | `https://quicknode.gleec.com/gasfree/tron` |
| `TRON_GASLESS_SERVICE_PROVIDER` | `TLntW9Z59LYY5KEi9cmwk3PKjQga828ird` |

These values are public but security-sensitive. They are version-controlled in
the preview, RC, mobile, and desktop workflows instead of GitHub repository
variables, so provider changes require a reviewed commit and cannot be caused
by a missing or out-of-band variable update. Secrets do not belong in either
value.

The release master performs final builds manually on the CI server. For an
approved mainnet GasFree build, append all of the following compile-time
defines to the existing target-specific `flutter build` command:

```sh
--dart-define=TRON_GASLESS_ENABLED=true \
--dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
--dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
--dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
```

Before building, validate the exact release environment:

```sh
TRON_GASLESS_ENABLED=true \
TRON_GASLESS_RECEIVE_ENABLED=true \
TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird \
TRON_GASLESS_REQUIRED_NETWORK=tron \
bash .github/scripts/validate_tron_gasless_config.sh
```

`String.fromEnvironment` values are compiled into the application, so setting
these variables only in the shell without forwarding the matching
`--dart-define` arguments is insufficient.

GasFree send and receive are controlled exclusively by the compiled flags and
pinned production identity. Changing their availability or provider binding
requires a reviewed rebuild and deployment. Runtime KDF capability, typed
account status, custody binding, and freshness checks remain fail-closed.

The mainnet proxy and upstream provider-list endpoints return `401` to unsigned
`curl` requests by design. The pinned provider address above is the provider
captured from the authenticated Gleec GasFree account and used by the amended
KDF provider-list fixture. KDF revalidates the pin against
`/api/v1/config/provider/all` on the first GasFree operation.

## Removed compatibility mechanisms

- `gasless::configure` and restart fallback invocation;
- `provider_available`, `reason_code`, and explicit/legacy status branching;
- V0/V1/bound receive-evidence generations;
- request-ID, fingerprint, expected-authorization, and bound-response echoes;
- regex-derived relay lifecycle states and raw error-copy display;
- local maximum/fee authority and native-fallback notices;
- direct provider/custody balance access and TronGrid finality checks.

The local encrypted pre-submit reservation, unknown-outcome lockout, provider
pin, action-time QR/copy check, Standard recovery, wallet/session guards, and
custody history refresh are permanent safeguards, not compatibility
workarounds.

## Validation

Repository policy treats the existing unit/integration suites as known failing;
they are not release sign-off. Add and maintain focused fixtures, then use
changed-file formatting, root `flutter analyze`, independent analysis of each
changed SDK package, artifact provenance inspection, and a thorough combined
diff review.

Perform Nile/manual canary validation before promotion. Do not execute a real
mainnet transfer without separate authorization.
