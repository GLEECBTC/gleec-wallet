# Unified swap — release checklist

What has to be true, in order, before the unified swap (wallet #3507) ships. Each step that changes something outside a developer's machine needs an explicit go from the release owner. Open decisions are listed first, with who owns them.

## Open decisions

| Decision | Owner | State |
|---|---|---|
| **Aggregator access in production.** Today every user quotes the public API without a key: 75 quotes every two hours per network address, and the wallet's budget is designed around that. The API team will release a server-side proxy that holds a partner key. | API team | The public API is the interim choice (decided 2026-09-24). When the proxy exists, build with `--dart-define=LIFI_API_URL=<proxy URL>`, and the SDK hands it to KDF as `lifi_api` ([BUILD_RUN_APP.md](BUILD_RUN_APP.md#lifi_api_url)). Unset, the public API is used as before. The key stays on the proxy: the wallet has no setting for it. A partner key's limit covers every user at once, so it must be sized for peak use. KDF's 5-second routed status polling also counts against it: 12 requests a minute for each cross-network swap in flight. |
| **Integrator fees.** | Business | Not in this release. The contract makes them KDF configuration (contract l.385), and KDF sends none today. |
| **Routed-swap contract, gleec-specs#2.** | CharlVS (GUI review), shamardy (author) | The four changes requested on 2026-09-03 are fixed at `0b209b2`. The GUI review that said "fix the envelope and this is a merge from my side" still stands as *changes requested*. A draft approving re-review and a draft Max section are kept outside the repos until the owner decides to post them. |
| **KDF gaps the wallet works around.** | KDF team | Listed in [`SWAP_DEFERRED_FEATURES.md`](SWAP_DEFERRED_FEATURES.md#kdf-behaviour-the-wallet-works-around). None blocks release; KDF changes are out of scope for this one. |

## Merge path

Do these in order. Each needs a go.

1. **KDF #29 merges into kdf-internal `dev`.** It is the KDF team's to merge. Record the merge commit.
2. **Repin the SDK's KDF** from `feat/lifi-integration@4872ef2` to that merge commit. In `packages/komodo_defi_framework/app_build/build_config.json`:
   - set `api.branch` to `dev` and `api.api_commit_hash` to the merge commit;
   - replace the seven `valid_zip_sha256_checksums`;
   - leave `coins.*` untouched (the build rewrites `bundled_coins_repo_commit` on every run; restore it before staging).

   First, check that devbuilds has an artefact for every platform: web, iOS, macOS, Android arm64 and armv7, Linux and Windows.
3. **SDK #389:** out of draft, reviewed, then squash-merged into SDK `dev`. The `protected-main-dev` ruleset needs one approval and every thread resolved. CodeQL never reports, so the merge needs the owner's bypass.
4. **Repin the wallet's `sdk` submodule** to the squash commit, not to #389's branch head.
   - Before moving, prove `git -C sdk diff <squash> <pre-squash head>` is empty.
   - `pubspec.lock` changes only if an SDK package version changed.
   - Regenerate it with Flutter 3.41.4, and check the diff is only those versions.
5. **Wallet #3507:**
   - Check the `# Unreleased` changelog entry against what shipped.
   - It has been marked ready for review since 2026-09-24. Refresh both PR descriptions.
   - Merge only **after** the 0.9.7 release candidate (#3525) has merged. Otherwise the swap ships in 0.9.7.

## Gates

| Gate | How | Last result |
|---|---|---|
| App unit suite | `flutter test test_units/main.dart` with the four `TRON_GASLESS_*` defines (see AGENTS.md) | 3,027 passed, 4 skipped (2026-09-30, with hardware wallets kept out of the swap form, funds at other HD addresses named and `MyAddressError` read as a fault a retry may clear, on #389 at `536e3640`) |
| SDK suites | Each package's `flutter test`; #389's "Flutter tests (all packages)" check runs them all | #389 at `3c3f18f1` (SDK dev's market-data fixes, SDK#392 and SDK#393), run locally (2026-09-29): sdk 1,133 (1 skipped), local_auth 124, harness 224 (4 skipped), framework 98, rpc 343, cex_market_data 361 (6 skipped), and the other 10 packages green. CI has run the framework's 6 web-transport tests in WebAssembly since `e00fa467`, where they pass. CI is green at `536e3640` (2026-09-30). With the order-book RPC fixes and the `best_orders` parser at `536e3640`, run locally (2026-09-30): sdk 1,139 (1 skipped), rpc 361, harness 224 (4 skipped), local_auth 124, framework 98. A first sdk run failed only in the teardown of `history_cache_cipher_upgrade_test.dart`, a flake from SDK#385 |
| KDF `routed_swap` tests | KDF team's CI on #29. The `Test` workflow runs only when dispatched by hand. | 36 `routed_swap` + 18 LI.FI client tests passed locally at `4872ef2` |
| Live engine check, no funds | `routed_swap_live_capture_test.dart` holds the recorded responses | Native and WebAssembly agree; 9 of the day's 75 keyless quotes used. Order-book RPCs (2026-09-30, native, signed out, peer-to-peer on): the v2 forms of `min_trading_vol`, `max_taker_vol` and `orderbook_depth` get `NoSuchMethod`, the legacy forms reach KDF, and `orderbook_depth` answers every pair, zeros included. The web build then showed USDT → AVN with no offers before an amount, and DOGE → AVN's offer range, "Use {max}" and its price |
| Quote budget | `swap_quote_budget_test.dart` | Idle form 42 → 10 requests per 10 minutes, then none; typing 2 → 1; native Max 3 → 1; start 1 → 0 |
| Accessibility and layout | `swap_accessibility_test.dart`; `swap_widgets_test.dart` runs the same checks on review, outcomes and Activity | Every new and changed state at 375, 390, 768, 1024 and 1440 px, light and dark, and at 200% text, measured in Manrope: no overflow, no text cut short or split mid-word, 48 dp targets, every control labelled and pressable by a screen reader. Passing (2026-09-30, adding the no-offers states, their shortcuts, the offer range and the pickers' "No offers" section, then the hardware-wallet notice and the line on funds at other addresses) |
| Test coverage | `flutter test --coverage` over the app suite and the SDK packages; new files count whole, existing files only for the lines this branch changed | App (2026-09-30): 7,443 of 7,449 lines in the 79 new files (the other 6 are 4 private event `props` and `SwapResumeUnconfirmedException.toString`) and 159 of 161 changed lines in 20 existing files (the other 2 log a refused `LIFI_API_URL`, a define the suite runs without). The order-book offers work alone: all 414 lines of its 7 new files and all 211 lines it changes elsewhere; in the SDK, all 64 lines of the order-book RPC fixes and all 20 of the `best_orders` parser. SDK (2026-09-30, #389 at `536e3640`): 1,596 of 1,597 changed routed-swap lines, in the RPCs and the manager (the other one writes a provider error's request ID in `toJson`); 1,728 of 1,739 of all the lines #389 changes outside its test harness (the other 11 register the manager at start-up, decode the native FFI transport's responses, write that request ID, or belong to a gas-free fix #389 carries) |
| UI tests | `ui-tests-on-pr` | Red only at `fiat_onramp_tests`, an external Ramp key issue |
| Live swaps with funds | [`SWAP_LIVE_TEST_BRIEF.md`](SWAP_LIVE_TEST_BRIEF.md) — the release owner runs them with small amounts | Not run |
| Moderated usability session | [`SWAP_USABILITY_SESSION.md`](SWAP_USABILITY_SESSION.md) — five users | Not run |
