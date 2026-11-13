# Gleec Wallet v0.10.0 Release Notes

Gleec Wallet 0.10.0 brings Swap, Activity and Advanced trading into one surface,
with atomic order-book and KDF-executed routed quotes compared after costs.
It adds durable swap recovery, clearer review/funding evidence and native-Max
gas headroom, integrates SDK 0.9.0, and includes the macOS startup, market-data
and phone-balance fixes prepared for the unpublished 0.9.8 release.

This release is prepared as a **GitHub draft**. Signed downloads, install/upgrade
qualification and the final LI.FI fee-collection check remain pending in the
[release checklist](https://github.com/GLEECBTC/gleec-wallet/blob/0.10.0/docs/RELEASE_0.10.0_CHECKLIST.md). The latest published app
release remains **0.9.7-1**.

Finalized 13 November 2026 with official KDF main `f9632e0` and SDK main
`554087ee7401c8ea019494273134d92aea6f767a` ([SDK#446](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/446)).
The [input manifest](https://github.com/GLEECBTC/gleec-wallet/blob/0.10.0/docs/RELEASE_0.10.0_INPUTS.json) records the current pins,
artifact hashes and local qualification. Dated earlier audits retain their
original revisions; current hosted qualification is recorded on PR #3575.

## Build and release configuration

- **LI.FI production by default** ([#3585](https://github.com/GLEECBTC/gleec-wallet/pull/3585)) — Direct builds, Docker and GitHub builds select the production integrator. Staging is unavailable; previews use the same production profile while KDP is configured for the production integration. Public profiles, required compiled-profile checks and artifact/dependency records make the selected configuration verifiable. SDK, KDF and coin pins are unchanged by this carry.

## 🚀 New Features

- **One Swap Surface** ([@CharlVS](https://github.com/CharlVS), [#3507](https://github.com/GLEECBTC/gleec-wallet/pull/3507), [#3557](https://github.com/GLEECBTC/gleec-wallet/pull/3557)) — Swap compares supported atomic and routed sources by minimum return after costs. The picker activates assets on demand, preserves Hide 0 balance assets, and explains unsupported pairs or insufficient funds. Advanced trading remains available.
- **Swap Activity and Recovery** ([@CharlVS](https://github.com/CharlVS), #3555, #3557) — Follow active swaps away from the form and after restart, see attention/completion notices, and export evidence explaining funds, approvals and recovery actions.
- **Remote Legal Documents and Consent** ([@CharlVS](https://github.com/CharlVS), #3558) — Load versioned legal documents and gate consent on availability. Production availability must pass before distribution; the existing one-off preview override is not a production waiver.

### SDK Updates (komodo-defi-sdk-flutter)

This release integrates **SDK 0.9.0**, distributed as one pinned checkout:

- Refreshed the verified KDF engine and frozen coins bundle, adding TAR/TAR-segwit and TEL-BASE, removing TEL-KRC20, updating TEL ERC-20/Polygon contracts and decimals, and preserving GLEEC/GRC-20 Trezor support ([SDK#430](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/430), [SDK#431](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/431)).

- Bound executable routed offers and their copies to the manager and wallet
  session that priced them. Wallet transitions cannot replace the session
  underneath dispatch; a lost answer after dispatch remains unconfirmed
  ([SDK#426](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/426),
  [SDK#427](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/427)).
- Recovered every in-flight history page after a cold start and rejected a
  recovery read if the wallet changes during pagination
  ([SDK#417](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/417),
  [SDK#418](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/418)).
- Recovered Trezor wallet files without a saved local record, restored prior
  placeholder policy after failed claims and required successful initialization plus a
  readable active wallet before completing sign-in
  ([SDK#424](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/424),
  [SDK#425](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/425)).

- Typed routed quotes and execution, KDF-owned Max, exact accepted minima,
  durable UUID recovery, required/locked balances and separate measured versus
  provider-reported payouts ([SDK#389](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/389), [SDK#407](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/407)).
- Configured GLEEC/GRC-20 assets for Trezor and unambiguous activation routing
  ([SDK#405](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/405));
  hardware routed signing is not established by this change.
- Correct CoinGecko/CoinPaprika market data, shared bulk price requests and
  encrypted history-cache recovery ([SDK#392](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/392), [SDK#393](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/393), [SDK#401](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/401), [SDK#402](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/402)).
- **Build-log privacy** — Failed build-time SDK GitHub API calls report whether
  authentication was used without logging authorization headers
  ([SDK#434](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/434),
  [SDK#435](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/435)).
- Verified frozen coin files/icons and seven-platform KDF rebuild checksums.
  See the [SDK changelog](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/blob/554087ee7401c8ea019494273134d92aea6f767a/CHANGELOG.md) and [migration guide](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/blob/554087ee7401c8ea019494273134d92aea6f767a/docs/RELEASE_0.9.0.md); immutable runtime pins are recorded below.

## 🐛 Bug Fixes

- **First Trezor Sign-In** ([@CharlVS](https://github.com/CharlVS), [#3590](https://github.com/GLEECBTC/gleec-wallet/pull/3590), [#3589](https://github.com/GLEECBTC/gleec-wallet/pull/3589)) — Save the default coin selection after device authentication finishes, and prevent session restoration from publishing the wallet before setup completes.

- **Swap Start Ownership** ([@CharlVS](https://github.com/CharlVS), [#3583](https://github.com/GLEECBTC/gleec-wallet/pull/3583), [#3584](https://github.com/GLEECBTC/gleec-wallet/pull/3584), [#3592](https://github.com/GLEECBTC/gleec-wallet/pull/3592), [#3593](https://github.com/GLEECBTC/gleec-wallet/pull/3593)) — Pending routed and order-book swaps are revoked when the review is cancelled, replaced or hidden, or its wallet session ends. Reviews and legal consent remain tied to the original session, including logout and login to the same wallet. Submission is serialized with wallet switching for at most 10 seconds, so a request the engine never answers cannot hold off sign-out; SDK offers cannot be rebound to another session. While a start may be running, its amount, Max and unit switch are locked, and Review stays off until a just-signed-in wallet's session is ready. Once a request may have reached the engine, a lost answer remains unconfirmed and is recovered through Activity rather than automatically retried.

- **Trezor Sign-In Errors** ([@CharlVS](https://github.com/CharlVS), [#3581](https://github.com/GLEECBTC/gleec-wallet/pull/3581), [#3582](https://github.com/GLEECBTC/gleec-wallet/pull/3582)) — Replaced the misleading Trezor Suite-only explanation with a general sign-in failure and Suite as one possible cause. The wallet-file recovery itself is covered under SDK Updates above.

- **Wallet History** ([@CharlVS](https://github.com/CharlVS), [#3572](https://github.com/GLEECBTC/gleec-wallet/pull/3572), [#3566](https://github.com/GLEECBTC/gleec-wallet/issues/3566), [SDK#413](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/413)) — Preserve outgoing direction across reconnect/cache refresh, restore ETC through its verified explorer, distinguish self-transfer principal from native fees, and keep unavailable fiat separate from a real zero. Token valuations use their normalized symbol and identify current spot values.

- **Transfer Review and Precision** ([@CharlVS](https://github.com/CharlVS), [#3570](https://github.com/GLEECBTC/gleec-wallet/pull/3570), [#3571](https://github.com/GLEECBTC/gleec-wallet/pull/3571), [#3565](https://github.com/GLEECBTC/gleec-wallet/issues/3565)) — Separate recipient principal from fees and same-asset total debit, including Max. Preserve exact accessible amounts and reject unsupported decimals or an EVM preview that differs from the entered amount before submission.

- **Atomic Token Trading** ([@CharlVS](https://github.com/CharlVS), [#3579](https://github.com/GLEECBTC/gleec-wallet/pull/3579), [#3563](https://github.com/GLEECBTC/gleec-wallet/issues/3563)) — Restore atomic EVM-token trading, Advanced orders and bot starts to the previous release's behavior. The existing review row describes engine-managed allowance, including possible unlimited approval, instead of claiming none is needed. No extra confirmation or feature gate is added; LI.FI keeps its separate approval flow.

- **Review and Start** ([@CharlVS](https://github.com/CharlVS), #3554, #3556, #3557) — Preserved review across layout and policy refreshes, kept it scrollable in short windows, blocked duplicate/stale starts and revalidated replacements against policy, funding and accepted minimums.
- **Native Max Funding** ([@CharlVS](https://github.com/CharlVS), #3557) — Repriced a smaller exact amount with bounded gas headroom before review. Required funding, estimated spending and retained balance stay separate. Later fee or balance changes can still prevent execution; uncertain starts are never automatically resubmitted.
- **Unavailable Fiat Providers** ([@CharlVS](https://github.com/CharlVS), #3557) — Rejected malformed/block-page responses cleanly, cleared stale payment methods, stopped loading and allowed explicit refresh. Upstream Banxa availability remains tracked in [#3559](https://github.com/GLEECBTC/gleec-wallet/issues/3559).
- **Phone Balances and Asset Management** ([@CharlVS](https://github.com/CharlVS), #3546, #3550) — Show whole balances, allow a value too wide to shrink to scroll, and restore asset-manager balance text.
- **Startup, Sign-Out and Prices** ([@DeckerSU], [@CharlVS](https://github.com/CharlVS), [SDK#395](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/395), [SDK#396](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/396), [SDK#394](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/394), [SDK#390](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/390), [SDK#391](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/391)) — Fixed macOS fresh-install startup, distinguished engine failures from wrong passwords, contained early stream disconnects and restored price fallback behavior from the 0.9.8 preparation.

## 💻 Platform and Build Changes

- **macOS** ([@DeckerSU], #3541) — Sign the KDF helper with hardened runtime and timestamp for notarization. Signed packaging and fresh-install validation remain release gates.
- **GasFree TRON** ([@CharlVS](https://github.com/CharlVS), #3546, #3549) — Enable production GasFree defaults in ordinary and shared-CI builds. The four production defines remain pinned for release validation.
- **Frozen Inputs** ([@CharlVS](https://github.com/CharlVS), [SDK#433](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/433), [SDK#446](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/446)) — SDK main `554087ee7401c8ea019494273134d92aea6f767a` pins official KDF main `f9632e0` (`3.2.0-beta`), specs `7c388ea` and coins `cc8249e8`. The engine runtime source matches the preceding `a51d69a` candidate; only KDF's changelog differs. All seven archives were checked against independent release digests and mirror sidecars, with archive contents, compiled commit markers and the native version verified. The final coins roll adds Yenten (YTN) and L2 fee models for AVAX, ETH-BASE, MNT and MON, and removes no coin. Runtime coin updates remain independent. The engine retains the ERC-20 payment validation shipped in 0.9.7-1. Earlier engine inputs remain dated preparation history.
- **RC Previews** ([@CharlVS](https://github.com/CharlVS), [#3587](https://github.com/GLEECBTC/gleec-wallet/pull/3587)) — Enabled ordinary preview updates for hyphenated frozen release branches while retaining the legal-document availability gate.

## Compatibility and Known Limits

SDK 0.9.0 has migration requirements for custom CoinPaprika/activation and
authentication adapters, including session-owned dispatch, and adopters of
interim routed-swap APIs.

- **LI.FI defaults:** supported same-chain/cross-chain quotes, cheapest/fastest
  selection, exact and Max amounts, approval handling, Activity, recovery and
  eligible cancellation are available without a feature opt-in. Asset activation,
  trading policy, funding, reviewed minimums and execution checks still apply.
  `LIFI_INTEGRATOR_ENABLED` controls commission configuration, not availability.
- **Terms availability:** ordinary builds require available wallet and LI.FI
  documents before routed Start. `BYPASS_LEGAL_DOCUMENT_GATE` defaults to false.
  Only the isolated, manually dispatched RC preview bypasses availability,
  retaining its warning and never recording unavailable terms as accepted.
- **Capability scope:** the pinned routed contract supports LI.FI and eligible
  EVM assets; it has no external-recipient parameter. Additional provider
  backends and routed hardware signing are not established by this release.
  Hardware wallets remain wallet-only, as in app 0.9.7-1.
- **Native Trezor sessions:** after an app restart, a failed engine health
  check can restart the engine signed out, so sign in with the device again.
  Locking the device during an attempt returns `Unexpected message` until you
  reconnect and unlock it.
- **Atomic EVM tokens:** trading follows app 0.9.7-1 behavior. The engine may
  reuse an allowance or grant unlimited permission when the trade matches.
  The existing review describes that behavior without inventing a spender,
  exact amount or reset requirement. Start, Advanced orders and bot starts keep
  their previous interaction flow; existing recovery/cancellation stays usable.
- **Release qualification:** current official-engine checks and preview identity
  are recorded on release PR #3575. Signed packaging, fresh installation,
  upgrades and Charl's production LI.FI fee-collection check remain required
  before publication. Earlier engine results retain their exact revisions.
  Five-person usability and live fiat testing were explicitly deferred; the
  named Banxa quote/selection deferral remains separate from Ramp. Neither is
  a passing provider test or a claim that the upstream service is available.

**Full Changelog:** [0.9.7-1...0.10.0](https://github.com/GLEECBTC/gleec-wallet/compare/0.9.7-1...0.10.0).
