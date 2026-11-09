# Solana integration development and acceptance

Solana support is developed alongside the upstream fixes. The integration recognizes native SOL and SPL assets, uses the existing SDK coordinator and wallet flows, and keeps unverified capabilities behind explicit build gates. The production engine source commit and catalog assets remain unchanged; the approved Linux/macOS native-library archive update is recorded in [local validation](SOLANA_LOCAL_VALIDATION.md). See [SOLANA_KDF_DEPENDENCIES.md](SOLANA_KDF_DEPENDENCIES.md) for the engine dependencies and combined-candidate release requirement.

## Contract and boundaries

- `experimental::enable_solana_with_assets` and `experimental::enable_solana_token` use the v2 envelope. Nodes serialize as `{url}`. Trusted token overrides include the complete `SOLANATOKEN` protocol with platform, mint, program and decimals.
- Iguana and mnemonic-derived HD wallets each expose one owner address. `enable_hd` preserves the engine's distinct derivation; Solana requests never add HD account/discovery, withdrawal-address, or signing-address selectors.
- SOL balances/history are the platform stream source. Balance events are arrays; history events are individual transaction objects with a `coin` discriminator. Polling, reconnect and cached-history behavior stay in the existing managers. V2 history omits an HD account target. Base58 addresses and signatures remain case-sensitive.
- SOL uses nine decimal places; token precision comes from trusted metadata. Withdrawal uses normal `withdraw`, a review, a rebuilt signed transaction, and `send_raw_transaction`. The confirmation coordinator compares all review-relevant values before immediate broadcast. Ambiguous outcomes remain pending/uncertain and must not cause automatic resubmission.
- `SolanaFeeInfo` carries `fee_amount`, `rent_amount` and `total_amount`. Its currency resolves through the SOL platform because KDF omits `coin`; devnet token fees remain `TESTSOL`. Rent is an account-creation deposit, separate from token amount and network fee. Indexed history may omit memo/status and report no rent breakdown; do not infer those from a withdrawal preview.
- `orderbook`/`best_orders` retain their existing method names with the v2 envelope. `buy`/`sell`/`setprice` use the existing execution path; KDF chooses the Solana v1 swap protocol. Required funding must include every `trade_preimage.total_fees.required_balance` currency, including SOL on the receiving side. Present conservative requirements without inventing an exact refundable-rent split. KDF confirmation value `1` means finalized for Solana.
- Mainnet and mixed-network new trades are blocked. Curated devnet atomic swaps require explicit opt-in. Solana market maker automation remains disabled until the engine can enforce funding and policy for each generated order. Restrictions on starting trades do not remove cancellation or recovery. Shielded offers and authoritative own-order IDs remain usable for self-trade prevention. Solana routed swaps, external/hardware wallets, multiple HD addresses and arbitrary mint-only discovery are outside the current engine contract.

