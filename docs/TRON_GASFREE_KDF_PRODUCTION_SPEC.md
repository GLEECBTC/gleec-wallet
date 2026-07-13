# TRON GasFree staged KDF production hand-over

Status: implementation handoff

Audience: Komodo DeFi Framework maintainers and reviewers

Consumer: Gleec Wallet and `komodo-defi-sdk-flutter`

Last updated: 2026-07-13

## 1. Purpose

This is the complete, self-contained KDF team hand-over for both staged Gleec
Wallet TRON GasFree releases:

1. the **V1 status-attested opening**, which is the immediate delivery target; and
2. the later **V2 provider-bound release**, which completes the production
   assurance model.

It is a normative implementation contract, not an audit report. No other local
document is required to determine scope, wire behavior, tests, artifacts, or
acceptance. The words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** have their
usual RFC-style meanings.

The following invariants apply to both release profiles:

- Gleec production configuration MUST pin the service-provider address. In the
  V1 profile, KDF attests the resolved provider through
  `gasless::account_status`, and the SDK requires exact equality with the pin
  before exposing receive QR/copy. V2 extends that enforcement through runtime
  configuration, signing, submission, and trace handling. Automatic discovery
  is not an acceptable production default.
- A GasFree request MUST NOT silently downgrade to a native TRON transfer.
- A missing transaction hash after relay acceptance is a pending relay
  submission, not a failed transaction.

V2 adds a further invariant: reconfiguring an already-active TRON runtime MUST
be authoritative; a synthetic “already active” success is not sufficient.

