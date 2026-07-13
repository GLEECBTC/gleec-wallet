# TRON GasFree KDF handover

Status: implementation handover

Immediate target: V1 status-attested receive opening

Implementation base: `bfd7f7ee30deed4e02b87347e19426b52017d580`

## Goal

Enable Gleec Wallet to show and copy one canonical GasFree custody address
safely, while retaining a separate V2 phase for full relay and runtime
hardening. This document is self-contained; no other local document is needed
to implement or accept the KDF work.

“V1” and “V2” below are Gleec release stages. They do not rename the official
GasFree protocol version.

| Stage | KDF outcome | GUI value |
| --- | --- | --- |
| V1 | `gasless::account_status` proves exact provider, custody address, token usability, and safe balance shape | Opens QR/copy on the core Receive screen for canonical wallets and fails closed everywhere else |
| V2 | KDF owns runtime configuration, provider enforcement, relay binding, lifecycle errors, and finality | Removes SDK/GUI compatibility workarounds and permits broader reviewed integrations |

## V1 product boundary

V1 receive is limited by the SDK and app to:

- canonical mainnet USDT or Nile TESTUSDT;
- the configured network and token contract;
- the pinned GasFree provider;
- a software wallet's canonical primary address; and
- the core wallet Receive screen.

Custom tokens, hardware wallets, secondary derivations, Bitrefill refunds,
consolidation, and other integrations remain on Standard TRON or require the
future bound-relay capability.

## Current KDF WIP

The reported KDF WIP is the correct V1 foundation: it introduces the four
`availability` states, removes spendability/fees/maximum from unusable states,
prevents pending transfers from looking healthy, and makes decimal and custody
mismatches hard errors. V1 receive must remain closed until that work also has
the exact provider selection/`service_provider` attestation, timestamp
compatibility, tests, and immutable artifacts required below.

## V1 required KDF changes

Implement these changes as a reviewed descendant of
`bfd7f7ee30deed4e02b87347e19426b52017d580`.

### 1. Make account availability explicit

`gasless::account_status` must return required `availability` with exactly one
of these values:

```text
available
pending_transfer
token_unsupported
provider_unreachable
```

The new response must not also contain the superseded `provider_available` or
`reason_code` fields. A mixed response is invalid.

### 2. Return a strict ready shape

Only `availability: available` authorizes GasFree receive or send readiness.
It must include:

- the locally derived `gasfree_address`;
- the locally read `on_chain_balance`;
- `active`;
- `frozen_balance`;
- `spendable_balance`;
- `transfer_fee`;
- `max_withdrawable`; and
- `service_provider`, exactly equal to the configured provider pin.

`activation_fee` may be absent/null only when `active` is `true`. If `active`
is `false`, `activation_fee` is required.

Example:

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

### 3. Preserve balances without claiming usability

For every non-available result:

- derive and return the local custody address;
- read and return its TRC-20 `on_chain_balance`;
- expose no spendable balance, fees, maximum, or provider identity; and
- never substitute the Standard EOA balance.

Required field matrix:

| Availability | `active` / `frozen_balance` | Spendable, fees, maximum | `service_provider` |
| --- | --- | --- | --- |
| `pending_transfer` | May retain trusted provider values | Null | Null |
| `token_unsupported` | Null | Null | Null |
| `provider_unreachable` | Null | Null | Null |

A pending transfer must never look healthy or expose a positive
`max_withdrawable`.

### 4. Treat identity mismatches as hard errors

These failures must be typed errors, not degraded success responses:

| `error_type` | Meaning |
| --- | --- |
| `TokenDecimalsMismatch` | Local token decimals differ from the provider contract |
| `CustodyAddressMismatch` | Provider account address differs from KDF's local derivation |
| `ProviderIdentityMismatch` | The configured provider is not the provider actually offered/resolved |

The error enum must derive `SerializeErrorType`, implement `HttpStatusCode`,
and serialize only stable, non-secret fields. Provider response bodies,
credentials, signed payloads, and raw transport errors must not be exposed.

Because a hard error has no successful balance payload, consumers retain the
last verified custody snapshot for recovery. They must not fall back to an EOA
balance.

### 5. Enforce the configured provider

When KDF has a configured provider pin:

- provider enrollment must offer that exact TRON address;
- KDF must not select the first provider or silently substitute another;
- an available response must echo the exact address in `service_provider`;
- a non-empty provider list that omits the pin is
  `ProviderIdentityMismatch`; and
- provider discovery outage or an empty result is
  `availability: provider_unreachable` with the local custody total and no
  provider-derived fields.

Automatic provider discovery is not a production fallback.

