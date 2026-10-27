# Combined LI.FI candidate validation — 27 October 2026

Implementation: wallet `1643c3323f5ebeb9168b244d969a5e6d6df971a1`, SDK
`b5c1d9db854358b84cfb4b22f0fd86d1ba8780d1`. [Handover and remaining gates](KDF_LIFI_DECKER_HANDOVER_2026-10-27.md).
All Flutter/Dart commands use `/Users/charl/fvm/versions/3.41.4/bin`, including
inside the SDK (its own FVM default is not used). Dart is 3.11.1.

## Commands and local results

From the wallet root:

```sh
flutter pub get --enforce-lockfile --offline
flutter test --no-pub test_units/main.dart \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
flutter analyze --no-pub
dart run easy_localization:generate -S ./assets/translations -s en.json -f keys
dart format <changed Dart files only>
git diff --check
python3 -m unittest discover -s tool -p test_kdf_lifi_quote_smoke.py
```

Locked dependency resolution passed without changing the root lockfile. The wallet
suite first ran with `--no-test-assets` after asset generation: **3,800 passed,
4 skipped**. It was then rerun with asset transformation enabled to check the
frozen inputs rather than trust old test caches: **3,800 passed, 4 skipped**,
exit 0 again. New app tests are imported by the aggregator. Python: **2 passed**.
Changed-file format check: 63 app and 4 SDK Dart files, no changes required.
Analysis: **0 errors, 55 warnings, 2,141 infos**, exit 1 due to the existing backlog;
no new diagnostics in the integration or freeze implementation. Localization keys
were regenerated and formatted using the repository generator.

Per SDK package, from `sdk/packages/<name>`:

```sh
KDF_HARNESS='' flutter test --no-pub --reporter expanded
# komodo_defi_rpc_methods, komodo_defi_types, komodo_defi_framework,
# komodo_defi_local_auth, komodo_coin_updates, komodo_defi_sdk
```

First pass used `--no-test-assets` against generated assets; the second pass
includes asset transformation; all six package suites and both harness modes
passed again. Both runs are tracked separately in the local logs.
Package counts: **379; 191 / 3 skipped; 101; 127; 106; 1,192 / 1 skipped**.
From `sdk/packages/komodo_wallet_build_transformer`, `dart test`: **119 passed**.
The six new freeze tests cover commit-addressed content despite CDN configuration,
metadata refs without branch-head reads, corrupt cached files/icons, extra cached
icons, rejected corrupt downloads, and rebuild signaling after correction.

From `sdk/packages/komodo_defi_harness`, each of `hd` and `iguana`:

```sh
KDF_HARNESS='' KDF_HARNESS_WALLET_TYPE=hd flutter test --no-pub --exclude-tags bench
KDF_HARNESS_WALLET_TYPE=hd BENCH_OUT=/tmp/bench-hd.json flutter test --no-pub --tags bench
dart run tool/compare_bench.dart --baseline tool/bench_baseline.json \
  --current /tmp/bench-hd.json --max-regression 0.30
# Repeat with iguana and a separate output file.
```

Replay: **221 passed / 3 skipped each**. Benchmark and 30% regression comparison:
**both passed**. The skipped process tier is not funded execution evidence.

From `sdk/packages/komodo_defi_rpc_methods`:

```sh
CHROME_EXECUTABLE="$PWD/../../tool/flutter_test_chrome.sh" \
FLUTTER_TEST_CHROME_BINARY='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' \
flutter test --no-pub --no-test-assets --platform chrome --wasm \
  --reporter expanded test/src/rpc_methods/routed_swap
```

**107 passed** in a fresh browser profile, covering exact/Max request serialization,
concrete execution, required funding, optional payouts, locked balances and both
gas-estimation error envelopes. This is mocked RPC contract testing, not an EVM swap.

## Clean release builds and provenance

```sh
flutter build bundle --release --no-pub
flutter build web --release --no-pub --csp --no-web-resources-cdn
FLUTTER_XCODE_CODE_SIGNING_ALLOWED=NO \
FLUTTER_XCODE_CODE_SIGNING_REQUIRED=NO \
FLUTTER_XCODE_CODE_SIGN_IDENTITY='' \
FLUTTER_XCODE_CODE_SIGN_STYLE=Manual \
FLUTTER_XCODE_DEVELOPMENT_TEAM='' \
FLUTTER_XCODE_PROVISIONING_PROFILE_SPECIFIER='' \
flutter build macos --release --no-pub
```

