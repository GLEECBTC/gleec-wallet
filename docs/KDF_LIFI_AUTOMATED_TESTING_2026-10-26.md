# Additional automated LI.FI testing — 2026-10-26

This follow-up tested the delivered wallet `202ef1f0b` and SDK `9e3cc0af`.
The only follow-up code is a reusable quote smoke runner; application and SDK
runtime code is unchanged.

## Repeatable live quote checks

```sh
python3 tool/kdf_lifi_quote_smoke.py --json /tmp/lifi-quote-report.json
```

Requires Python 3.9+, generated native KDF/coin assets and network access. Optional
`--kdf` and `--coins` select those assets. It starts a new unfunded wallet, verifies
the engine version against the manifest, activates Arbitrum/Base ETH and USDC,
and checks exact quotes plus unfunded Max. Assertions cover the concrete amount,
positive unchanged provider minimum, required balance versus gas estimate, one
included combined 2% fee, and typed `InsufficientBalance` naming the native coin.

The runner uses the configured proxy and confirmed integrator policy. Its RPC
allowlist rejects init, approval, withdrawal and broadcast calls. It reads no
existing wallet/seed, deletes its temporary wallet and logs, and exits nonzero on
failure. Four negative checks confirmed fund-committing method names are rejected.
The JSON report contains public quote values and the coin-config digest, without
seeds, credentials or wallet addresses. The Base transform here mirrors SDK policy;
SDK tests separately verify bundled/cached/refreshed normalization.

**Result:** both pairs passed twice, including the final command without a debug
wrapper. [Final machine-readable report](KDF_LIFI_AUTOMATED_QUOTE_REPORT_2026-10-26.json).
The first attempt exited during engine startup; the initial report did not retain
its exit detail before temporary cleanup. It did not recur in two subsequent
fresh-wallet runs. The runner now records the failed phase and startup exception;
it does not silently retry or mark that initial attempt passed.

## Browser / WebAssembly RPC suite

From `sdk/packages/komodo_defi_rpc_methods`, with Flutter 3.41.4:

```sh
CHROME_EXECUTABLE="$PWD/../../tool/flutter_test_chrome.sh" \
FLUTTER_TEST_CHROME_BINARY='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
flutter test --no-pub --platform chrome --wasm --reporter expanded \
  test/src/rpc_methods/routed_swap
```

**107 passed**, including exact/Max requests, concrete init, locked balances,
funding totals, optional measured/provider payouts and gas-estimation envelopes.
This uses a fresh browser test profile and mocked RPCs, not funded execution.

## CI on the delivered commits

| Surface | Result / evidence |
|---|---|
| SDK all-package tests, including WebAssembly transport | [Passed](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/actions/runs/40354801183) |
| Wallet unit suite | [Passed](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113122) |
| HD/iguana replay and performance comparison | [Passed](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113090) |
| Wallet web preview build | [Passed](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113206) |
| Windows / Linux builds | [Passed](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113089) |
| Android build | [Passed](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113066) |
| macOS / iOS build jobs | Cancelled with no runner name or executed steps. Logs unavailable. These are not passing CI builds; the earlier local unsigned macOS build passed. |
| Chrome and Safari UI workflows | [Failed only in fiat_onramp_tests](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40355113130); see below. |

Both browser jobs logged success for `wallets_tests`, `wallets_manager_tests`,
`dex_tests` and `misc_tests`. The Chrome driver log identifies
`Run Fiat On-Ramp tests:` failing because `fiat-payment-method-ramp-0` matched zero
widgets. Its diagnostic points to rejected provider credentials as a possible
cause; these logs alone do not establish that cause. No provider keys were read
or changed, and this separate on-ramp failure was not hidden or skipped.

These CI results belong to the delivered commits named above, not to later
commits that add this runner/report. No automated run here committed funds.
The human-operated funded round and the three upstream KDF failures remain as
recorded in [the integration validation](KDF_LIFI_VALIDATION_2026-10-26.md).