### 6. Normalize provider timestamps

Accept RFC3339, epoch seconds, and epoch milliseconds. Normalize public
`confirmed_at` to epoch seconds. Reject negative, fractional, malformed, and
overflowing values.

Provider `createdAt`, `updatedAt`, `expiredAt`, and `txnBlockTimestamp` may be
non-negative integers, decimal-integer strings, or RFC3339. Preserve numeric
units where the existing relay contract requires them.

### 7. Preserve V1 compatibility boundaries

V1 must not:

- add fields to PR #9's strict signed `tx_json`;
- silently downgrade GasFree withdrawal to Standard TRON;
- implement a synthetic successful `gasless::configure`; or
- alter Standard TRX/TRC-20 behavior.

`gasless::configure` is not required for V1. Its absence means an already
active runtime may require restart/reactivation before status-attested receive
can open.

## GUI behavior enabled by V1

| KDF result | Required GUI behavior |
| --- | --- |
| Complete `available` response with exact provider/address | Show GasFree QR/copy after wallet, token, network, freshness, and remote-control checks |
| `pending_transfer` | Show “transfer in progress”; retain balance/activity/recovery and block another GasFree action |
| `token_unsupported` | Keep custody recovery visible and use Standard TRON for normal actions |
| `provider_unreachable` | Show neutral temporary unavailability; retain custody balance/recovery and allow recheck |
| Any typed identity mismatch | Show a security state; hide QR/copy, fees, maximum, and retry paths that could create an unsafe deposit |

The app can disable new receives remotely without hiding existing custody
balances, pending transfers, Standard TRON, or recovery.

## V1 tests and acceptance

KDF must provide focused automated coverage for:

- all four availability values and their exact serialization;
- rejection of mixed new and legacy status fields;
- ready status with complete fields and exact `service_provider`;
- inactive ready status with and without `activation_fee`;
- pending transfer with no spendability, fees, or maximum;
- unsupported/unreachable status retaining only local custody identity/total;
- exact provider match, substitution rejection, empty discovery, and outage;
- typed decimal, custody, and provider mismatch errors, including serialized
  `error_type` and HTTP status;
- RFC3339, epoch-second, epoch-millisecond, malformed, negative, and overflow
  timestamps;
- unchanged strict `tx_json` fixtures; and
- Standard TRX/TRC-20 regressions.

Use typed response/error structs. Test-side wire mirrors should use
`#[serde(deny_unknown_fields)]`. Shared parsing logic should use `cross_test!`
unless a platform-specific reason is documented.

Acceptance also requires:

- `cargo fmt` and relevant clippy checks;
- focused native tests and the affected RPC-layer tests;
- WASM compilation of the changed path;
- funded Nile validation for ready, pending, unsupported, provider outage,
  decimal mismatch, custody mismatch, and provider mismatch; and
- read-only mainnet validation of configuration, enrollment, provider pin, and
  account status. No real-value mainnet transfer is authorized by this handover.

## V1 artifacts and promotion

Build every declared artifact from the same final descendant of
`bfd7f7ee30deed4e02b87347e19426b52017d580`:

- Web/WASM;
- iOS arm64;
- macOS universal;
- Android armv7;
- Android arm64;
- Linux x86-64; and
- Windows x86-64.

Publish the full KDF commit SHA and independent SHA-256 checksum for every
artifact. Android armv7/arm64 are release blockers; placeholder or zero
checksums are invalid.

Promotion order is mandatory:

1. merge/publish KDF and immutable artifacts;
2. update and publish the Flutter SDK artifact pin; and
3. update and publish Gleec Wallet.

## V2 deferred hardening

V2 moves the remaining assurance into KDF:

- authoritative `gasless::configure` without restart;
- wallet-type and primary-derivation enforcement;
- provider pinning across status, signing, submission, and trace polling;
- KDF-issued request IDs and signed-payload fingerprints;
- submit/trace binding to provider, account, custody address, recipient, token,
  amount, nonce, version, deadline, signature context, and maximum fee;
- typed lifecycle, retryability, terminality, security, and configuration
  errors with redacted diagnostics;
- authorization-expiry handling and `final_fee <= signed_max_fee`;
- authoritative on-chain finality reconciliation; and
- native/WASM parity from one immutable KDF commit.

After V2 promotion, the SDK and GUI may remove the V1 restart fallback,
status-only receive flag, provider-string inference, and local correlation for
new transfers. Recovery access, remote kill switches, duplicate-send
protection, pending/unknown UI, and legacy pending-record support remain.

Protocol reference: [official GasFree documentation](https://docs.gasfree.io/).
