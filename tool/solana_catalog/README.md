# Solana preview catalogs

[Coins PR #2103](https://github.com/GLEECBTC/coins/pull/2103) adds native SOL and classic USDC on mainnet and devnet. All four Solana source
registry entries remain `wallet_only: true`. Token-2022 is represented by protocol
metadata validation but has no public catalog entry while KDF transfer/rent fixes
are pending. Mainnet uses `SOL` and `USDC-SOL`; devnet uses `TESTSOL` and
`TESTUSDC-TESTSOL`. Devnet pricing prefixes are separate from mainnet, and catalog
tickers contain at most one hyphen, following the KDF maintainer's requirement. The generator preserves
Solana tickers exactly, including the `-TESTSOL` platform suffix.

Devnet SOL and USDC are test assets with no financial value. Their catalog
entries leave price-provider IDs empty. Devnet swaps can still quote a rate
between test assets. [Solana devnet guide](https://solana.com/docs/tokens/quickstart)
· [Circle testnet USDC](https://developers.circle.com/stablecoins/usdc-contract-addresses#testnet)

The Solana node source files in `solana/` keep `cluster` and `genesis_hash` scanner
metadata separate from `rpc_nodes`. Generated KDF activation nodes contain only
`url`. These public endpoints are development defaults, not a production provider
selection. Production still needs retained transaction history and browser CORS
validation.

The expected genesis identities are published by Solana Labs:
https://beta.docs.solanalabs.com/clusters/available (Devnet and Mainnet Beta).
The scanner requires matching `getGenesisHash`, `getHealth == "ok"`, and a valid
finalized `getSlot`. Redirects are refused so a configured HTTPS endpoint cannot
downgrade the scan to plain HTTP. Failed identity checks cannot inherit a previous successful
connection timestamp. A normal catalog build includes only verified recent nodes.
SPL tokens inherit their explicit platform's verified nodes. RPC source URLs must
use canonical lowercase `https://`, a valid port, and no userinfo, fragments,
whitespace, control characters or backslashes, so scanners and native/browser
outputs agree on the same endpoint.

## Isolated generated fixtures

The committed files in [fixtures](fixtures/) were generated from coins commit
[`b4da6112`](https://github.com/GLEECBTC/coins/commit/b4da611235da401df3f202e1f4846d1711c081a6).
Their bytes and manifest hashes carry over from the original coins preview.

From the wallet root, install the pinned Python dependencies from the selected
coins checkout's `utils/requirements.txt`, then build into a temporary directory.

```sh
solana_preview_dir=$(mktemp -d)
python3 -B tool/solana_catalog/generate_solana_candidate.py \
  --coins-repo ../coins-solana-integration --output "$solana_preview_dir"
SOLANA_COINS_REPO=../coins-solana-integration \
  python3 -B -m unittest discover -s tool/solana_catalog -v
```

Use the pinned coins commit to check byte-for-byte reproduction. For a fresh
preview, select a reviewed coins revision and record its full commit and the
new snapshot's hash in [the wallet preview profile](../../docs/SOLANA_INTEGRATION.md#candidate-isolation).

Offline generation supplies simulated scan observations to the same
`CoinConfig.generate()` path as the full catalog. It writes the preview files
to `--output` (the `fixtures/` directory by default). The manifest records
whether the node checks were live.
Use `--verify-nodes` to require live Solana identity/health checks before generating.
The manifest records Solana and UTXO verification separately; reusing the UTXO
snapshot does not claim fresh node validation.

`coins.json` and `coins_config.json` contain all four wallet-only entries.
`swap_coins.json` and `swap_coins_config.json` contain the two Solana devnet entries
with explicit `wallet_only: false`, plus the existing `MARTY` UTXO testnet for
SOL/SPL ↔ UTXO swap testing. MARTY is copied from the reviewed generated registry
config after checking its raw protocol/network metadata and every Electrum endpoint
against `electrums/MARTY`. Both existing SSL and WSS nodes are required so native
and browser fixtures retain a UTXO counterasset. The generator limits the swap
fixture to testnet entries. The manifest hashes all four catalogs.

Consumers must use isolated preview storage, explicit `enableAutoUpdate: false`,
and supported-engine capability gates. Setting `runtime_updates_enabled: false`
alone is insufficient in the current Flutter SDK. Do not overlay this candidate
onto an existing real wallet's cached catalog. Follow the
[wallet preview instructions](../../docs/SOLANA_INTEGRATION.md#candidate-isolation)
to set the build gates.

## Generator integration

Full regeneration continues through `utils/generate_app_configs.py`; the regular
scanner now includes Solana independently from EVM and Tron. Solana HTTP polling
nodes also survive the browser/WSS output filter. Raw SPL protocol data (platform,
mint, program and decimals) is preserved, with explicit parent metadata and
cluster-specific explorer templates. The generator does not infer parentage from
ticker suffixes.

## Validation recorded

The preview tests verify the committed snapshot bytes and hashes, curated MARTY
metadata, SSL/WSS node preservation, rejection of unreviewed or disabled nodes,
and testnet-only swap scope. The coins repository's `utils/tests` suite covers
registry validation, node scanning and normal catalog generation.

A separate read-only probe on 2026-11-08 passed both public development endpoints:
mainnet finalized slot `467016646`, devnet finalized slot `520111989`, with health
and the expected genesis identities. These probes do not establish browser CORS,
retained history, transfer construction or swap execution. The offline-generated
snapshot manifest remains `nodes_verified_during_generation: false`.
