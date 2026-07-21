# Gnosis Pay KDF local patch

## Local-only provenance

- Reviewed source: [GLEECBTC/kdf-internal PR #6](https://github.com/GLEECBTC/kdf-internal/pull/6)
- Exact base SHA: `5be59af67ebe1b45b7e9a00c03104b402092a262`
- Existing KDF checkout preserved at:
  `/Users/charl/Code/Gleec/komodo-defi-framework`
- Dedicated worktree:
  `/Users/charl/Code/Gleec/kdf-gnosis-card-local`
- Local branch: `local/gnosis-signing-hardening`
- Upstream: none

The existing KDF checkout, its `feat/tron-gasfree-gui-tweaks` branch, and its
untracked `.agents` directory were not changed. PR #6 was not altered. No KDF
commit was pushed and no new pull request was created.

## Local commits

1. `95c64fd5bf856dff44c35f18cfd6459e271dc568` —
   `fix(eth): validate configured card Safes`
2. `334557f4580ee3bd6aa866244da7d297d5b41205` —
   `fix(eth): restrict card module operations`
3. `2cad0c4784f9b18515ee5cf7e123bff4f93b2f5a` —
   `fix(eth): accept legacy recovery IDs`
4. `574e8606c7a8d1cd2c83ae702533f075e359f19d` —
   `fix(eth): verify full card modifier graph`
5. `08276c76fb13a0165a37c08d9b7d55505bb0a157` —
   `fix(eth): distinguish card chain mismatches`

## Security changes and proof

### Configured Safe registration

Changed symbols:

- `find_authorized_delay`, `verify_authorized_delay`, `safe_modules`, and
  `is_official_zodiac_proxy` in
  `mm2src/coins/eth/safe/service.rs`;
- `RegisteredCardSafe` and `GnosisPayCardSafeRegistry` in
  `mm2src/coins/eth/safe/state.rs`;
- `register_gnosis_pay_card_safe` in
  `mm2src/mm2_main/src/rpc/lp_commands/smart_account.rs`;
- the minimal view/call ABI in
  `mm2src/coins/eth/safe/gnosis_safe_abi.json`.

Registration no longer expects the EOA to remain a core Safe owner after card
setup. It enumerates enabled Safe modules and accepts only the exact Zodiac
minimal-proxy runtime for the supported Delay mastercopy
`0x22d903fd45F441F51bcad198D14eBa8a75EA1ef0`. It then requires:

- `Safe.isModuleEnabled(delay)`;
- `Delay.avatar() == Safe`;
- `Delay.target() == Safe`;
- `Delay.owner() == Safe`;
- `Delay.isModuleEnabled(owner)`.

The registry stores both Safe and verified Delay addresses and remains scoped
to the KDF session. Unit tests cover empty registration, replacement,
owner isolation, shared clone state, exact proxy identity, and ABI selectors.
The wallet integration test proves re-registration when a new coordinator is
created against a restarted KDF session.

### ModuleTx operation allowlist

Changed symbols in `mm2src/coins/eth/safe/typed_data.rs`:

- `validate_and_sign_card_safe_typed_data`;
- `validate_module_operation`;
- `decode_supported_module_operation`;
- exact ABI decoding helpers and `SupportedModuleOperation`.

Every `ModuleTx` must use the registered Delay as its EIP-712 verifying
contract. KDF revalidates that Delay on-chain before signing. Outer calldata
must be canonical
`execTransactionFromModule(address,uint256,bytes,uint8)` with `CALL` and a
non-zero target. Only these inner operations are accepted:

- a non-zero native withdrawal with empty inner calldata;
- canonical ERC-20 `transfer(address,uint256)` to a non-zero recipient and
  amount, with bytecode present at the token address;
- canonical Gnosis Pay `setAllowance` using the official spending key, equal
  non-zero balance/max-refill/refill values, and a non-zero period.

Card registration and signing are pinned to Gnosis Chain ID 100. For limit
changes, KDF also requires a Safe-specific Bouncer whose runtime is an exact
Account Kit v4.10.1 Bouncer with immutable `from`, `to`, and `selector` values
bound to the Safe, Roles module, and `setAllowance`. Its `to` must be an enabled
exact proxy for the supported Roles mastercopy
`0x732B9E9f259fbA6f65A1a012DC89c20872ffBd2f`; Roles avatar and target must both
be the Safe, and Roles ownership must have been transferred to that Bouncer.

The official Bouncer fixture is stored at
`mm2src/coins/eth/safe/test_data/bouncer_runtime_4_10_1.hex`; the production
check normalizes its immutable words and compares the exact runtime hash.

Cross-platform pure tests accept canonical ERC-20 and daily-limit vectors and
reject delegatecall and unknown calldata. Focused tests also reject the wrong
chain, modified Bouncer identity/immutables, wrong Delay or Roles ownership,
and a non-enabled Delay owner. Existing tests continue to reject schema, Safe,
and operation mismatches. `SafeTx` behavior was not expanded or used for
wallet deployment/setup.

Wrong activated-coin networks and wrong typed-data domains remain distinct
typed RPC errors, so a chain-1 coin with a chain-100 payload cannot produce a
misleading “expected 100, got 100” result. The pure chain, Bouncer, modifier
graph, withdrawal, and limit tests use `cross_test!` for native/Wasm coverage.

### Signature compatibility

Changed symbols:

- `EthCoin::verify_message` in `mm2src/coins/eth.rs`;
- `test_sign_verify_message` in `mm2src/coins/eth/eth_tests.rs`.

Signing continues to emit canonical Ethereum recovery IDs (`v=27/28`). Message
verification now normalizes legacy `v=0/1` before recovery. The regression test
verifies both canonical and legacy encodings against the same EIP-191 message.

## Responsibilities deliberately outside KDF

KDF contains no Gnosis HTTP client, card or KYC model, Safe deployment/setup,
persistence, relaying, analytics, UI formatting, or partnership configuration.
The public RPC names and request wire shape remain
`smart_account::register` and `smart_account::sign_typed_data`.

The Flutter SDK normalizes omitted `types.EIP712Domain`, decodes supported
calldata into `PreparedSmartAccountIntent`, compares it with the requested
action, and uses a canonical SHA-256 payload digest as a mutation guard. KDF
calculates and signs the authoritative EIP-712 digest and independently applies
the allowlist. Flutter displays the Safe, chain, Delay, target, recipient,
amount/limit, and temporary-freeze effect before calling KDF.

Safe deployment is exclusively an API/repository responsibility. The app and
KDF consume the address returned after the mock API reaches `ok`; neither
deploys nor configures the Safe.

## Diff statistics

Compared with the reviewed base:

```text
9 files changed, 814 insertions(+), 115 deletions(-)
```

All changed files are limited to existing Ethereum signing, card-Safe
validation/registry, the existing smart-account RPC handler, its minimal ABI,
and focused tests.

## Verification results

Passed:

```sh
cargo fmt --all
cargo test -p coins safe::
# 17 passed

cargo test -p coins test_sign_verify_message
# 3 passed

cargo test -p mm2_eth eip712
# 15 passed

cargo build --release -p mm2_bin_lib --lib
# passed; produced the local SDK dynamic library

cargo clippy -p coins --lib -- -D warnings
# passed

git diff --check 5be59af67ebe1b45b7e9a00c03104b402092a262..HEAD
```

`cargo clippy -p mm2_main --lib -- -D warnings` was also attempted. It was
blocked in unchanged Lightning code by five existing conversions between
`chain::{Transaction, BlockHeader}` and `bitcoin::{Transaction, BlockHeader}`;
none of the reported files are part of this patch.

A final read-only review using the KDF maintainer rubric reported
`would-pass-first-review: yes` with no remaining blocker inside the agreed
signing-only scope.

Wasm relevance was checked with:

```sh
cargo check -p coins --target wasm32-unknown-unknown
```

It did not reach project code on this Apple Silicon host. Both bundled
`secp256k1-sys` versions failed in their C build because the installed `clang`
reported no target compatible with `wasm32-unknown-unknown`. This is an
environment/toolchain failure; the shared operation tests use KDF's
`cross_test!` macro and passed natively. A configured WASI/emscripten KDF build
environment is still required before upstream release.

## Known limitations and assumptions

- Exact supported Delay and Roles mastercopies are pinned to the Account Kit
  deployments reviewed for this implementation, and the Bouncer is pinned to
  Account Kit v4.10.1. A partnership upgrade needs a reviewed allowlist change.
- Safe module discovery requests the first 32 modules. The normal card Safe
  fixture has two; an authorized Delay outside that page fails closed.
- Registry state is intentionally not persisted. Flutter re-registers the Safe
  after KDF restart.
- The pre-existing PR #6 `SafeTx` branch is unchanged and the wallet never uses
  it for deployment or setup. Before any live upstream release, its separate
  pre-setup purpose should be confirmed or removed; this local milestone only
  invokes the allowlisted `ModuleTx` path.
- Mock vectors follow Account Kit v4.10.1. A captured partnership/API payload
  must be added before enabling a live adapter because public examples do not
  yet establish a stable, versioned EIP-712 wire contract.
- The local contract harness installs deterministic official-proxy identities
  for testing; it is not a deployment implementation and is never used by a
  production build.
- No live Gnosis adapter or PSE integration is included in this milestone.

## Recreate and inspect

From the preserved KDF checkout:

```sh
cd /Users/charl/Code/Gleec/komodo-defi-framework
git fetch origin pull/6/head:refs/remotes/origin/pr-6-head
git worktree add \
  -b local/gnosis-signing-hardening \
  /Users/charl/Code/Gleec/kdf-gnosis-card-local \
  5be59af67ebe1b45b7e9a00c03104b402092a262
git -C /Users/charl/Code/Gleec/kdf-gnosis-card-local branch --unset-upstream
```

Inspect or export the local patch:

```sh
git -C /Users/charl/Code/Gleec/kdf-gnosis-card-local \
  diff 5be59af67ebe1b45b7e9a00c03104b402092a262..HEAD

git -C /Users/charl/Code/Gleec/kdf-gnosis-card-local \
  format-patch --stdout \
  5be59af67ebe1b45b7e9a00c03104b402092a262..HEAD \
  > /tmp/gnosis-signing-hardening.patch
```

Final safeguard: the local branch has no `branch.*.remote` or merge target,
the worktree is clean, and nothing from it has been pushed or submitted.
