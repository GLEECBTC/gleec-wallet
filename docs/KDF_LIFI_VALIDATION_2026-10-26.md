# KDF LI.FI validation — 2026-10-26

This delivery continues [SDK #407](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/407)
and [wallet #3557](https://github.com/GLEECBTC/gleec-wallet/pull/3557), targeting
specs `7c388ea7b91cb7c657435d416bc03e5349b46162` and KDF
`35f0bde438eec2cb0471b19642b9d9c4602fa17d`.

[SDK validation and artifact provenance](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/blob/9e3cc0af627cfb11567c3180a64aeb2efa564c5c/docs/LIFI_INTEGRATION_VALIDATION.md)
records all seven verified archive digests, Linux recovery, exact SDK suite
commands/results and read-only proxy quotes. The coins pin remains
`2b0aefb78b184091ab086c66e513d8b03f5d5a01`.

SDK commit `9e3cc0af627cfb11567c3180a64aeb2efa564c5c` was published to
PR #407 before the wallet submodule was repinned to it. Both PRs remain open.

## Wallet checks

All commands use Flutter 3.41.4, prefetched locked dependencies and the PR
worktree. New app policy tests are imported in `test_units/main.dart`.

```sh
flutter test --no-pub --no-test-assets test_units/main.dart \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
flutter analyze --no-pub
flutter build web --release --no-pub --csp --no-web-resources-cdn
xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner \
  -configuration Release -derivedDataPath build/macos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

The full app suite covers Max refresh races, manual edits returning to exact,
source/order choices, rate-limit pauses, rejected Max and immutable review
snapshots. Funding, included fees, provider-only/missing measured receipts,
partial/refund outcomes, exports and gas/approval evidence are also exercised.
The exact provider minimum is displayed and passed unchanged to `init`.

Builds temporarily set only `coins.update_commit_on_build=false`, restoring the
original manifest afterward, so asset generation cannot move the coins pin.
Both native and web generated assets use KDF `35f0bde`. A normal signed macOS
build was attempted and failed because no provisioning profile for
`com.GleecDEX.wallet` is installed. The unsigned release build checks compilation
and linking; it is not a signed distribution artifact.

Localization keys were regenerated with
`dart run easy_localization:generate -S ./assets/translations -s en.json -f keys`.
Changed Dart files, including generated output, were formatted with the Dart SDK bundled with Flutter 3.41.4.
Final analysis: zero errors, 55 existing warnings and 2141 informational
diagnostics; it exits nonzero because of these existing diagnostics. None occurs
in changed wallet files. SDK analysis and package counts are in the linked SDK
report. Final app gate: **3679 passed, 4 skipped**, with all four prescribed GasFree
defines. Final web release and unsigned macOS release builds both completed with
exit 0. `git diff --check` passed. These are local results; newly triggered PR CI
is separate from this evidence.

## Remaining release gates

- Run the human-operated funded round on the PR preview using
  [the runbook](SWAP_LIVE_TEST_BRIEF.md). No funded execution was attempted here.
- The upstream KDF unit failures remain:
  `validate_dex_fee_invalid_sender_erc`, `firo_lelantus_tx_details`, and
  `test_block_header_utxo_loop`. Upstream CI must not be described as passing.
- Release owner handles signing, production proxy capacity/monitoring and
  release approvals. Upstream merges and production deployment are outside
  this task. This delivery remains Phase 1 EVM swaps.
