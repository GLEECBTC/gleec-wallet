# TRON GasFree receive build policy

New GasFree custody receive addresses are exposed only when all of these checks
pass:

1. `TRON_GASLESS_ENABLED` was compiled as `true`.
2. `TRON_GASLESS_RECEIVE_ENABLED` was compiled as `true`.
3. The build's provider URL, network, token identity, and pinned service
   provider pass the local allowlist.
4. KDF's typed `gasless::account_status` response is fresh and reports
   `availability: available` for the canonical token, exact provider, and exact
   custody address.
5. The SDK reports the GasFree receive capability as ready.
6. The wallet epoch, foreground state, and canonical primary software-wallet
   derivation still match when the asynchronous check completes and when the
   user invokes QR or copy.

There is no runtime control endpoint. Changing either feature flag, the
provider URL, provider identity, or required network requires a reviewed build
and deployment.

Any failed or unknown check disables new GasFree receives. It does not hide an
existing custody balance, pending transfer, retained Standard address, or
recovery action authorized by its own current checks.

## KDF contract

The GUI performs no CREATE2 derivation, TIP-712 operation, or direct provider
request. `gasfree_address` is opaque KDF output. KDF derives it and hard-fails a
reachable provider/custody mismatch; Flutter binds the response to the current
wallet and validates typed fields, amounts, and freshness.

Only `availability: available` authorizes a new QR or copy action.
`pending_transfer`, `token_unsupported`, and `provider_unreachable` remain
visible with their typed custody state but do not authorize a new deposit.
Provider, custody-address, and token-decimal mismatches are security failures.

Every send still requires a fresh KDF withdrawal preview with
`fallback_to_native: false`; account-status fees and maximums are display
estimates only.

## Release configuration

Production-equivalent builds use:

```sh
TRON_GASLESS_ENABLED=true
TRON_GASLESS_RECEIVE_ENABLED=true
TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron
TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
TRON_GASLESS_REQUIRED_NETWORK=tron
```

The reusable build action forwards the first four values as compile-time Dart
defines and uses the required network as a CI policy check. Receive cannot be
enabled unless send is enabled, and enabled builds require a valid base URL and
provider pin.

The public mainnet identity is version-controlled in preview and release
workflows. It is not a repository variable, so changes require a reviewed
source diff. Local and non-release builds remain disabled unless they supply
the values explicitly.

## Runtime safety and rollback

While the receive surface is foregrounded, the app refreshes typed KDF status
every 30 seconds. Every QR, copy, consolidation, or integration handoff checks
that the observation is no more than one minute old and still matches the
wallet, asset, provider, and custody address.

To disable GasFree receive, compile `TRON_GASLESS_RECEIVE_ENABLED=false` and
deploy a replacement build. Leave provider configuration available so existing
custody balances, pending transfers, and recovery remain visible.
