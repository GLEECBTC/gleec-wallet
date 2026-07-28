# TRON GasFree receive control

New GasFree custody receive addresses are exposed only when all of the
following checks pass:

1. The fail-closed `TRON_GASLESS_ENABLED` kill switch was explicitly enabled.
2. The fail-closed `TRON_GASLESS_RECEIVE_ENABLED` kill switch was explicitly
   enabled.
3. The provider URL, network, token identity, and pinned service-provider
   address pass the local allowlist.
4. `TRON_GASLESS_CONTROL_URL` is configured and its fresh `receiveEnabled`
   document explicitly enables Receive. An empty URL or unavailable/stale
   control document fails closed.
5. KDF's `gasless::account_status` returns a fresh `availability: available`
   status for the canonical token, with the exact configured
   `service_provider`, the expected KDF custody address, and the complete
   available-state balance and fee shape.
6. The wallet/configuration epoch and canonical primary software-wallet
   derivation still match when the asynchronous status call completes and when
   the user invokes QR or copy.

Any failed or unknown check disables **new GasFree receives**. It does not hide
an existing custody balance, a pending transfer, retained Standard addresses,
or recovery actions authorized by their own current checks.

## KDF contract

The GUI performs no CREATE2 derivation, TIP-712 operation, or direct provider
request. `gasfree_address` is opaque KDF output: KDF derives it and hard-fails a
reachable provider/custody mismatch. Flutter binds the completed request to the
current wallet/configuration epoch and only performs ordinary field, amount,
and freshness checks.

Only `availability: available` authorizes new QR/copy. A
`pending_transfer` response keeps its provider, balances, and fee information
visible but blocks new receives. `token_unsupported` keeps the provider
identity and enables Standard/recovery guidance. `provider_unreachable` keeps
the fresh on-chain custody total visible while provider-derived spendability
and fees remain unknown.

`ProviderIdentityMismatch`, `GasfreeAddressMismatch`, and
`TokenDecimalMismatch` are hard security failures. They must never be rendered
as an empty or temporarily unavailable account. The superseded
`provider_available` and `reason_code` response fields are rejected.

Every send still requires a fresh KDF withdrawal preview with
`fallback_to_native: false`; the status fee and maximum are display estimates
only.

## Release workflow gate

The reusable build action exposes a primary GasFree kill switch and an
additional receive kill switch. Builds may explicitly set either switch to
`false`, but Receive cannot be enabled unless the primary GasFree switch is
also enabled. Enabled builds require complete, valid provider configuration.

The public mainnet proxy URL and provider pin are version-controlled in the
GasFree preview workflows. They are deliberately not GitHub repository
variables: changing either identity is security-sensitive and must leave a
reviewed source diff. The release master must pass the same values explicitly
to a manual CI-server build, as documented in
[`TRON_GASFREE_KDF_HANDOVER.md`](TRON_GASFREE_KDF_HANDOVER.md).

The feature switches and Receive control URL remain operational inputs. A
Receive-enabled build must also pass a real `TRON_GASLESS_CONTROL_URL`.
Feature-switch defaults do not waive artifact provenance, provider binding,
canary, or Product/Design approval requirements.

## Endpoint contract

The endpoint must be HTTPS, must not redirect, and must not contain credentials,
query parameters, fragments, encoded path components, or dot segments. It must
return HTTP 200 with `Content-Type: application/json` and a body no larger than
4 KiB. Flutter web builds also require CORS permission for the wallet origin.

The JSON object has exactly these fields; additional or missing fields fail
closed:

```json
{
  "schemaVersion": 1,
  "receiveEnabled": true,
  "expiresAt": "2026-07-10T12:02:00Z",
  "network": "tron",
  "serviceProvider": "TLntW9Z59LYY5KEi9cmwk3PKjQga828ird"
}
```

- `schemaVersion` must be the integer `1`.
- `receiveEnabled` must be a boolean.
- `expiresAt` must be a canonical UTC timestamp, strictly in the future, and no
  more than five minutes ahead of the client clock.
- `network` must exactly match the configured provider path: `tron` or `nile`.
- `serviceProvider` must exactly match the production-pinned TRON address.

Serve the response with `Cache-Control: no-store`. The client revalidates every
30 seconds while the receive surface is foregrounded and again immediately
after the current document or 60-second KDF status window expires.
Transport failure, timeout, non-200 status, malformed JSON, expiry, or binding
mismatch removes the custody address from copy/QR/refund selection while the
existing custody row remains visible.

## Rollback

Set `receiveEnabled` to `false` with a fresh expiry. Clients currently viewing
the receive screen will disable new custody receives on their next revalidation
(within 30 seconds). Leave the build-level send/recovery configuration in place
so existing custody balances and unresolved transfers remain visible. Recovery
or consolidation remains available only when its own typed KDF state and fresh
action-time checks authorize it; provider outage or a hard-security state does
not itself prove that either action is safe. Neither action authorizes a new
GasFree submission.