The protocol source of truth is the
[official GasFree developer documentation](https://docs.gasfree.io/). KDF MUST
follow the official TIP-712 domain, authorization fields, provider API, and
trace-state definitions unless a documented and tested proxy contract explicitly
extends them.

## 2. Staged release strategy

### 2.1 Decision and terminology

The project has deliberately pivoted to a staged rollout. The KDF team's
immediate task is the **V1 status-attested opening**, not the full V2 contract.
That release may proceed after the complete V1 delta from `bfd7f7ee…`, required
tests, and immutable platform artifacts pass the acceptance gate in section
20.1.

The full provider-bound assurance profile remains a separate **V2** delivery
and MUST stay disabled until every V2-scoped **MUST** in sections 3–19 and the
V2 acceptance gate in section 20.2 are complete.

In this document, “V2” names Gleec's hardened product release profile. It does
not change the official GasFree TIP-712 domain version `V1.0.0`, and it is
unrelated to KDF's atomic-swap V2 protocol.

| Release profile | KDF delivery | User-facing scope | Status |
| --- | --- | --- | --- |
| V1 status-attested opening | Exact provider attestation, explicit availability, hard identity mismatches, balance-preserving non-usable states, timestamp compatibility, focused tests, and immutable artifacts | Core-wallet GasFree QR/copy for one canonical address; truthful pending/paused/recovery states; Standard TRON remains available | Immediate implementation and artifact target |
| V2 provider-bound release | Runtime configuration, provider enforcement across the lifecycle, signed-request/trace binding, typed errors, finality verification, and full native/WASM parity | Removes V1 restart/status workarounds, enables broader integrations, and provides a fully bound send lifecycle | Deferred until every V2 requirement passes |

Shipping V1 is an explicit constrained-risk decision. It attests the custody
address and provider strongly enough to open the core receive surface, but it
does not assert that the legacy provider API is idempotent or that PR #9 binds
every relay response to its signed request. The app and SDK compensate by
narrowing eligibility and integration scope, preserving unresolved
submissions, and refusing retry after any possibly accepted relay request.

### 2.2 Immediate KDF scope: V1 status-attested opening

The required V1 implementation MUST be developed and reviewed as a delta from
[GLEECBTC/kdf-internal PR #9](https://github.com/GLEECBTC/kdf-internal/pull/9)
tip
`bfd7f7ee30deed4e02b87347e19426b52017d580`. That tip already contains the
Android Cargo serialization and target-scoped workflow changes. There is no
separate local compatibility commit to preserve, replay, or cherry-pick, and
there is no special line-count allowance or limit for V1. The KDF team should
implement the complete behavior below in reviewable Conventional Commits.

The resulting reviewed tip becomes the V1 release candidate. All artifacts
MUST be built from and report that final full SHA.

The KDF team has reported an in-progress account-status correction that adds
the explicit availability states below, suppresses fee/maximum fields whenever
GasFree is unusable, and promotes decimal and custody mismatches to hard errors.
That work is the correct V1 foundation and supersedes the earlier proposed
`provider_available`/`reason_code` compatibility shape. It is not, by itself,
sufficient to open receive: the final V1 candidate must also implement exact
provider selection and the attested `service_provider`, timestamp
compatibility, regression coverage, and artifact requirements specified here.

The KDF team MUST deliver the following V1 behavior. This contract incorporates
the account-availability safety correction; implementations MUST NOT expose both
that contract and the superseded `provider_available`/`reason_code` shape.

1. `gasless::account_status` MUST return required `availability` with exactly
   these V1 values: `available`, `pending_transfer`, `token_unsupported`, and
   `provider_unreachable`.
2. Only `availability: available` means GasFree is usable. It MUST populate
   `active`, `frozen_balance`, `spendable_balance`, `transfer_fee`, and
   `max_withdrawable`; `activation_fee` MAY be `null` for an already-active
   account. A pending transfer MUST never report a positive
   `max_withdrawable` or otherwise look healthy.
3. `pending_transfer`, `token_unsupported`, and `provider_unreachable` MUST
   preserve the locally read custody address and total. A pending response MAY
   retain trusted `active` and `frozen_balance`, but `spendable_balance`, fee
   fields, and `max_withdrawable` MUST be `null`. Unsupported and unreachable
   responses MUST additionally set `active` and `frozen_balance` to `null`.
   These are balance/recovery states, not receive or send readiness.
4. Token-decimal and custody-address mismatches MUST be hard typed errors,
   matching the withdraw path's safety policy. The RPC MUST expose stable
   `TokenDecimalsMismatch` and `CustodyAddressMismatch` error types without raw
   provider content. Consumers retain an earlier custody snapshot for recovery;
   they MUST NOT substitute the EOA balance.
5. When `service_provider` is configured, provider enrollment discovery MUST
   offer that exact TRON address. KDF MUST NOT silently substitute the first
   discovered provider or fall back to the configured provider when discovery
   fails or returns an empty list.
6. An available response MUST echo the exact resolved provider in optional
   `service_provider`. A non-empty provider list that omits the configured pin
   MUST return a stable `ProviderIdentityMismatch` hard error. Provider-list
   outage or an empty list MUST return `availability: provider_unreachable`,
   `service_provider: null`, and the local custody total.
7. Provider timestamps accept RFC3339, epoch seconds, or epoch milliseconds.
   Projected `confirmed_at` is normalized to epoch seconds on the KDF wire
   response. Submit/trace created, updated, and expiry integers retain their
   supplied units; consumers MUST detect and normalize those units explicitly.
   Specifically, `expiredAt`, `createdAt`, `updatedAt`, and
   `txnBlockTimestamp` accept a non-negative JSON integer, a decimal-integer
   string, or RFC3339. Numeric input retains its units; RFC3339 converts to epoch
   seconds. For public `confirmed_at`, numeric values greater than or equal to
   `100000000000` are epoch milliseconds and MUST be integer-divided by `1000`;
   smaller values are epoch seconds. Negative, malformed, fractional, and `u64`
   overflow values MUST fail.
8. Existing strict PR #9 `tx_json` remains wire-compatible. V1 MUST NOT add
   request-envelope fields to the signed relay payload.
9. Standard TRX and Standard TRC-20 behavior remains unchanged and available
   whenever GasFree is unavailable.
10. Focused tests cover exact provider matching, substitution rejection,
   explicit availability, pending-transfer max suppression, hard mismatch
   errors, every balance-only response, timestamp formats, normalization, and
   strict legacy payload compatibility. Shared pure
   parsing logic SHOULD use `cross_test!` unless a target-specific reason is
   recorded.
11. Immutable artifacts and independent SHA-256 checksums are published for
   every declared platform, including Android armv7 and Android arm64.

The following are explicitly **not required for the V1 KDF release** and
remain V2 work:

- `gasless::configure` and authoritative reconfiguration of an already-active
  TRON runtime;
- KDF-issued request envelopes, idempotency keys, or signed-payload
  fingerprints;
- field-by-field submit-response and trace-response binding;
- the V2 typed relay lifecycle error family;
- KDF-side wallet-type and primary-derivation enforcement;
- provider `accountAddress` validation beyond the locally checked custody
  address; and
- any change to PR #9's strict signed `tx_json` shape.

Against the V1 KDF contract, a missing `gasless::configure` method is the
expected compatibility signal. Any other configuration error remains fail-
closed in the SDK.

### 2.3 V1 assurance envelope

The V1 app and SDK profile is intentionally narrow:

- GasFree defaults to disabled; production must explicitly enable the limited
  profile and its separate status-attested receive flag after release-owner
  risk acceptance; a fresh network/provider-bound remote control document is
  also required and may disable new receives at any time;
- only the exact mainnet `USDT-TRC20` or Nile `TESTUSDT-TRC20` identity,
  canonical contract, matching network, configured provider, primary software-
  wallet derivation, and canonical custody address is eligible;
- the exact enrolled identities are mainnet `USDT-TRC20` on `TRX`, contract
  `TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`, and Nile `TESTUSDT-TRC20` on `TRXT`,
  contract `TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf`; both use 6 decimals and the
  primary path `m/44'/195'/0'/0/0`;
- Trezor, custom tokens, secondary derivations, wrong-network assets, and
  provider-rejected tokens always use Standard TRON;
- receive becomes eligible only after a fresh V1 account status echoes the
  exact configured provider, returns the exact locally expected custody
  address, reports explicit `availability: available`, and includes every
  required usable-status field;
- the account-status custody address is authoritative. Cached activation or
  pubkey metadata is used only as an exact cross-check and can never authorize
  receive independently;
- exactly one canonical primary custody candidate must exist. Duplicate,
  secondary, previously cached, hardware-wallet, or ambiguous candidates fail
  closed;
- V1 receive evidence is distinct from legacy transfer verification. A signed
  preview can enable a guarded legacy send but can never enable receive;
- every account-status probe is bound to the stable wallet session and a
  per-asset request epoch. A wallet switch, reset, or newer probe invalidates
  older success and error completions before they can mutate capability,
  balances, or receive evidence;
- V1 opens QR/copy only in the core wallet Receive surface. Bitrefill refund
  selection, consolidation, and other integrations remain bound-relay-only;
- because V1 has no `gasless::configure`, a TRON runtime activated without the
  provider must be restarted or freshly activated. The app must explain this
  limitation and must not synthesize readiness;
- a signed preview must contain the configured provider before an existing
  custody balance can be submitted;
- the SDK-generated request ID and fingerprint are wallet-local recovery data
  and are never injected into the legacy signed relay payload;
- a transport-ambiguous submit, malformed response, trace mismatch, or legacy
  terminal failure remains non-retryable `submittedUnknown`;
- the V1 KDF profile does not provide V2 recursive redaction or complete
  raw-body suppression. Production MUST use the Gleec proxy's stable sanitized
  error contract, direct provider/HMAC mode remains development-only, raw relay
  diagnostics remain off, and support bundles MUST exclude raw KDF/provider
  errors;
- a legacy trace becomes confirmed only after on-chain history verifies the
  transaction hash, token, custody source, recipient, authorized amount, and
  `finalFee <= signedMaxFee`; and
- existing custody balances, pending activity, Standard addresses, and recovery
  remain visible when availability becomes stale, disabled, or unsupported.

The V1 profile therefore supports recovery, guarded sending of existing funds,
and core-wallet QR/copy onboarding for one status-attested canonical GasFree
address. Broader receive integrations and authoritative in-place runtime
upgrade remain V2 capabilities.

Downstream compatibility is intentionally explicit:

- the SDK parses legacy `provider_available` for balance/recovery compatibility
  only; legacy responses set no V1 receive evidence;
- `GaslessReceiveEvidence.statusAttestedV1` is independent of legacy transfer
  verification and is granted only by explicit `availability: available`, exact
  `service_provider`, exact custody address, and complete usable fields;
- `GaslessReceiveEvidence.boundRelayV2` remains the only receive permission for
  Bitrefill, consolidation, and other integrations;
- production core receive requires `TRON_GASLESS_ENABLED=true`,
  `TRON_GASLESS_RECEIVE_ENABLED=true`, and
  `TRON_GASLESS_STATUS_ATTESTED_RECEIVE_ENABLED=true`, plus valid pinned
  provider/base/control URLs and a fresh matching remote-control document; and
- all three switches default to `false`. Disabling them hides new receive
  actions but never hides custody balances, pending activity, or recovery.

### 2.4 GUI value enabled by the staged system contract

KDF does not own Flutter layout or copy. Its structured responses, together
with the V1 SDK/app/proxy mitigations and later V2 KDF guarantees,
determine whether the GUI can be accurate and financially safe.

- **Truthful availability:** users see neutral, unsupported, recovery, or
  security states instead of a false green GasFree promise.
- **Preserved access:** provider or token problems do not make an existing
  custody balance disappear.
- **Safer sending:** the V1 SDK treats every ambiguous relay outcome as
  processing and suppresses duplicate sends; V2 KDF adds authoritative
  rejected-versus-accepted classification.
- **Clear money presentation:** custody total, spendable amount, fee maximum,
  recipient amount, and final fee remain distinct.
- **Predictable recovery:** Standard TRON remains usable and unsupported custody
  deposits retain an official recovery path.
- **Safe V1 onboarding:** exact provider/address attestation lets the wallet
  reveal one canonical GasFree QR/copy action without weakening other
  integrations.
- **V2 simplification:** authoritative configuration and bound relay responses
  remove restart messaging, legacy inference, and duplicate verification seams.

| Interface or system behavior | V1 GUI value | Additional V2 GUI value |
| --- | --- | --- |
| Explicit availability plus typed mismatches | Distinct ready, pending, unsupported, unreachable, and security messaging without inferring usability from a balance | V2 adds lifecycle-wide typed state and terminality |
| Exact `service_provider` in ready status | Core receive opens only for the configured provider; missing/old KDF responses remain fail-closed | The same pin is enforced through configure, sign, submit, and trace |
| Deterministic token, decimal, or custody mismatch | Custody funds stay visible with recovery actions, while in-app GasFree send/receive controls remain disabled | Provenance is combined with authoritative spendable and frozen amounts |
| Temporary provider unavailability | Custody balance and recovery remain visible with neutral messaging; receive and stale spend limits stay hidden while recheck or fresh preview remains available | Provider-bound status distinguishes a safe retry from a security mismatch |
| RFC3339/seconds/milliseconds compatibility | Normalized `confirmed_at` renders consistently; created, updated, and expiry values are accepted without assuming they were normalized | Bound trace finality adds trustworthy block and confirmation metadata |
| Strict Standard/GasFree rail separation | Unsupported users remain on familiar Standard TRON instead of silently entering custody | KDF attests the exact rail and runtime configuration before signing |
| Legacy signed preview exposes the service provider; SDK verifies the configured pin | Existing custody sends show provider, fee maximum, and expiry before approval | KDF verifies the provider pin before status, preview, submit, and every trace response |
| Legacy relay result plus SDK recovery policy | GUI shows “Still processing,” keeps durable activity, and hides “Try again” | Bound request/trace data allows stronger reconciliation and terminal-state classification |
| Runtime reconfiguration | Fresh activation/restart is required before V1 receive can become ready | Already-active TRON assets can become authoritatively GasFree-ready without restart |
| Production error sanitation | Release enablement requires operational proof that the Gleec proxy emits only stable codes/correlation IDs and withholds raw provider content from GUI and support bundles | KDF additionally enforces recursive redaction and raw-body suppression at the protocol boundary |
| Immutable native/WASM artifacts | The same limited behavior reaches supported devices, including Android | Every platform exposes the complete provider-bound V2 contract with parity evidence |

The V1 availability/error values map to the following safe GUI contract:

| KDF outcome | V1 KDF response | Required GUI interpretation |
| --- | --- | --- |
| `availability: available` | Exact `service_provider` and complete usable fields | Core-wallet QR/copy may open only after SDK/app identity, freshness, and remote-control gates also pass |
| `availability: pending_transfer` | Custody total retained; trusted active/frozen data may remain; spendable, fee fields, and maximum `null` | “Transfer in progress”; retain balance/activity/recovery, with no receive or new send |
| `availability: token_unsupported` | Custody total retained; every provider-derived status, spendable, fee, and maximum field `null` | Use Standard TRON for normal actions and offer official custody recovery; no GasFree send/receive |
| `availability: provider_unreachable` | Custody total retained; `service_provider` and every provider-derived status, spendable, fee, and maximum field `null` | Neutral temporary-unavailability state; retain balance/recovery, hide receive and spend limits, allow recheck |
| `TokenDecimalsMismatch` | Typed hard error; no usable status | Security/recovery state; retain any earlier custody snapshot, never substitute EOA balance, and disable GasFree send/receive |
| `CustodyAddressMismatch` | Typed hard error; no usable status | Security/recovery state with official recovery/support guidance; disable GasFree send/receive |
| `ProviderIdentityMismatch` | Typed hard error; no usable status | Security state; disable GasFree send/receive while retaining Standard and existing recovery access |

### 2.5 V2 provider-bound delivery

The V2-scoped requirements in sections 3–19 specify the deferred KDF
implementation; requirements marked **V1** or **Both profiles**
apply as stated. V2 is required before the app may enable GasFree receive in
Bitrefill, consolidation, or other integrations, remove V1 compatibility seams,
or claim a fully provider-bound relay lifecycle. Android build fixes alone do
not satisfy V2 because signing and relay submission occur inside KDF; runtime
safety, response binding, typed errors, and finality verification must also be
implemented.

V2 must remove or narrow the following downstream compatibility seams only
after the corresponding KDF capability and immutable artifacts are promoted:

| V1 compatibility seam | V2 KDF replacement | SDK/GUI change after promotion |
| --- | --- | --- |
| Fresh activation/restart requirement | Authoritative `gasless::configure` | Remove restart guidance and missing-configure compatibility path |
| `statusAttestedV1` wallet-only receive evidence and build flag | `boundRelayV2` capability | Retire the V1 receive flag/path for new sessions |
| SDK/app canonical-wallet and derivation inference | KDF wallet-type and primary-path enforcement | Remove local eligibility inference as an authority; retain display checks defensively |
| Account-status provider echo plus preview-time provider comparison | Provider pin enforced across configure, status, signing, submit, and trace | Collapse duplicated provider inference into typed KDF capability/errors |
| SDK-local request UUID/fingerprint and mandatory independent finality matching | KDF-issued request/fingerprint context and bound relay responses | Stop creating the local workaround for new V2 sends; retain it for migrated legacy pending records |
| Core-wallet QR/copy only | Fully bound receive/send capability | Permit Bitrefill, consolidation, and other reviewed integrations to use the shared bound gate |

The remote receive kill switch, custody/recovery visibility, durable
pending/unknown activity, no-retry rule after possible acceptance,
duplicate-send reservation, and copy/QR sensitive-action revalidation remain
permanent safeguards; V2 does not remove them.

### 2.6 Local delivery references

The implementation is deliberately split so the initial pull request stays
reviewable while the complete V2 target remains available to the KDF team:

| Component | Local branch | Commit | Purpose |
| --- | --- | --- | --- |
| KDF V1 implementation base | `feat/tron-gasfree-gui-tweaks` remote PR tip | `bfd7f7ee30deed4e02b87347e19426b52017d580` | Exact base for the KDF team to implement the complete V1 contract in this document; no local follow-up commit exists |
| Complete KDF contract | `add/gas-free-tron-hardening` | `049012bc3540f3307e67c1afe537c8208f6498b5` | Full provider pinning, runtime configuration, relay binding, typed errors, and validation |
| Flutter SDK | `add/tron-gas-free` and `add/gas-free-tron-hardening` | `179daea217d8a0e130d680f6915efba159bea7af` | Hardened SDK with bound-relay mode, wallet-only V1 receive attestation, and session-safe status/recovery handling |
| Gleec Wallet implementation | `add/gas-free-tron` | `24b5527e3dc7c620d60ea3dabc5186e5b5519425` | Last non-document snapshot: status-attested core receive, fail-closed custody UX, recovery, integration isolation, and rollout controls |

The complete KDF tip consists of these reviewable commits, oldest first:

1. `4b2bfa8dc966c24d24fdc2fc3f8414068cce0a79` — provider invariants;
2. `32804840ab73e281016cb322c875ed76d1954d1a` — runtime reconfiguration;
3. `223c31ab6a3dc8975d616942bfbc2f8fdb3306db` — relay lifecycle binding;
4. `049012bc3540f3307e67c1afe537c8208f6498b5` — integration coverage.

That V2 tip is a reference snapshot based on `997332e5…`, not a directly
promotable descendant of the final V1 release. Before V2 promotion, its
commits MUST be rebased or cherry-picked and reconciled onto the final V1 SHA,
retaining explicit availability, hard mismatch errors, exact status provider
attestation, timestamp compatibility, Android CI fixes, and all V1 regression
coverage.

The SDK hardening tip consists of these reviewable commits, oldest first:

1. `49c5a8395fb9dd25be21d29f638a4114c1641113` — hardened public transfer contracts;
2. `996170711b913bb7785c1197456390ce017f4172` — wallet-scoped capability enforcement;
3. `68bc1a09c9aa38eb650fb889f9da3404660f5a6c` — durable unresolved-relay recovery;
4. `80ebc370093e85d539e928a6b5f3614327213d4d` — custody balance and history reconciliation;
5. `0bfb44f49feb99d5eaf78609a879870dff8dd41c` — spend-limit UI clarity;
6. `fa56cf611cc7f1b3556bece704e4ba316735b2d0` — SDK 1.0 migration metadata;
7. `a177ab2c5449d17251d2919074ac1e754e9636b7` — wallet-only receive-evidence contract;
8. `e141d13e5e9bad82ec5f1470fcf133ca0f45eada` — legacy account-status receive attestation;
9. `7f2dba7de8da9f8b33f80342656110ab0e3102a3` — session-scoped attestation readiness;
10. `f3d1c6f331a38d92e076b095d4c67f0c0a0f3fd7` — receive-attestation lint cleanup; and
11. `179daea217d8a0e130d680f6915efba159bea7af` — explicit-availability validation, wallet/session binding, request ordering, and recovery-race coverage.

The Gleec Wallet implementation snapshot consists of these reviewable commits,
oldest first:

1. `0872843db0978a54ad8608cd0bc88f3e7ef07010` — hardened SDK integration and artifact reference;
2. `9b2e5c7ddf1f55dbd3e03d23abb9aa35f4a2bd3a` — custody and relay-state UX;
3. `64fd06de95a2dc23e6b19e85a6e2e3b8c28b8b0c` — wallet integrations and sensitive-action revalidation;
4. `176c6d643e076a211834b1bf38a02cd521c3f6f7` — production proxy controls;
5. `03ab61c9f748fb73f49dae72f76d46855c8f3553` — release configuration gates;
6. `3a1ca2db1b0dbfa96ecf9c6b13fee4e273fa5675` — status-attested core receive, explicit availability UX, and sensitive-action revalidation; and
7. `24b5527e3dc7c620d60ea3dabc5186e5b5519425` — false-default status-attested receive build gate.

The documentation commit containing this specification is the local main-app
branch tip. It cannot embed its own commit identifier without changing that
identifier; the seven immutable implementation commits above are the handoff
reference for code and configuration review.

These branches and commits are provenance and implementation-acceleration aids;
the normative requirements in this document do not depend on access to them.
They are not published artifacts and MUST NOT be placed in an SDK build manifest
until their commits and immutable binaries are available to every build
environment.

### 2.7 Visual-design gate status

This is wallet-team context, not a KDF acceptance criterion. KDF's GUI-facing
responsibility ends at stable, typed, semantically correct response data.

- **Basis:** the Gleec UI-Pro accessibility, touch, responsive, forms/error
  recovery, navigation, and financial-data checklists were applied to the
  Flutter flow.
- **Status:** exception. No canonical Purple Vault design pack or repository
  design-language source was available in this checkout.
- **Implemented under the exception:** behavioral state clarity, existing-theme
  consistency, semantic labels and announcements, minimum touch targets,
  scroll/wrap behavior, light/dark contrast review, and 200% text support.
- **Wallet-team follow-up:** obtain the canonical design source and complete
  identical-viewport visual comparisons before describing the feature as
  visually pristine.

## 3. Scope

Unless a requirement is explicitly labeled **V1** or **Both
profiles**, sections 3–19 define the V2 provider-bound profile. Sections 5 and
15 explicitly preserve shared protocol and compatibility invariants. In
sections 3–19, **Release blocker** means a blocker for V2 enablement unless the
heading says **V1 release blocker**.

### 3.1 In scope

- TRON mainnet and Nile network identification.
- TRC-20 GasFree provider configuration.
- Canonical software-wallet eligibility.
- Runtime GasFree configuration for already-active coins.
- Custody account status and balance provenance.
- GasFree withdraw preview and TIP-712 signing.
- Relay submission through `send_raw_transaction` or an equivalent typed RPC.
- Relay acceptance, trace polling, finality, and response verification.
- Stable typed RPC errors.
- Secret redaction and safe diagnostics.
- Native/WASM parity and immutable release artifacts.

### 3.2 Out of scope

- Flutter UI layout, copy, accessibility, and localization.
- SDK encrypted storage and restart reconciliation.
- Application remote receive kill switch.
- Production proxy deployment, peer mesh, rate limiting, CORS, and operations.
- DEX settlement from GasFree custody.
- Multi-address GasFree custody in either Gleec release profile.

The SDK owns durable pending-transfer persistence. KDF owns the correctness and
security of every value the SDK persists.

## 4. Protocol and trust model

### 4.1 V1 status-attested flow

V1 uses the legacy PR #9 relay contract. It does not call
`gasless::configure`, and it does not add local SDK recovery fields to KDF's
strict signed `tx_json`.

```mermaid
sequenceDiagram
    participant App as Gleec Wallet
    participant SDK as Flutter SDK
    participant KDF
    participant Provider as GasFree provider
    participant Tron as TRON network

    App->>SDK: request canonical GasFree receive readiness
    SDK->>KDF: gasless::account_status
    KDF->>Provider: discover enrollment and require configured provider
    KDF->>Provider: read account/provider status
    KDF->>Tron: read canonical custody token balance
    KDF-->>SDK: exact provider/address availability or typed mismatch error
    SDK->>SDK: verify provider, custody, asset, wallet, path, complete fields
    SDK-->>App: status-attested V1 receive evidence
    App->>App: require fresh remote control; expose core QR/copy only
    App->>SDK: send custody funds
    SDK->>KDF: legacy gasless withdraw preview
    KDF-->>SDK: strict signed tx_json + fee authorization
    SDK->>SDK: verify provider pin; persist local request ID/fingerprint
    SDK->>KDF: send_raw_transaction(strict tx_json)
    KDF->>Provider: submit signed authorization
    Provider-->>KDF: legacy acceptance or transport outcome
    KDF-->>SDK: trace/legacy result
    SDK->>SDK: persist trace immediately when present
    loop Until exact reconciliation
        SDK->>KDF: legacy trace status
        SDK->>Tron: verify raw on-chain token event
    end
    SDK-->>App: processing, confirmed, or non-retryable unknown
```

The status response attests the provider and custody address for receiving; it
does not bind a later relay response to its signed request. The local request ID
and fingerprint improve wallet-scoped recovery but are not provider idempotency
keys. That residual risk is why ambiguous outcomes remain locked and why
confirmation requires exact on-chain reconciliation.

### 4.2 V2 provider-bound flow

```mermaid
sequenceDiagram
    participant App as Gleec Wallet
    participant SDK as Flutter SDK
    participant KDF
    participant Proxy as Gleec proxy
    participant Provider as GasFree provider
    participant Tron as TRON network

    App->>SDK: enable/check GasFree
    SDK->>KDF: gasless::configure
    KDF->>Proxy: provider/token/account checks
    Proxy->>Provider: authenticated GasFree API
    KDF-->>SDK: authoritative account status
    SDK->>KDF: withdraw preview (gasless)
    KDF->>KDF: construct and sign TIP-712 permit
    KDF-->>SDK: signed relay payload + fee authorization
    SDK->>KDF: send_raw_transaction(tx_json)
    KDF->>Provider: submit signed authorization via proxy
    Provider-->>KDF: trace ID and echoed authorization data
    KDF->>KDF: validate response against signed request
    KDF-->>SDK: relay acceptance, not a transaction hash
    loop Until terminal
        SDK->>KDF: gasless::trace_status
        KDF->>Provider: query trace via proxy
        Provider-->>KDF: trace and on-chain state
        KDF->>KDF: bind and validate all fields
        KDF-->>SDK: pending/on-chain/confirmed/failed
    end
    Provider->>Tron: sponsor and submit transaction
```

Trust assumptions:

- In V1, the SDK and app MAY trust the exact ready account status only for the
  narrow receive decision described in section 2.3. Relay responses remain
  provisional and require the legacy recovery/finality policy.
- In V2, the SDK and app MUST NOT trust provider data that KDF has not
  validated and bound to the signed request.
- The provider may be unavailable, stale, compromised, or return a response for
  the wrong authorization.
- A transport failure during the submit POST may occur before or after provider
  acceptance. It is therefore an unknown financial outcome unless KDF has
  definitive evidence of rejection.
- `requestId` is documented by GasFree for issue investigation; the official
  API does not promise idempotency or request-ID lookup. KDF MUST NOT treat it as
  an idempotency guarantee.

## 5. Network constants and signed authorization — Both profiles

KDF MUST use the official GasFree constants:

| Network | Chain ID | Verifying contract |
| --- | ---: | --- |
| TRON mainnet | `728126428` | `TFFAMQLZybALaLb4uxHA9RBE7pxhUAjF3U` |
| Nile | `3448148188` | `THQGuFzL87ZqhxkgqYEryRAd7gqFqL5rdc` |

The TIP-712 domain MUST be:

```text
name: GasFreeController
version: V1.0.0
chainId: network-specific value above
verifyingContract: network-specific value above
```

The signed `PermitTransfer` message MUST bind exactly:

```text
token
serviceProvider
user
receiver
value
maxFee
deadline
version
nonce
```

Requirements:

- `version` MUST equal `1` until a separately reviewed protocol upgrade exists.
- `value`, `maxFee`, `deadline`, `version`, and `nonce` MUST be parsed without
  floating-point conversion.
- Provider amounts MUST be interpreted in token base units and converted using
  the activated token’s authoritative decimal count.
- Signature generation and recovery MUST use the exact signed message above.
- **V2:** Chain ID, verifying contract, token, provider, signer, receiver, amount,
  maximum fee, deadline, version, and nonce MUST be revalidated immediately
  before submission.

## 6. Capability and wallet eligibility

### KDF-GF-001 — Canonical wallet identity — Release blocker

The Gleec single-custody GasFree profile MUST be available only for the
canonical primary software-wallet address:

- HD wallet: external address `m/44'/195'/0'/0/0` only.
- Iguana wallet: its single primary address.
- Trezor, WalletConnect, MetaMask, secondary HD derivations, change addresses,
  or any address not owned by the active wallet MUST be rejected.

KDF MUST derive the GasFree custody address locally from the canonical EOA and
network. A provider-reported custody address MUST match this local derivation.

For V1, the SDK and app MUST restrict GasFree custody to that
single canonical address and treat secondary derivations as Standard TRON. V2
KDF MUST enforce the same restriction authoritatively and MUST NOT expose
additional GasFree custody accounts for secondary derivations.

### KDF-GF-002 — Token and network capability — Release blocker

Eligibility MUST be based on all of the following, not on ticker alone:

- active chain is TRON;
- active asset is a TRC-20 token of that platform;
- token contract belongs to the active network;
- provider reports that exact contract as supported;
- provider decimal count matches KDF’s activated token decimals;
- provider pin is resolved and matches;
- wallet identity satisfies KDF-GF-001;
- token has a live runtime GasFree configuration.

Every unverified case MUST fail closed. KDF MUST NOT infer GasFree support from
a `gasfree_address` field or from a token name.

## 7. Provider configuration

### KDF-GF-003 — Strict configuration — Release blocker

KDF MUST support a provider configuration equivalent to:

```json
{
  "base_url": "https://quicknode.gleec.com/gasfree/tron",
  "service": "komodo_proxy",
  "service_provider": "T...",
  "allow_service_provider_discovery": false,
  "request_timeout_ms": 15000,
  "status_poll_interval_ms": 3000,
  "unsafe_allow_insecure_http": false
}
```

Production invariants:

- `service_provider` is mandatory and MUST be a valid TRON address.
- `allow_service_provider_discovery` defaults to `false`.
- The provider returned by `/api/v1/config/provider/all` MUST contain the pinned
  address. A mismatch MUST fail before signing.
- `service` MUST be `komodo_proxy` in production.
- Direct HMAC mode MAY exist for development only and MUST require an explicit
  `unsafe_allow_direct_hmac: true` opt-in.
- Direct HMAC credentials MUST NOT be accepted when empty.
- Production URLs MUST use HTTPS.
- URL credentials, query parameters, fragments, backslashes, duplicate path
  separators, traversal-like segments, and malformed paths MUST be rejected.
- Plain HTTP MUST require an explicit development-only opt-in.
- Request timeout MUST be bounded to `1,000..60,000 ms`.
- Status polling interval MUST be bounded to `500..60,000 ms`.
- Configuration validation MUST use runtime errors, not `assert!` or
  release-disabled assertions.

Direct mode uses a host-only URL and KDF appends the network path. Proxy mode
preserves the configured proxy mount and network path. KDF MUST not silently
rewrite a production proxy URL to another network.

### KDF-GF-004 — Provider limits — V2 release blocker

KDF MUST fetch and validate the pinned provider’s:

- `maxPendingTransfer`;
- `minDeadlineDuration`;
- `defaultDeadlineDuration`;
- `maxDeadlineDuration`.

The requested deadline duration MUST fall within provider bounds. An omitted
duration uses the provider default. The absolute signed deadline MUST be
revalidated immediately before submission.

## 8. Runtime configuration RPC

### Activation-time configuration

Fresh TRON activation MUST accept the same provider contract under
`tron_gasless_provider`, and each token request MUST opt in explicitly:

```json
{
  "ticker": "TRX",
  "nodes": [{ "url": "https://..." }],
  "tron_gasless_provider": {
    "base_url": "https://quicknode.gleec.com/gasfree/tron",
    "service": "komodo_proxy",
    "service_provider": "T...",
    "allow_service_provider_discovery": false
  },
  "erc20_tokens_requests": [
    {
      "ticker": "USDT-TRC20",
      "gasless": {
        "enabled": true,
        "transfer_max_fee": "20"
      }
    }
  ]
}
```

The fresh activation path and `gasless::configure` MUST share the same
validation helpers and capability semantics. A token MUST NOT become GasFree
ready merely because its activation request contained `gasless.enabled=true`.
Provider enrollment, decimals, wallet identity, custody identity, and account
status must all pass first. Passive re-enable MUST either apply the requested
configuration authoritatively or return a typed mismatch directing the caller
to `gasless::configure`; it MUST NOT silently retain a provider-less runtime.

### KDF-GF-005 — `gasless::configure` — Release blocker

KDF MUST expose an authoritative one-shot RPC for an already-active TRON
platform and token set.

Request:

```json
{
  "mmrpc": "2.0",
  "method": "gasless::configure",
  "params": {
    "platform_coin": "TRX",
    "provider": {
      "base_url": "https://quicknode.gleec.com/gasfree/tron",
      "service": "komodo_proxy",
      "service_provider": "T...",
      "allow_service_provider_discovery": false,
      "request_timeout_ms": 15000,
      "status_poll_interval_ms": 3000
    },
    "tokens": [
      {
        "coin": "USDT-TRC20",
        "transfer_max_fee": "20"
      }
    ]
  }
}
```

Response:

```json
{
  "platform_coin": "TRX",
  "service_provider": "T...",
  "tokens": [
    {
      "coin": "USDT-TRC20",
      "account_status": {
        "gasfree_address": "T...",
        "active": true,
        "on_chain_balance": "100",
        "frozen_balance": "0",
        "spendable_balance": "100",
        "transfer_fee": "1",
        "activation_fee": null,
        "max_withdrawable": "99",
        "availability": "available",
        "service_provider": "T..."
      }
    }
  ]
}
```

Required behavior:

- Reject an empty token list and duplicate tickers.
- Reject inactive, non-TRON, wrong-platform, or non-TRC-20 assets.
- Verify each token’s contract, enrollment, decimals, provider status, and
  canonical account before mutating any live coin state.
- Validate the full request before publishing any partial capability.
- Publish token configuration first and the provider runtime last, or use an
  equivalent atomic update that prevents partial readiness.
- Return success only after an authoritative account-status check succeeds for
  every requested token.
- If the active runtime already uses another provider pin, fail explicitly.
  Provider rotation requires resolving outstanding transfers, deactivating the
  platform, and reactivating with the new pin.
- Use `#[serde(deny_unknown_fields)]` on request types.

Required typed errors include:

```text
CoinNotFound
InvalidPlatform
InvalidToken
DuplicateToken
EmptyTokenList
TokenNotSupported
TokenDecimalsMismatch
AccountStatusUnavailable
InvalidConfiguration
ProviderError
Internal
```

Errors MUST implement `SerializeErrorType` and `HttpStatusCode` with
appropriate 4xx, 502/503, and 500 mappings.

## 9. Custody account status RPC

### KDF-GF-006 — `gasless::account_status` — V1 release blocker

Request:

```json
{
  "mmrpc": "2.0",
  "method": "gasless::account_status",
  "params": { "coin": "USDT-TRC20" }
}
```

The response MUST contain:

| Field | Meaning |
| --- | --- |
| `gasfree_address` | Locally derived canonical custody address |
| `active` | Provider activation status, or `null` when unavailable |
| `on_chain_balance` | TRC-20 balance at the custody address; always present |
| `frozen_balance` | Provider-reported in-flight amount, or `null` |
| `spendable_balance` | Custody total minus frozen, or `null` |
| `transfer_fee` | Token-denominated provider transfer fee, or `null` |
| `activation_fee` | One-time token fee when applicable, otherwise `null` |
| `max_withdrawable` | Spendable minus fees, clamped to zero, or `null` |
| `availability` | Required V1 usability state |
| `service_provider` | Exact resolved provider address when ready, otherwise `null` |

V1 `availability` values:

```text
available
pending_transfer
token_unsupported
provider_unreachable
```

V1 hard-error `error_type` values added to `GaslessAccountStatusError`:

```text
TokenDecimalsMismatch
CustodyAddressMismatch
ProviderIdentityMismatch
```

These errors MUST implement `SerializeErrorType` and `HttpStatusCode`, contain
only stable non-secret fields, and never require consumers to parse display
messages. V2 may add finer authentication and invalid-response categories.

Requirements:

- `on_chain_balance` MUST be read from the custody address, never substituted
  from the EOA.
- Before returning ready, KDF MUST resolve provider enrollment and require the
  configured provider exactly. A non-empty provider list that omits the pin is
  `ProviderIdentityMismatch`; directory outage or an empty response produces
  `availability: provider_unreachable`. Neither path may use a fallback.
- A V1 ready response MUST contain the exact `service_provider`, omit
  legacy `provider_available`/`reason_code`, set `availability: available`, and
  populate `active`, `frozen_balance`, `spendable_balance`, `transfer_fee`, and
  `max_withdrawable`.
- KDF MUST combine the on-chain balance with provider `frozen` state before
  calculating spendability.
- `pending_transfer` MUST set `transfer_fee`, `activation_fee`,
  `spendable_balance`, and `max_withdrawable` to `null`. It MAY retain trusted
  `active` and `frozen_balance` for presentation, but it is not receive/send
  readiness.
- `token_unsupported` and `provider_unreachable` MUST retain the local custody
  total and set `service_provider`, `active`, `frozen_balance`, fee fields,
  spendable balance, and maximum to `null`.
- Provider identity, token, decimal, custody, or pending mismatch MUST never
  return a positive maximum or usable spendability.
- Authentication failure may degrade for read-only balance visibility, but
  preview/submission MUST still fail.
- Unknown provider states or malformed amounts MUST not be accepted.

Canonical V1 ready result shape:

```json
{
  "gasfree_address": "T...",
  "active": true,
  "on_chain_balance": "25.000000",
  "frozen_balance": "0.000000",
  "spendable_balance": "25.000000",
  "transfer_fee": "1.000000",
  "activation_fee": null,
  "max_withdrawable": "24.000000",
  "availability": "available",
  "service_provider": "T..."
}
```

Canonical V1 degraded result shape:

```json
{
  "gasfree_address": "T...",
  "active": null,
  "on_chain_balance": "25.000000",
  "frozen_balance": null,
  "spendable_balance": null,
  "transfer_fee": null,
  "activation_fee": null,
  "max_withdrawable": null,
  "availability": "provider_unreachable",
  "service_provider": null
}
```

## 10. Withdraw preview and signed relay payload

### KDF-GF-007 — Explicit rail selection — Release blocker

A GasFree preview request MUST use an explicit rail:

```json
{
  "coin": "USDT-TRC20",
  "from": { "derivation_path": "m/44'/195'/0'/0/0" },
  "to": "T...",
  "amount": "10",
  "max": false,
  "fee_method": "gasless",
  "gasless": {
    "max_fee": "2",
    "deadline_seconds": 300,
    "fallback_to_native": false
  }
}
```

Requirements:

- `fallback_to_native` MUST default to `false`.
- Gleec production requests always set it to `false`.
- When false, KDF MUST return a typed error instead of building a native TRON
  transaction for any GasFree failure.
- GasFree options used with the native rail or a non-TRON asset MUST be rejected.
- Preview MUST re-fetch account info, recommended nonce, frozen funds, token
  enrollment, fees, `allowSubmit`, and provider limits.
- The selected source MUST be the canonical EOA from KDF-GF-001.
- `max=true` MUST calculate the maximum from authoritative custody spendable
  funds after frozen value, transfer fee, and activation fee.
- Zero, below-fee, fully frozen, partially frozen, and exact-fee boundaries
  MUST be distinguished.
- Fee cap is the smaller of the request cap and runtime token cap. The quoted
  fee MUST not exceed it.
- The permit MUST be signed locally only after all preflight checks pass.

The preview fee variant MUST be distinct from native TRON fees and include:

```json
{
  "type": "TronGasless",
  "coin": "USDT-TRC20",
  "fee_method": "gasless",
  "provider_name": "gasfree",
  "provider_address": "T...",
  "gasfree_address": "T...",
  "transfer_fee": "1",
  "activation_fee": null,
  "total_token_fee": "1",
  "signed_max_fee": "2",
  "authorization_deadline": "1780000000",
  "request_id": "uuid-v4",
  "authorization_fingerprint": "sha256-hex",
  "trace_id": null
}
```

The opaque `tx_json` relay payload MUST contain enough information for KDF to
revalidate the authorization at submission, including:

```text
relay type and wire version
UUID-v4 request ID
SHA-256 signature fingerprint
chain ID
coin
source derivation selector, when HD
source EOA
locally derived custody address
verifying contract
complete signed authorization
creation time
```

Secret-bearing relay payloads MUST use strict deserialization and redacted
debug/string output.

## 11. Relay submission

### KDF-GF-008 — Pre-submit revalidation — Release blocker

Before any provider submit POST, KDF MUST:

1. Strictly decode the relay payload and reject unknown fields.
2. Verify relay type/wire version.
3. Confirm the coin is the configured TRC-20 token.
4. Confirm chain ID and verifying contract.
5. Confirm token and pinned provider.
6. Confirm source EOA belongs to the active wallet.
7. Confirm HD source is exactly the canonical primary derivation.
8. Recompute and compare the custody address.
9. Recover and verify the TIP-712 signature.
10. Compare the raw signature fingerprint.
11. Confirm receiver, amount, maximum fee, deadline, version, and nonce.
12. Confirm the signed maximum fee does not exceed the current runtime cap.
13. Reject expired or provider-out-of-range deadlines.
14. Re-fetch account info and verify EOA, custody address, nonce, token,
    decimals, fees, frozen balance, and `allowSubmit`.

KDF MUST serialize preflight and submit under a per-canonical-EOA lock so two
local calls cannot both observe `allowSubmit=true` and submit concurrently.

### KDF-GF-009 — Submission response binding — Release blocker

KDF MUST validate the provider submit response before returning relay
acceptance. It MUST compare:

```text
trace ID format
request ID, when echoed
account EOA
locally derived custody address
provider address
receiver/target address
token contract
recipient amount
maximum fee
version
nonce
expiry/deadline
signature, when echoed
estimated activation + transfer fee <= signed maximum
```

If the response contains a valid trace ID but another field mismatches, KDF
MUST return a typed security error with `relay_accepted=true`, the safe request
ID, trace ID, and mismatched field. The client must then reconcile the trace and
must not resubmit.

### KDF-GF-010 — Successful submission contract — Release blocker

A successful relay submission MUST return a relay acceptance, not a fake
on-chain transaction hash:

```json
{
  "relay_type": "tron_gasfree",
  "request_id": "uuid-v4",
  "trace_id": "provider-trace-uuid",
  "state": "WAITING",
  "expected_authorization": {
    "request_id": "uuid-v4",
    "account": "T...",
    "custody_address": "T...",
    "provider": "T...",
    "receiver": "T...",
    "token": "T...",
    "amount": "10000000",
    "max_fee": "2000000",
    "deadline": "1780000000",
    "version": "1",
    "nonce": "9",
    "signature_fingerprint": "sha256-hex"
  }
}
```

`request_id`, `trace_id`, and the expected authorization context MUST be
available to the SDK immediately. `tx_hash` remains absent until the provider
reports an on-chain transaction.

## 12. Typed submission errors

### KDF-GF-011 — Stable error envelope — Release blocker

GasFree structured-submission errors MUST NOT be flattened into display text.
The wire shape MUST be equivalent to:

```json
{
  "error": "GasFree relay submission failed",
  "error_type": "GaslessRelaySubmission",
  "error_data": {
    "code": "authorization_expired",
    "stage": "submission",
    "retryable": true,
    "terminal": true,
    "relay_accepted": false
  }
}
```

Required stable codes:

| Code | Meaning | `relay_accepted` | Safe action |
| --- | --- | --- | --- |
| `invalid_payload` | Invalid relay wire payload | `false` | Fix request; do not replay unchanged |
| `wrong_coin_type` | Not a configured TRC-20 | `false` | Use Standard rail |
| `runtime_missing` | GasFree runtime not configured | `false` | Reconfigure |
| `chain_id_mismatch` | Wrong network | `false` | Security/configuration failure |
| `verifying_contract_mismatch` | Wrong TIP-712 domain | `false` | Security failure |
| `service_provider_mismatch` | Provider differs from pin | `false` | Security failure |
| `token_mismatch` | Token differs from active contract | `false` | Security failure |
| `invalid_address` | Malformed address | `false` | Fix request |
| `custody_address_mismatch` | Wrong CREATE2 account | `false` | Security failure |
| `signature_mismatch` | Signature/fingerprint invalid | `false` | Security failure |
| `wallet_ownership_mismatch` | Signer not active wallet | `false` | Security failure |
| `authorization_expired` | Deadline elapsed | `false` | Generate a new preview/authorization |
| `pending_transfer` | Provider allows no new submission | `false` | Reconcile existing transfer |
| `provider_rejected` | Definite provider rejection | `false` | Correct request; classify by stable reason |
| `authentication_rejected` | Proxy/provider auth failed | `false` | Configuration failure |
| `rate_limited` | Definite 429 rejection | `false` | Retry later with a new status check |
| `provider_unavailable` | Failure proved before POST | `false` | Retry later |
| `provider_timeout` | Timeout proved before POST | `false` | Retry later |
| `submission_outcome_unknown` | Submit POST outcome ambiguous | omitted | Block resubmission; reconcile/support |
| `provider_response_mismatch` | Invalid provider/preflight response proven before submit POST | `false` | Security failure |
| `accepted_response_mismatch` | Trace ID returned but response mismatched | `true` | Persist trace and reconcile; never replay |
| `internal` | KDF cannot prove financial outcome | omitted unless proven | Block replay until resolved |

Semantics:

- `retryable=true` means a caller may retry the operation described by the
  error after its condition changes. It never permits replaying an expired or
  potentially accepted signed payload.
- A timeout, disconnect, malformed body, upstream 5xx, or proxy failure during
  the submit POST MUST produce `submission_outcome_unknown` unless KDF has
  definitive pre-acceptance rejection evidence.
- A malformed or mismatched submit response without a usable trace ID is also
  `submission_outcome_unknown`; KDF MUST NOT reuse the pre-submit
  `provider_response_mismatch` code for an ambiguous POST outcome.
- `relay_accepted` MUST be omitted when unknown. It MUST NOT default to false.
- Raw provider bodies and provider exception strings MUST NOT appear in the
  envelope.

Provider rejection reasons SHOULD be normalized from the official error set:

```text
provider_address_not_match
deadline_exceeded
invalid_signature
unsupported_token
too_many_pending_transfers
version_not_supported
nonce_not_match
max_fee_exceeded
insufficient_balance
```

## 13. Trace status and finality

### KDF-GF-012 — `gasless::trace_status` — Release blocker

Request:

```json
{
  "mmrpc": "2.0",
  "method": "gasless::trace_status",
  "params": {
    "coin": "USDT-TRC20",
    "trace_id": "provider-trace-uuid",
    "expected_authorization": {
      "request_id": "uuid-v4",
      "account": "T...",
      "custody_address": "T...",
      "provider": "T...",
      "receiver": "T...",
      "token": "T...",
      "amount": "10000000",
      "max_fee": "2000000",
      "deadline": "1780000000",
      "version": "1",
      "nonce": "9",
      "signature_fingerprint": "sha256-hex"
    }
  }
}
```

Response:

```json
{
  "state": "confirmed",
  "tx_hash_on_chain": "...",
  "block_height": 76543210,
  "confirmed_at": 1780000123,
  "final_fee": "1.5",
  "failure_reason": null
}
```

KDF state projection MUST be:

```text
pending
submitted
on_chain
confirmed
failed
```

`confirmed` requires provider `txnState=SOLIDITY`, not merely initial chain
inclusion. `failed` is terminal only when the provider supplies an authoritative
failure state.

### KDF-GF-013 — Trace response binding — Release blocker

Every trace response MUST be bound to the persisted authorization context.
KDF MUST validate:

- trace ID;
- request ID when present;
- canonical EOA and custody address;
- pinned provider;
- receiver;
- token;
- amount;
- nonce;
- expiry;
- maximum fee and version when present;
- signature fingerprint and signature recovery when a signature is present;
- estimated and final fee not exceeding the signed maximum;
- actual recipient amount equals the originally authorized amount;
- activation fee plus transfer fee equals total fee when all are present;
- total cost equals amount plus total fee;
- state and transaction-state combinations are internally consistent.

A confirmed response MUST include transaction hash, block height, confirmation
timestamp, final fee, final amount, and total cost. Missing or inconsistent
confirmation data is a typed response-mismatch security failure.

Unknown provider states MUST fail deserialization. KDF MUST accept provider
timestamps as RFC3339, epoch seconds, or exact epoch milliseconds and normalize
`confirmed_at` to epoch seconds.

### KDF-GF-014 — Polling and streaming — V2 release blocker

The one-shot status RPC is mandatory and is the recovery authority after an
app or KDF restart. SSE streaming is optional but, if provided, MUST:

- use the configured poll interval;
- apply bounded exponential backoff and jitter after retryable errors;
- emit the initial status and meaningful state changes only;
- never regress a trace from a later state to an earlier state;
- stop polling terminal states;
- report exhausted polling as unknown/pending, not failed;
- validate every response exactly as the one-shot RPC does.

## 14. Security and privacy — V2 provider-bound profile

### KDF-GF-015 — Secret handling — V2 release blocker

KDF MUST NOT log, serialize into errors, or expose through `Debug`/`Display`:

```text
api_key
api_secret
Authorization headers
HMAC signatures
mnemonics, seeds, private keys, passwords, userpass
raw signed authorization
raw signature
tx_json relay payload
tx_hex
raw provider or proxy bodies
```

Requirements:

- Provider configuration and relay payload types MUST implement explicit
  redacted debug formatting or omit `Debug` entirely.
- Redaction MUST be recursive for nested maps and lists and MUST recognize
  snake_case, kebab-case, and camelCase secret keys.
- Sanitization MUST NOT mutate the actual request transmitted to KDF/provider.
- Error conversion MUST preserve category and stable code while discarding raw
  upstream content.
- Request and trace IDs MAY appear as non-secret correlation identifiers.
- Wallet addresses and raw financial amounts SHOULD be omitted from logs unless
  a narrowly scoped, explicitly approved diagnostic mode requires them.
- Live integration credentials MUST come from CI/local environment secrets.
  They MUST NOT be committed as Rust constants, fixtures, documentation values,
  or example defaults.

## 15. Compatibility requirements

### KDF-GF-016 — Existing rails — Both profiles

- Native TRX and native TRC-20 withdrawal behavior MUST remain unchanged when
  `fee_method` is omitted or equals `native`.
- Existing `tx_hex` submission MUST remain unchanged.
- Structured `tx_json` interception MUST be opt-in by an exact relay-type tag.
- Non-GasFree JSON broadcasters, including Sia, MUST retain their existing
  behavior and error contract.
- GasFree-specific logic MUST remain inside the TRON/TRC-20 branch.
- Unsupported platforms MUST return typed unsupported errors rather than panic.
- RPC, activation, provider, and wallet paths MUST NOT introduce caller-
  reachable `unwrap()` or `expect()` calls. Any genuinely infallible invariant
  must be documented at the call site and covered by a test.

### KDF-GF-017 — Wire compatibility — Both profiles

- New request types MUST deny unknown fields where they carry signed or
  security-sensitive data.
- Optional response fields may be omitted only when absence has defined
  semantics.
- Relay payloads MUST include an explicit wire version before any future
  payload shape change.
- Changing a signed field, state name, error code, or amount representation is a
  breaking API change and requires coordinated SDK versioning.

## 16. Required automated tests

Every defect boundary MUST have a regression test. Shared pure logic SHOULD use
`cross_test!` unless target-specific behavior is documented.

### 16.1 V1 status-attested opening tests

The V1 KDF candidate MUST cover:

- ready status with explicit `availability: available` and no legacy
  `provider_available` or `reason_code` fields;
- every explicit availability value;
- pending transfer never reporting fees, spendable balance, or a positive
  maximum;
- locally read custody total retained for token-unsupported and
  provider-unreachable responses;
- token-unsupported and provider-unreachable responses clearing every
  provider-derived status, frozen, spendable, fee, maximum, and provider field;
- non-available responses with even an empty `service_provider` field rejected
  as an invalid wire shape rather than treated as routine degradation;
- exact typed `TokenDecimalsMismatch`, `CustodyAddressMismatch`, and
  `ProviderIdentityMismatch` errors with safe HTTP mappings;
- exact configured provider offered and echoed as `service_provider` in a ready
  response;
- configured provider absent from a non-empty list, empty provider list, and
  provider-list outage never substituting or falling back to another provider;
- `service_provider: null` on every non-available response;
- RFC3339, epoch-second, and epoch-millisecond provider timestamps;
- `confirmed_at` normalized to epoch seconds;
- submit/trace created, updated, and expiry integer units preserved for
  compatibility;
- malformed and out-of-range timestamp rejection;
- no new request, fingerprint, or envelope fields in the strict legacy
  `tx_json` fixture;
- Standard TRX/TRC-20 withdrawal and non-GasFree JSON broadcaster regressions;
- native and WASM compilation of the changed parser/status path; and
- immutable artifact version/checksum verification for every declared target,
  including Android armv7 and Android arm64.

The strict signed legacy `tx_json` request fixture MUST deny unknown fields.
Provider response fixtures MAY tolerate additive metadata but MUST assert every
required field and degraded null/omission semantic.

### 16.2 V2 configuration and capability

- mainnet/Nile chain ID and verifying-contract vectors;
- HTTPS, URL credentials, query, fragment, malformed path, and HTTP opt-in;
- timeout and polling lower/equality/upper boundaries;
- production provider pin required;
- discovery false by default and explicit development opt-in;
- direct HMAC explicit opt-in and empty credential rejection;
- provider pin match and mismatch;
- exact token contract and decimal match;
- unsupported/custom/wrong-network token rejection;
- HD primary, HD secondary, change, Iguana, Trezor, WalletConnect, and MetaMask
  eligibility matrix;
- active-runtime reconfiguration success, partial-failure atomicity, duplicate
  token, empty list, and provider-rotation rejection.

### 16.3 V2 preview and signing

- official TIP-712 domain and permit hash/signature vectors;
- exact source ownership and derivation;
- zero, frozen, partially frozen, exact-fee, and below-fee balances;
- active versus first-transfer activation fee;
- provider deadline minimum/default/maximum, expiry, and overflow;
- request cap versus runtime cap;
- `max=true` authoritative calculation;
- `fallback_to_native=false` never returns a native fee/result;
- all GasFree withdraw error variants serialize deterministically.

### 16.4 V2 submission

- duplicate local submissions are serialized per EOA;
- account status rechecked immediately before POST;
- tampered chain, verifying contract, provider, token, EOA, custody address,
  receiver, amount, maximum fee, deadline, version, nonce, signature, request
  ID, and fingerprint are rejected before POST;
- submit-response mismatch for every echoed field;
- estimated fee lower/equal/higher than maximum;
- definite provider rejection versus ambiguous transport/timeout/5xx;
- typed envelope status, code, retryability, terminality, and
  `relay_accepted` presence/absence;
- accepted response mismatch preserves only request ID, trace ID, and field.

### 16.5 V2 trace and finality

- every trace identity-field mismatch;
- optional echo validation;
- fee lower/equal/higher than maximum;
- final fee component reconciliation;
- recipient amount preservation;
- transaction total-cost reconciliation;
- all transfer/transaction state cross-products;
- confirmation metadata requirements;
- RFC3339/seconds/milliseconds timestamp acceptance and epoch-second
  normalization;
- unknown enum state and malformed payload rejection;
- backoff, jitter bounds, repeated transport errors, late confirmation, and
  terminal stop behavior.

### 16.6 V2 security

- recursive secret redaction without request mutation;
- no credential, signed payload, signature, wallet key, raw body, URL secret,
  or raw financial payload in logs/errors;
- native, remote, and WASM transport error-path parity;
- repository secret scan, including live-test fixtures.

## 17. Required validation commands

### 17.1 V1 status-attested release gate

Run the current stable toolchain against the complete V1 delta from
`bfd7f7ee…` and its RPC path:

```bash
cargo fmt --all -- --check

cargo test -p coins gasfree --lib
cargo test -p mm2_main --lib gasless --features utxo-walletconnect

cargo clippy -p coins -p mm2_main --lib -- -D warnings
cargo check -p coins -p mm2_main
cargo check --target wasm32-unknown-unknown -p coins -p mm2_main
```

The release report MUST also include successful immutable builds for Web/WASM,
iOS arm64, macOS universal, Android armv7, Android arm64, Linux x86-64, and
Windows x86-64 from one exact full SHA.

The observed CI tip serializes Android Cargo compilation only in the dev
workflow; the release workflow currently receives longer timeouts only. Both
release Android jobs MUST complete successfully. If either still exhausts the
runner, equivalent serialization MUST be applied to the release workflow before
artifact promotion.

### 17.2 V2 provider-bound gate

Run the narrow-to-broad V2 gates:

```bash
cargo fmt --all -- --check

cargo test -p coins gasfree
cargo test -p mm2_main --lib gasless --features utxo-walletconnect
cargo test -p coins_activation --lib eth_with_token_activation --features for-tests

cargo clippy -p coins -p mm2_main -p coins_activation --lib -- -D warnings
cargo check -p coins -p mm2_main -p coins_activation
cargo check --target wasm32-unknown-unknown \
  -p coins -p mm2_main -p coins_activation
```

If a broader repository baseline prevents a bare command, the PR must document
the unrelated baseline and run the narrowest feature set that compiles the full
changed path. No GasFree-specific failure may be waived as baseline noise.

## 18. Live Nile validation

All live validation MUST use environment-provided credentials and funded Nile
wallets. Tests sharing an account MUST be serialized because the official
provider currently permits one pending authorization per account.

### 18.1 V1 status-attested opening

Using both an empty canonical Nile wallet and a wallet with existing GasFree
custody state, validate:

- full and balance-only account-status presentation;
- exact pinned provider echo, provider-list mismatch, provider outage, and no
  silent provider substitution;
- core-wallet QR/copy opening only for a fresh, complete, status-attested
  canonical address;
- duplicate candidates, secondary derivations, stale remote control, wallet
  switch, and the remote kill switch closing QR/copy immediately while leaving
  balance and recovery visible;
- runtime-not-configured restart guidance without synthetic readiness;
- explicit-amount and maximum legacy preview;
- exact signed-preview provider equality before submission;
- first-transfer activation fee when applicable;
- legacy relay acceptance and immediate trace persistence;
- RFC3339, epoch-second, and epoch-millisecond confirmation inputs through
  controlled proxy or fixture fault injection;
- late confirmation after a polling outage;
- an ambiguous submit outcome induced through controlled transport fault
  injection and remaining non-retryable;
- exact raw on-chain reconciliation of token, custody source, recipient,
  authorized amount, final fee maximum, and transaction hash;
- unsupported token, wrong network, secondary derivation, and provider outage
  falling back safely to Standard TRON or recovery; and
- Bitrefill refund selection and consolidation remaining bound-relay-only.

### 18.2 V2 provider-bound release

Validate:

- first activation and already-active runtime configuration;
- authoritative account status;
- explicit amount and maximum withdrawal;
- first-transfer activation fee;
- relay submit and immediate trace persistence data;
- on-chain and solidified confirmation;
- pending-transfer rejection;
- expired authorization;
- provider outage before submit;
- ambiguous submit outcome;
- late confirmation after polling outage;
- unsupported token, wrong network, provider mismatch, and secondary address;
- native TRON regression alongside GasFree tests;
- native and WASM/provider-proxy parity.

Mainnet validation is limited to configuration, authenticated proxy access,
token enrollment, provider pin, account status, and read-only health checks.
Real-value mainnet transfers require separate written approval.

## 19. Artifact and delivery requirements

### 19.1 V1 immutable artifacts — V1 release blocker

The V1 artifact candidate is the reviewed implementation of this document on
top of `bfd7f7ee30deed4e02b87347e19426b52017d580`. The KDF team MUST:

1. identify the final full release SHA;
2. build Web/WASM, iOS arm64, macOS universal, Android armv7, Android arm64,
   Linux x86-64, and Windows x86-64 from that same SHA;
3. publish every archive through a location available to clean CI and developer
   environments;
4. calculate and publish an independent SHA-256 for each archive;
5. prove each runtime reports the final full SHA and exposes the same V1
   provider-attested account-status and timestamp contract; and
6. provide the complete manifest before the SDK artifact pin is changed.

No prebuilt local V1 follow-up commit or artifact exists. The final reviewed
descendant of `bfd7f7ee…` becomes the sole V1 artifact identity. The
compatibility SDK remains pinned to the last fetchable artifact commit,
`997332e5d6b0c5ca471aa7dc9727a7be96938ae2`, until all V1 release archives
and checksums are published. Existing artifacts MUST NOT be relabeled as
artifacts for the future V1 implementation SHA.

Android armv7 and Android arm64 are immediate V1 release blockers. A local
binary override is never a release input. All-zero or placeholder checksums are
invalid.

### 19.2 KDF-GF-018 — V2 immutable artifacts — V2 release blocker

After code review and tests:

1. Commit the complete KDF implementation.
2. Build every platform from that exact full commit SHA.
3. Publish artifacts for:
   - Web/WASM;
   - iOS arm64;
   - macOS universal;
   - Android armv7;
   - Android arm64;
   - Linux x86-64;
   - Windows x86-64.
4. Calculate SHA-256 independently for each downloaded archive.
5. Update the SDK build configuration with the full KDF SHA and exact checksum
   allowlist.
6. Download each artifact through the same transformer path used by CI and
   verify its checksum and runtime version.
7. Prove every artifact reports the same KDF commit and exposes the same RPC and
   error contracts.

All-zero checksums are V2 release blockers and MUST never be treated as valid.
Artifacts built from an earlier commit MUST not be relabeled or reused.

Promotion order is strict for each release profile:

1. publish the selected KDF commit and the complete checksum manifest;
2. update, validate, and publish the SDK reference;
3. update the Gleec Wallet submodule pointer and publish the app branch.

Publishing the main repository before the referenced SDK commit is reachable
would leave CI and fresh clones unable to resolve the dependency and is not
permitted.

## 20. Acceptance criteria

### 20.1 V1 status-attested opening acceptance

The V1 KDF implementation is accepted when all of the following are true:

- The candidate is a descendant of
  `bfd7f7ee30deed4e02b87347e19426b52017d580` and implements the complete V1
  behavior in section 2.2.
- Exact configured provider selection is proven; mismatch, empty discovery,
  and outage never substitute or fall back to another provider.
- Available status echoes the exact provider and every non-available status
  clears it.
- Pending transfer, unsupported token, and provider-unreachable status never
  expose fees, spendable balance, or a maximum as usable.
- Decimal, custody, and provider identity mismatches are stable typed hard
  errors and never produce receive/spend readiness.
- RFC3339, epoch-second, and epoch-millisecond inputs are accepted and
  `confirmed_at` is normalized to epoch seconds.
- The strict legacy `tx_json` and Standard TRON rails have no breaking change.
- The focused initial tests, formatting, clippy, native checks, and WASM checks
  are green.
- Funded and empty-wallet Nile validation for status-attested core receive and
  the constrained legacy send flow passes.
- Every declared platform artifact exists, reports one immutable full SHA, and
  matches a non-placeholder checksum; Android armv7 and arm64 are included.

Production enablement of the V1 profile additionally requires the
downstream SDK, app, proxy, and release-owner teams to confirm:

- The SDK team validates available, all three non-available, and all three hard
  mismatch RPC fixtures, mixed old/new wire rejection, out-of-order probe
  completion, and wallet-switch error completion before updating the KDF
  artifact pin.
- The app opens core-wallet GasFree QR/copy only with status-attested V1 or
  bound-relay V2 evidence plus fresh remote authorization. Bitrefill and
  consolidation remain bound-only. Standard TRON, custody visibility,
  unresolved activity, and recovery remain available in every state.
- Operational evidence proves the production Gleec proxy returns only stable
  sanitized errors and correlation IDs; direct provider/HMAC mode and raw relay
  diagnostics remain disabled.
- Release owner explicitly accepts the residual legacy relay ambiguity
  and KDF redaction limitation described in section 2.3.

V1 does **not** require the V2 items in section 20.2.

### 20.2 V2 provider-bound acceptance

The V2 KDF delivery is accepted only when all of the following are true:

- Every V2-scoped MUST in sections 3–19 is implemented.
- No GasFree request can silently become a native TRON transfer in the Gleec
  production configuration.
- No unsupported wallet, token, network, provider, or derivation can sign or
  submit a GasFree authorization.
- The app can distinguish definite pre-relay rejection, accepted relay,
  ambiguous outcome, confirming, confirmed, and authoritative final failure
  without parsing display strings.
- Submit and trace responses are cryptographically and semantically bound to
  the original signed request.
- Final fee cannot exceed the signed maximum.
- Provider outage never substitutes an EOA balance for custody balance.
- No secret or signed payload is exposed in logs, errors, fixtures, or support
  data.
- Focused tests, clippy, native checks, and WASM checks are green.
- Funded Nile validation passes.
- Every declared platform artifact exists, matches the same immutable commit,
  and has a non-placeholder checksum.
- The SDK team has validated the final RPC fixtures against generated Dart
  models before the KDF SHA is pinned.

## 21. Deliverables expected from the KDF team

### 21.1 V1 status-attested opening

- Reviewable Conventional Commit changesets directly descended from
  `bfd7f7ee30deed4e02b87347e19426b52017d580`.
- `gasless::account_status` fixtures for `available`, `pending_transfer`,
  `token_unsupported`, and `provider_unreachable`, including exact
  `service_provider` and nullability semantics.
- Typed error fixtures for `TokenDecimalsMismatch`,
  `CustodyAddressMismatch`, and `ProviderIdentityMismatch`.
- Provider evidence for exact match, missing configured pin, empty list,
  provider outage, and no silent substitution/fallback.
- RFC3339, epoch-second, and epoch-millisecond submit and trace fixtures with
  normalized `confirmed_at` output.
- Focused unit/RPC, native, WASM, clippy, and Standard-rail regression evidence.
- Empty-wallet and funded Nile evidence for status-attested core receive plus
  the guarded legacy send flow.
- Published archives and an independent SHA-256 manifest for every supported
  platform, including Android armv7 and Android arm64.
- The final full immutable KDF SHA that the SDK may pin.
- A short release note stating that V1 includes core-wallet receive attestation
  but excludes `gasless::configure`, bound request envelopes, submit/trace
  lifecycle binding, and KDF-side canonical-wallet enforcement.

### 21.2 V2 provider-bound release

- One or more reviewable Conventional Commit changesets implementing this
  specification's V2 requirements.
- Updated KDF API documentation and request/response fixtures.
- Unit, RPC serialization, native, WASM, and Nile integration tests.
- A short threat-model note covering provider compromise and ambiguous submit
  outcomes.
- A CI run or signed test report for the required gates.
- Published artifacts and SHA-256 manifest for every supported platform.
- The full immutable KDF commit SHA to pin in the Flutter SDK.
- A migration note for any changed wire shape or error code.

## 22. External references

- [GasFree developer documentation](https://docs.gasfree.io/)
- [Official unsupported-token recovery page](https://gasfree.io/withdraw)
- [TronLink GasFree user guide](https://support.tronlink.org/hc/en-us/articles/38903684778393-GasFree-User-Guide)
