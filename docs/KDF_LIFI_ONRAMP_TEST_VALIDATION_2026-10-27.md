# Independent on-ramp validation — 27 October 2026

The default on-ramp integration target now exercises **Banxa quotes and
selection independently of Ramp**. It checks USD 50 → BTC, EUR 50 → BTC and
EUR 50 → LTC, including nonzero quotes, matching amount/currencies and selected
provider/method. It rejects zero placeholders and stale quotes. Failures retain
their explanation in the integration driver's report data.

Ramp is explicitly skipped with a deferred label, following the user's release
disposition. Its separate target is available for the next update. The previous
checkout-launch check is retained in a separate Banxa target: it creates an order
and therefore is excluded from the default read-only gate. No order, payment or
funded swap was submitted in this validation. A quote pass does not establish
checkout, KYC or delivery.

## Results

| Check | Result |
|---|---|
| Offline dependency resolution with enforced lockfile | Passed |
| Changed-file formatting | Passed; four on-ramp Dart files and the retained KDP browser diagnostic |
| Full analysis | 0 errors, 55 warnings, 2,150 infos; existing diagnostics outside all five changed Dart files |
| Changed on-ramp files analysis | No issues found |
| Full wallet unit/widget aggregator, four GasFree defines | 3,800 passed, four skipped, zero failures |
| Chrome profile integration | Banxa passed all three pair/selection checks. Ramp explicitly deferred/skipped. Chrome 156.0.8078.48, matching-build ChromeDriver 156.0.8078.47. |
| Safari release integration | Web compilation succeeded. Test execution blocked before session creation: Safari requires **Allow remote automation**. No Banxa assertion ran; no Safari pass is claimed. |
| Separate live KDP checks | Native Arbitrum/Base and Chrome WASM Arbitrum signed quotes passed; the browser diagnostic's scoped analysis found no issues. See the RC audit. |

The first Safari attempt failed the runner's driver-start check. Starting a
dedicated driver directly returned `ready: true`; the second attempt exposed
`SessionNotCreatedException` with the explicit Remote Automation requirement.
Safari settings were not changed. Enable automation on a designated test host
and rerun this target, or run the updated hosted Safari job after publication.

These are local results recorded before publication. The user subsequently
clarified that branch publication and PR updates, including automated preview
comments, are allowed; the restriction applies to contacting colleagues. The prior
failed hosted on-ramp results remain historical evidence. Hosted CI for the new
test revision must be checked separately.

## Reproduction

Use Flutter 3.41.4 / Dart 3.11.1. Commands below ran from the candidate root.
Local log paths and SHA-256 values are retained in
`.lifi/evidence/KDF_LIFI_ONRAMP_TEST_VALIDATION_2026-10-27.json`, excluded from Git.
The commands, results and limitations remain recorded here.

```bash
flutter pub get --enforce-lockfile --offline
dart format test_integration/tests/fiat_onramp_tests/{form_tests,fiat_onramp_tests,ramp_onramp_tests,banxa_checkout_tests}.dart \
  test_integration/tests/kdf_tests/lifi_proxy_quote_smoke.dart
flutter analyze --no-pub --no-fatal-warnings --no-fatal-infos
dart analyze test_integration/tests/fiat_onramp_tests

flutter test --no-pub test_units/main.dart --reporter expanded \
  --dart-define=TRON_GASLESS_ENABLED=true \
  --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird

dart run_integration_tests.dart \
  -t fiat_onramp_tests/fiat_onramp_tests.dart \
  -d headless -b 1600,1024 -n chrome -m profile \
  --dart-define GEO_BLOCK=disabled \
  --dart-define TRON_GASLESS_ENABLED=true \
  --dart-define TRON_GASLESS_RECEIVE_ENABLED=true \
  --dart-define TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron \
  --dart-define TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
```

The Safari retry used the same defines with `-n safari -m release -p 4445`,
after starting `/usr/bin/safaridriver -p 4445 --diagnose` directly. Browser driver
processes were dedicated to this task. ChromeDriver was downloaded from the
official Chrome for Testing manifest because the installed driver was version
151 while Chrome was 156; no system driver was replaced.

The default CI runner already includes `fiat_onramp_tests/fiat_onramp_tests.dart`,
so Banxa remains in its existing gate. The two explicit integration targets are
not unit tests and do not belong in `test_units/main.dart`. No app runtime, SDK,
lockfile or KDF pin changed. See [the updated handover](KDF_LIFI_DECKER_HANDOVER_2026-10-27.md)
for remaining release decisions and [the KDP audit](KDF_LIFI_PROXY_RC_AUDIT_2026-10-27.md)
for the separate backend-RC investigation.
