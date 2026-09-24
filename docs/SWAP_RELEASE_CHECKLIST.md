# Unified swap — release checklist

What has to be true, in order, before the unified swap (wallet #3507) ships. Each step that changes something outside a developer's machine needs an explicit go from the release owner. Open decisions are listed first, with who owns them.

## Open decisions

| Decision | Owner | State |
|---|---|---|
| **Aggregator access in production.** Today every user quotes the public API without a key: 75 quotes every two hours per network address, and the wallet's budget is designed around that. The API team will release a server-side proxy that holds a partner key. | API team | The public API is the interim choice (decided 2026-09-24). When the proxy exists, KDF's `lifi_api` must point at it. The SDK's `KdfStartupConfig` has no field for that yet, and adding one is the wallet-side change. A partner key's limit is shared by every user, so it must be sized for peak use. KDF's 5-second routed status polling also counts against it. |
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
   - Take it out of draft and refresh both PR descriptions.
   - Merge only **after** the 0.9.7 release candidate (#3525) has merged. Otherwise the swap ships in 0.9.7.

## Gates

| Gate | How | Last result |
|---|---|---|
| App unit suite | `flutter test test_units/main.dart` with the four `TRON_GASLESS_*` defines (see AGENTS.md) | 1,324 passed, 4 skipped (2026-09-24) |
| SDK suites | Each package's `flutter test`: `komodo_defi_harness`, `komodo_defi_rpc_methods`, `komodo_defi_sdk` | Harness 220 (4 skipped), rpc 246; sdk to run with the repin |
| KDF `routed_swap` tests | KDF team's CI on #29. The `Test` workflow runs only when dispatched by hand. | 36 `routed_swap` + 18 LI.FI client tests passed locally at `4872ef2` |
| Live engine check, no funds | `routed_swap_live_capture_test.dart` holds the recorded responses | Native and WebAssembly agree; 9 of the day's 75 keyless quotes used |
| Quote budget | `swap_quote_budget_test.dart` | Idle form 42 → 10 requests per 10 minutes, then none; typing 2 → 1; native Max 3 → 1; start 1 → 0 |
| UI tests | `ui-tests-on-pr` | Red only at `fiat_onramp_tests`, an external Ramp key issue |
| Live swaps with funds | [`SWAP_LIVE_TEST_BRIEF.md`](SWAP_LIVE_TEST_BRIEF.md) — the release owner runs them with small amounts | Not run |
| Moderated usability session | [`SWAP_USABILITY_SESSION.md`](SWAP_USABILITY_SESSION.md) — five users | Not run |