**Web and unsigned macOS release builds passed (exit 0).** Each final build used a
clean output directory. All three generated coin configuration files and the exact
444-icon inventory plus the empty tracked `.gitkeep` match their packaged copies
byte for byte in both outputs. The initial web build correctly refused 72 stale
cache icons absent from the pin; they were quarantined outside the checkout.
No verification was disabled. Existing automatic-update builds keep the CDN policy;
frozen builds bypass it. Runtime coin updates remain enabled independently.

[The manifest](KDF_LIFI_CANDIDATE_MANIFEST_2026-10-27.json) includes compiler/host
versions, tracked lockfile hashes, generated SDK-workspace lock hash, seven archive
checksums and cache provenance, generated asset digests, effective public build
settings and local output inventory digests. It identifies the unsigned local
outputs, not future signed release packages. Private release-service configuration
was not loaded for these validation builds. Record intended deployment overrides
and secret version references during packaging without committing secret values.

## Read-only live checks

```sh
python3 tool/kdf_lifi_quote_smoke.py \
  --json docs/KDF_LIFI_QUOTE_REPORT_2026-10-27_FINAL.json
```

**Passed**: Arbitrum ETH → USDC and Base ETH → USDC through the configured proxy,
exact amount, positive provider minimum, one included combined 2% fee, required
gas funding and typed unfunded Max insufficiency. Coin configuration SHA-256 is
`6a1cb3a8c0fc69f2ef2525151238c6433875ce947d8ced78c6411035dc662ea5`, matching
the frozen asset in the manifest. Engine version is `3.1.1-beta_35f0bde`.
The runner creates an unfunded wallet, permits only version/activation/quote/stop,
and deletes its temporary wallet and engine logs. Its allowlist regression rejects
execution, approval, withdrawal and broadcast names before transport.

The [first attempt](KDF_LIFI_QUOTE_REPORT_2026-10-27.json) and
[diagnostic recheck](KDF_LIFI_QUOTE_REPORT_2026-10-27_RECHECK.json) remain failed.
The second run's redacted log identified KDF's password repetition policy. The
runner's generator now excludes triple repeats, including the suffix boundary;
a deterministic test covers rejection and regeneration. The first attempt and
historical 26 October failure had no retained engine detail, so neither is silently
reclassified. No funds, token approvals or swap-execution RPCs were submitted here.

## Independent CI and remaining limitations

CI snapshot appended below belongs to the named published implementation. A later
documentation-only commit may launch additional CI; pending checks are not passes.
The earlier on-ramp assertion and the three upstream KDF failures remain distinct
from the local integration suites. No full local GUI runner was repeated; the
published candidate triggers the normal Chrome/Safari workflow with its existing
public testnet fixtures. Mainnet funded and usability rounds remain human-owned.

Local command logs and quarantined generated outputs are under
`/private/tmp/lifi-release-integration-20261027`. They are not permanent release
artifacts. This committed report and manifest retain commands, results, source
identity and artifact digests; GitHub workflow artifacts supply independent CI
logs. No raw engine wallet/configuration was retained or uploaded.

### CI snapshot at 2026-10-27T07:09:13.507937+00:00

| Workflow | Result at snapshot |
|---|---|
| Wallet: [CharlVS is running UI tests on PR 🚀](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40464113981) | in_progress |
| Wallet: [Building desktop apps 🖥️](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40464114059) | in_progress |
| Wallet: [CharlVS is running unit tests on PR 🚀](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40464113955) | in_progress |
| Wallet: [Building mobile apps 📱](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40464114249) | in_progress |
| Wallet: [CharlVS is scanning dependencies for vulnerabilities 🔒](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40464114448) | success |
| Wallet: [CharlVS is deploying a preview build to Firebase Hosting 🚀](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40464114113) | success |
| Wallet: [CharlVS is validating code guidelines 🚀](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40464114091) | success |
| Wallet: [CharlVS is checking wallet load performance ⏱️](https://github.com/GLEECBTC/gleec-wallet/actions/runs/40464114143) | success |
| SDK: [Deploy Playground to Firebase Hosting on PR](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/actions/runs/40464029776) | success |
| SDK: [Flutter package tests (consolidated)](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/actions/runs/40464029709) | success |

In-progress jobs are outstanding automated checks. Release owners must inspect their
completed outcomes before approving freeze. The historical on-ramp failure is not
claimed fixed by a workflow that is still running.

[Local log digest index](KDF_LIFI_VALIDATION_LOG_INDEX_2026-10-27.json) identifies
the full fresh-run logs and exact SDK commands without uploading raw logs.
