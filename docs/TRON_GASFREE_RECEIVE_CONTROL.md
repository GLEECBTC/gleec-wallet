# TRON GasFree receive control

New GasFree custody receive addresses are exposed only when all of the
following checks pass:

1. `TRON_GASLESS_ENABLED=true` was set at build time.
2. `TRON_GASLESS_RECEIVE_ENABLED=true` was set at build time.
3. The provider URL, network, token identity, and pinned service-provider
   address pass the local allowlist.
4. `TRON_GASLESS_CONTROL_URL` returns a fresh `receiveEnabled: true` document.
5. The SDK's authoritative GasFree account-status call confirms the provider
   is available and returns the canonical custody address.

Any failed or unknown check disables **new GasFree receives**. It does not hide
an existing custody balance, a pending transfer, retained Standard addresses,
or recovery actions.

## KDF contract requirement

The current PR #9 compatibility RPC does not return a provider identity from
`gasless::account_status`. The SDK can therefore use it only for provisional,
read-only custody recovery and for a user-initiated signed preview that proves
the provider pin before sending existing funds. It cannot safely authorize a
new receive address.

`receiveEnabled: true` takes effect only when the SDK has detected the bound
KDF contract and has authoritatively verified the exact provider, token,
network, wallet, primary derivation, and custody address. Against legacy PR #9,
the application ignores an enabled remote document and keeps new GasFree
receives hidden.

## Release workflow gate

The reusable build action defaults both feature switches to `false`. Current
mobile, desktop, and web workflows intentionally inherit those defaults; this
keeps ordinary PR and release artifacts disabled while the bound KDF, Android
artifacts, and Operations evidence are unavailable.

An approved production rollout must explicitly pass environment-scoped values
for `TRON_GASLESS_ENABLED`, `TRON_GASLESS_RECEIVE_ENABLED`,
`TRON_GASLESS_BASE_URL`, `TRON_GASLESS_SERVICE_PROVIDER`, and
`TRON_GASLESS_CONTROL_URL` into the build action, and pass the expected
endpoint/provider values into the validation action. Do not use
repository-wide values that would silently enable untrusted pull-request
builds. The workflow wiring and its environment protection rules require
release-owner review and remain a release gate, not a safe default to commit
before rollout approval.

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

Serve the response with `Cache-Control: no-store`. The client revalidates at
least once per minute and again immediately after the current document expires.
Transport failure, timeout, non-200 status, malformed JSON, expiry, or binding
mismatch removes the custody address from copy/QR/refund selection while the
recovery row remains visible.

## Rollback

Set `receiveEnabled` to `false` with a fresh expiry. Clients currently viewing
the receive screen will disable new custody receives on their next revalidation
(within one minute). Leave the build-level send/recovery configuration in place
so existing custody balances and unresolved transfers remain accessible.
