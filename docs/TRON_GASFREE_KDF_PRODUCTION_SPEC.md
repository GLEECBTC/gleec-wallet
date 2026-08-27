# TRON GasFree production contract

Status: current release contract

Last updated: 2026-07-24

KDF source: `bd413dcfea73c9de2e85903323946a378b180fa7`

KDF documentation: `d175558a6c5d33a4f7ce4843227f0b54cc3dbc9b`

This document defines the contract consumed by Gleec Wallet and the nested
Komodo DeFi Flutter SDK. Historical V0/V1/V2 rollout proposals are retained in
git history at `ca0212a1b31b` under `docs/archive/gasfree/`; they are historical hand-off notes, not runtime specifications.

## Product invariants

- GasFree applies only to the reviewed TRC20 wallet rail. Standard TRON remains
  available when GasFree is disabled, unsupported, or temporarily unavailable.
- Production always supplies a pinned `service_provider` and requires exact
  equality whenever KDF returns provider identity.
- The app never contains GasFree API credentials. Production uses
  `komodo_proxy` over HTTPS.
- GasFree Send always requests `fallback_to_native: false`. A native preview
  returned for that request is rejected before submission.
- New GasFree Receive QR/copy is exposed only for a fresh `available` status,
  the canonical wallet address, the exact network/token/contract allowlist, and
  a valid local and remote policy decision.
- Existing custody balances, Standard addresses, unresolved transfers, and
  recovery/consolidation routes authorized by their own current checks remain
  visible when new GasFree actions are disabled.
- A submission that may have reached the provider is never blindly retried.
- Signed authorization and signatures are never persisted or logged.

## Activation

The TRON platform activation carries:

```json
{
  "tron_gasless_provider": {
    "base_url": "https://…",
    "service": "komodo_proxy",
    "service_provider": "T…",
    "request_timeout_ms": 10000,
    "status_poll_interval_ms": 3000
  }
}
```

`service_provider`, `request_timeout_ms`, and `status_poll_interval_ms` are
optional in the generic SDK. Gleec production requires `service_provider`.
GasFree-enabled tokens carry:

```json
{
  "gasless": {
    "enabled": true,
    "transfer_max_fee": "optional token amount"
  }
}
```

Provider discovery is owned by KDF and cached for the activation lifetime.
Changing or adding a provider requires ordinary token/platform reactivation;
there is no `gasless::configure` RPC.

## Account status

`gasless::account_status` accepts `{ "coin": "<ticker>" }`. Every successful
response includes `gasfree_address`, `on_chain_balance`, and one required
`availability` value:

| Availability | Provider | Provider balance/fee fields | Maximum |
| --- | --- | --- | --- |
| `available` | present | present; zero activation fee may be omitted | present |
| `pending_transfer` | present | present | absent |
| `token_unsupported` | present | absent | absent |
| `provider_unreachable` | absent | absent; on-chain total remains fresh | absent |

Only `available` authorizes Receive or Send. `pending_transfer` retains useful
balance and fee information but blocks a new transfer. `token_unsupported`
offers Standard/recovery actions. `provider_unreachable` keeps the fresh
on-chain custody total visible while spendability is unknown.

The client recognizes the exact hard errors emitted by this KDF revision,
including `ProviderIdentityMismatch`, `GasfreeAddressMismatch`, and
`TokenDecimalMismatch`. Identity/address/decimal mismatches are security states,
not degraded availability.

The superseded `provider_available`, `reason_code`, and mixed legacy/current
responses are rejected.

## Preview and submission

A GasFree preview uses:

```json
{
  "fee_method": "gasless",
  "gasless": {
    "max_fee": "optional token amount",
    "deadline_seconds": 300,
    "fallback_to_native": false
  }
}
```

Maximum withdrawal sends `"max": true` and omits `amount`. KDF's fresh preview
is the authority for the signed recipient amount and fee; account-status
`max_withdrawable` is display-only.

The relay payload contains exactly:

- `relay_type`
- `chain_id`
- `coin`
- optional `hd_from`
- `from_address`
- `gasfree_address`
- `verifying_contract`
- `signed_authorization`
- `created_at`

`send_raw_transaction` returns only `relay_type`, `trace_id`, and the provider
submission `state`. The wire has no request ID, authorization fingerprint, or
expected-authorization echo. Plain-string submission errors become a safe
generic submission failure unless local typed validation can prove a more
specific category.

Preview fee details contain the provider name, custody address, transfer and
activation fees, total token fee, signed maximum fee, and the documented null
`trace_id` placeholder. Final fee and finality come from trace status.

## Trace and recovery

Before submission the SDK enables:

```text
stream::gasless_trace::enable { coin, client_id? }
```

The streamer ID is `GASLESS_TRACE:<coin>`. Success events use
`GASLESS_TRACE:<coin>` and error events use
`ERROR:GASLESS_TRACE:<coin>`. After KDF accepts the relay, the SDK persists the
`trace_id`, immediately performs one `gasless::trace_status` reconciliation,
and then follows stream events filtered by coin and trace ID.

Trace states are `pending`, `submitted`, `on_chain`, `confirmed`, and `failed`.
`confirmed_at` is Unix seconds. `gasless::trace_status` is the restart and
disconnect recovery path and accepts only `coin` and `trace_id`.

The encrypted wallet-scoped journal uses a local `journalId` for its
pre-submission reservation. It is never sent to KDF. Accepted entries are
reconciled by trace ID. Migrated records without a trace remain
`submissionOutcomeUnknown` and non-resubmittable until resolved manually.

## Application gates

The existing build and remote Receive switches remain kill switches. They do
not replace KDF status or provider validation. QR/copy is revalidated at action
time and revoked when policy, wallet epoch, address, provider, or status
freshness changes.

The production allowlist remains exact:

- mainnet `USDT-TRC20`, platform `TRX`, contract
  `TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t`;
- Nile `TESTUSDT-TRC20`, platform `TRXT`, contract
  `TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf`;
- canonical primary software-wallet derivation only.

The Gleec product keeps Trezor GasFree actions excluded because the current
permit-signing path cannot extract the required device key. Generic KDF
activation and read-only account status are not suppressed by the SDK.

## Release gate

- All seven platform artifacts and provenance markers identify the full KDF
  source commit above and their exact archive and extracted-core hashes.
- Root and changed SDK packages pass static analysis after formatting.
- Contract fixtures cover the four status shapes, exact wire requests,
  submission/trace parsing, fallback discrimination, Max, journal migration,
  wallet races, and Standard withdrawal regression.
- Nile canary covers activation, empty/funded status, preview, submission,
  streaming, restart recovery, provider outage, remote Receive revocation,
  Standard access, and external custody deposit refresh.
- A real mainnet transfer requires separate explicit authorization.