Primary references: [KDF Solana integration](https://github.com/GLEECBTC/kdf-internal/pull/35), [KDF API documentation changes](https://github.com/GLEECBTC/komodo-docs-mdx/pull/608) at `df0b99642b7f9a2864b8e4cdb83b843c9be0c5f7`, and the immutable KDF commit linked in the dependency record. The reviewed [specs PR 2](https://github.com/GLEECBTC/gleec-specs/pull/2) at `7c388ea7b91cb7c657435d416bc03e5349b46162` has no Solana execution specification; its routed contract covers EVM. Source-shaped replay fixtures verify wallet contracts, not real chain execution.

## Review units

The integration is reviewed in three separate pull requests. The SDK Solana PR
is stacked on the independently reviewed authentication SDK branch, which owns
the shared final-dispatch guard and transport hooks. Solana callers use that
prerequisite; the Solana review diff excludes the authentication overhaul.
The wallet PR preserves its existing authentication protections and pins the
Solana SDK commit. All extraction and validation use isolated checkouts, leaving
the original mixed workspace intact.

| Review unit | Main implementation surfaces | Validation |
|---|---|---|
| Coins repository ([PR #2103](https://github.com/GLEECBTC/coins/pull/2103)) | Initial four registry entries; `solana/`, Solana explorers, `utils/solana_registry.py`, scanner/generator integration and immutable fixtures. Swap fixtures additionally reuse MARTY. | 40 scanner/generator tests; standalone read-only node checks. |
| Vendored SDK ([PR #444](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/444)) | SOL/SPL types and typed RPCs; activation coordinator; platform stream routing; history persistence; withdrawal refresh/journal; authenticated signing/export; catalog capabilities and isolated storage. Primary new tests are `komodo_defi_sdk/test/solana/`, `test/withdrawals/solana_*`, RPC/type protocol tests and harness `test/solana_replay_test.dart`. | Affected package suites, harness replay and browser stream/catalog checks below. |
| Wallet (this repository) | `lib/app_config/solana_build_config.dart`; SDK/bootstrap wiring; shared trading policy and funding discovery; existing withdrawal/history/key-export presentation; localized messages; candidate/smoke tools. | `test_units/main.dart`, including Solana build, trading and atomic-lifecycle tests plus existing withdrawal/history suites. |

Review catalog and SDK contracts first, then the wallet's capability wiring and
confirmation paths. Release the SDK submodule commit only after its own review;
the wallet change must reference that reviewed commit. Catalog publication and
the combined seven-platform engine repin remain separate release work.

## Candidate isolation

Devnet uses `TESTSOL` and `TESTUSDC-TESTSOL`. These names avoid the `SOL`/`USDC`
price prefixes and fit KDF's ticker/platform statistics convention. The earlier
unreleased names `SOL-DEV` and `USDC-SOL-DEV` are retired; they remain denial-only
aliases for trade starts, both with and without restored catalog metadata.
Cancellation and recovery remain available.

Regenerate the manifest/profile for the renamed snapshot and use fresh isolated
preview storage and a dedicated browser origin. History rows and pending-send
intents include the literal ticker; renaming does not migrate or clear them.
Preserve old evidence and reconcile any old uncertain signature before a funded
retry under the new names. The recorded native smoke uses fresh unfunded wallets,
so this change requires no production-wallet migration.

Candidate catalogs are prepared in the separate coins worktree/branch and identified by both the source base commit and the exact snapshot SHA256. A base commit alone does not identify uncommitted candidate entries. Generate/review the registry's Solana fixtures before making a profile; the fixture manifest identifies wallet-only and explicitly opt-in devnet swap variants separately.

The reviewed devnet swap fixture contains `TESTSOL`, `TESTUSDC-TESTSOL` and the existing `MARTY` UTXO testnet configuration. Its `swap_coins_config.json` SHA256 is `3b116790d8667afc89e69d09852efd64bf0703c68e36e16ed21d978c33349932`; raw `swap_coins.json` is `59b7020ae032af8a421922bfc56a05b0c1fb709990f2519402c850b4e65cc465`. Existing MARTY endpoint configurations are preserved; their runtime availability is a separate funded-round prerequisite. Use that snapshot and a separately generated manifest/profile for atomic acceptance. Do not reuse the wallet-only catalog digest with a swap snapshot.

`tool/solana_candidate.py` writes an exclusive, immutable-input manifest and optional Flutter defines JSON. It records the binary SHA256, full engine commit, catalog SHA256 and catalog base commit. It never changes build configuration, production assets, or remote repositories.

```sh
mkdir -p .solana
# Place a reviewed candidate binary and catalog snapshot in this ignored folder.
python3 tool/solana_candidate.py \
  --kdf .solana/kdf-candidate \
  --coins .solana/coins_config.json \
  --engine-commit FULL_40_CHARACTER_COMBINED_KDF_COMMIT \
  --coins-base-commit FULL_40_CHARACTER_COINS_BASE_COMMIT \
  --output .solana/candidate-manifest.json \
  --defines-output .solana/preview-defines.json \
  --preview-origin http://localhost:18471
```

The example commit placeholders must be replaced; short hashes are refused. Existing output files are never overwritten. `SOLANA_ENABLED` is true in the generated candidate profile. SPL Max and Token-2022 remain false pending their engine fixes and acceptance evidence. Devnet atomic trading defaults to false; explicitly enable it only with the reviewed devnet swap snapshot for development acceptance rounds. Release enablement still requires native/browser swap and recovery evidence. The profile also pins `SOLANA_KDF_COMMIT`, `SOLANA_COINS_COMMIT`, `SOLANA_CATALOG_SHA256`, and the non-default `KDF_COINS_STORAGE_NAMESPACE=solana-preview-<snapshot-prefix>`.

For the interactive preview, use a dedicated checkout/worktree and copy the exact candidate catalog only into that checkout's standard bundled catalog location. The app does not offer an alternative catalog-path define. Candidate WASM/mobile artifacts must likewise exist only in the isolated preview checkout/build output; do not edit the production manifest to get a preview running. Pass `--dart-define-from-file=.solana/preview-defines.json` when running that checkout.

The SDK candidate configuration uses **`assetsAutoUpdate:false`**, which reaches `enableAutoUpdate:false`, and a non-default catalog storage namespace. This change also makes the update manager honor `runtime_updates_enabled:false`; the preview keeps the explicit disablement as well. The compile-time namespace prefixes catalog, settings and custom-token database names, including on web where Hive ignores filesystem subdirectories. Fixture catalogs can be injected with `assetsDataFactory` and `assetsRuntimeUpdateConfig`.

Use a **dedicated browser origin** and disposable browser profile. In the browser, `SOLANA_PREVIEW_ORIGIN` must match the actual scheme, host and port; the app enforces it before engine/storage initialization. Changing only the catalog namespace does not isolate browser authentication at a shared origin, or native interactive wallet/keychain storage. Native process tests below use fresh temporary wallet storage and do not access an interactive user's wallet. Do not assume the candidate catalog namespace alone makes a native interactive run safe to reuse production app data.

The app checks the engine version tag before enabling Solana. The actual legacy `version` wire response is `{result: "3.1.0-beta_b1ff8f0", datetime: "..."}`. Development workflows use a seven-character Git tag; the RPC does not return a separate full commit. The smoke therefore binds the exact binary digest to a full-commit manifest before checking the version suffix. A short version string alone cannot establish full-commit provenance.

## Native unfunded smoke

```sh
KDF_BINARY="$PWD/.solana/kdf-candidate" \
python3 tool/solana_smoke.py \
  --coins .solana/coins_config.json \
  --manifest .solana/candidate-manifest.json \
  --json .solana/unfunded-smoke-report.json
```

Python 3.10+ and a compatible native KDF are required. `KDF_BINARY` is the existing native override; `--kdf` may override it explicitly. `SOLANA_DEVNET_RPC_URL` can select an HTTPS provider. The runner proves the provider's devnet genesis before activation, includes only reviewed `TESTSOL`/classic `TESTUSDC-TESTSOL` entries, and forces wallet-only mode.

The runner generates a fresh disposable BIP39 mnemonic, uses separate temporary wallets for HD and Iguana, checks their distinct derived owners without reporting addresses, and deletes wallet files/logs on success or failure. It reads no existing wallet or seed environment variable. RPC dispatch permits only version, activation, balance, history, address validation, disable and stop. Signing, key export, withdrawal, broadcast, order placement and swap recovery are refused before transport. The report omits provider URLs, credentials, seeds, addresses and raw engine errors.

This smoke verifies zero-balance platform/token activation, shared SOL/SPL owner, v2 targetless history, owner address validation, and token deactivation followed by later activation. It does not establish funded history/backfill, withdrawal correctness, or swap recovery.

## Validation record

Use the exact commands in [TESTING.md](TESTING.md), including all four GasFree defines for `test_units/main.dart`. Every new wallet test must be imported into that entry point; harness package tests run through their own package suite. The pinned Flutter toolchain for this workspace is `/Users/charl/fvm/versions/3.41.4/bin/flutter`.

Validation is repeated on the extracted PR branches, not inferred from the
previous mixed workspace. The exact branch results are recorded in
[SOLANA_LOCAL_VALIDATION.md](SOLANA_LOCAL_VALIDATION.md). This separates deterministic
contract tests, native read-only engine checks and remaining funded acceptance.

The following remain **runtime acceptance gates**, regardless of passing fixtures:

1. On one combined candidate, native and browser SOL/classic SPL transfers: ninth decimal SOL, fractional SPL, Max after its fix, insufficient SOL with sufficient tokens, wallet and token-account recipients, recipient creation/rent, wrong mint, UTF-8 memo boundaries, changed/expired review, uncertain broadcast and duplicate prevention.
2. Funded history: incoming ATA, outgoing and fee-only rows, v0 transactions, paging, pending/finalized reconciliation, reconnect and late-token backfill. Cache replay alone does not satisfy this.
3. Explicit devnet atomic rounds: SOL↔UTXO and classic SPL↔UTXO in both roles, Shielded own orders, receiving-side SOL requirements, maker/taker refunds and restart with locked funds, on native and browser. Mainnet and mixed-network rejection must remain covered. Follow [SWAP_LIVE_TEST_BRIEF.md](SWAP_LIVE_TEST_BRIEF.md) for review and submission; a person commits funds.
4. Token-2022 remains fixtures only until the dependency record is closed. Mainnet atomic and routed trading remain unavailable until their separate upstream requirements are met.

Uncertain withdrawal reservations survive restart/logout and retain the signature without persisting signed bytes. Identical intents remain blocked until authoritative reconciliation; there is deliberately no blind clear-and-retry action. Funded acceptance must verify signature reconciliation before removing an unresolved reservation.

Do not upload temporary wallet directories or engine logs as CI artifacts. Public digest manifests and redacted JSON evidence can be retained separately from those workspaces.
