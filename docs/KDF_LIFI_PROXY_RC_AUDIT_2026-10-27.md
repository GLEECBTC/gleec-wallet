# KDP / KDF RC compatibility investigation — 27 October 2026

KDP here means **Komodo DeFi Proxy**, as confirmed by the user.

**No observed blocker requires updating the proxy's backend KDF to a newer RC.**
Fresh native and browser WASM checks through the deployed `https://quicknode.gleec.com/lifi`
route succeeded using the frozen wallet engine. The published main release and
the LiFi candidate have identical proxy-signature and peer-healthcheck contracts.
The deployed proxy revision, backend version and image digests remain unverified;
source inspection and successful requests do not establish deployment provenance.

## Three separate components

| Component | Inspected identity and responsibility |
|---|---|
| Wallet KDF | `35f0bde438eec2cb0471b19642b9d9c4602fa17d`, `3.1.1-beta_35f0bde`. Owns quoting, Max, funding, commission validation, approvals and execution. All seven platform pins remain unchanged. |
| KDP service | Production source branch `smk/gui-auth`, head `59c2a58bd278f6a91db63d81cc0521c2959644bd`. Verifies client signatures/peers, rate-limits requests and forwards LI.FI requests with the server-held API key. It does not execute routed swaps. |
| KDP's backend KDF | Used for startup `version` and `peer_connection_healthcheck` RPCs. The repository's Dockerfile uses the floating image `gleec/komodo-defi-framework:dev-latest`. That reference does not identify the running binary or an immutable release input. |

The [proxy README](https://github.com/GLEECBTC/komodo-defi-proxy/blob/59c2a58bd278f6a91db63d81cc0521c2959644bd/README.md),
[backend RPC adapter](https://github.com/GLEECBTC/komodo-defi-proxy/blob/59c2a58bd278f6a91db63d81cc0521c2959644bd/src/net/kdf_rpc_interface.rs)
and [backend Dockerfile](https://github.com/GLEECBTC/komodo-defi-proxy/blob/59c2a58bd278f6a91db63d81cc0521c2959644bd/kdf/Dockerfile)
establish these boundaries. Banxa and Ramp use the separate
`fiat-ramps.gleec.com` service, so a KDP backend upgrade does not repair Ramp's
rejected API credential or determine Banxa availability.

## Published RC versus the LiFi pin

At this check, main is `2023112fa67b28cbebc2a7064d22267fed40310f`, the
`v3.1.1-beta` release merge, with matching artifacts in the
[main directory](https://devbuilds.gleec.com/main/). There are no GitHub Release
objects in `kdf-internal` at this check. The
[LiFi build directory](https://devbuilds.gleec.com/feat-lifi-integration/) and
[KDF #29](https://github.com/GLEECBTC/kdf-internal/pull/29) still identify
`35f0bde` as the current LiFi head. No newer LiFi revision was found.

The branches diverge: main has six release-merge commits absent from the LiFi
branch; LiFi has 22 feature commits absent from main. Main is not a drop-in
replacement for the wallet's routed-swap build. Comparing the relevant files at
both exact SHAs gives identical Git blobs:

| KDF contract | Identical blob SHA |
|---|---|
| `mm2src/proxy_signature/src/lib.rs` | `72aa18f3d7847fb1289066f30862a41f24f59026` |
| `mm2src/mm2_main/src/lp_healthcheck.rs` | `0d358845c0797719a9fa7a28bc7cba0ecc912302` |

Both sign `body_size` as fixed-width little-endian `u64`; the peer-healthcheck RPC
returns a boolean result, which current KDP expects. KDP's own lockfile still
pins `proxy_signature` at `e65fefe5`, but its verifier explicitly accepts the
canonical eight-byte encoding plus the older four-byte WASM encoding. Updating
that dependency is separate maintenance; the fixed-width wallet signature is
already compatible with the inspected verifier.

## Historical issues and current evidence

[KDP #30](https://github.com/GLEECBTC/komodo-defi-proxy/issues/30) remains open,
but its principal fixes are already in source through merged
[#31](https://github.com/GLEECBTC/komodo-defi-proxy/pull/31): no global cache lock
across KDF RPC, a 30-second outbound RPC deadline, replacement of the problematic
`timed-map` cache, local signature verification before peer RPC, WASM signature
compatibility, and GasFree browser-header handling. LI.FI forwarding support was
merged in [#32](https://github.com/GLEECBTC/komodo-defi-proxy/pull/32).
Those proxy fixes are not supplied by updating only its backend KDF image.

The fresh native quote check passed Arbitrum and Base exact quotes, the included
2% combined fee, required funding totals and rejected unfunded Max. Its generated coin digest matches the
frozen manifest. No approval, swap or payment was submitted.

The Chrome WASM check also passed using the pinned engine and the configured
proxy: an Arbitrum exact quote had a
positive minimum and exactly one included 2% fee. This exercises the signed
browser request path that the older issue had called into question. The read-only
diagnostic is retained as `test_integration/tests/kdf_tests/lifi_proxy_quote_smoke.dart`.
Its first two temporary runs failed before contacting the proxy because of
diagnostic setup mistakes (version RPC envelope, then bundled asset key); both
were corrected before the successful run. They are not service failures.

Public endpoint checks returned 401 for one unsigned LI.FI catalog request and
204 for a browser preflight with
`X-Auth-Payload` permitted. This checks rejection/CORS behavior; it does not prove
the deployed version, peer-healthcheck implementation or behavior under load.
The proxy root returned 404 through the public ingress, so it provided no version
information. No private administration endpoint or credential was accessed.

## Remaining owner evidence

- Record the deployed KDP commit/image digest, backend KDF version/image digest,
  and non-secret route/access/rate-limit settings. Replace floating references
  with reviewed immutable deployment inputs when preparing a service release.
- Verify shared-load recovery and browser reconnection on the actual deployment.
  The fresh browser quote passed; an old issue's intermittent browser peer
  failures are not disproved by a single successful session. Do not disable
  peer/signature validation to make a test pass.
- Retain the existing decision on KDF's five-second status-error polling and
  capacity/monitoring. Successful quotes do not exercise recovery after approvals
  or prove production load capacity.

These are provenance and operational sign-off gaps, not evidence that a newer
backend KDF is required. No service configuration, engine pin, deployment or
upstream repository was changed. No communication was sent.

Generated evidence is retained locally under `.lifi/evidence/` and excluded from
Git: `KDF_LIFI_PROXY_RC_AUDIT_2026-10-27.json`,
`KDF_LIFI_PROXY_RC_QUOTE_CHECK_2026-10-27.json`,
`KDF_LIFI_PROXY_WASM_CHECK_2026-10-27.json` and
`KDF_LIFI_PROXY_PUBLIC_CHECKS_2026-10-27.json`. These reports contain the
artifact-index digests, probe outputs and local log references. The exact source
revisions, contract blobs, conclusions and unknown deployment fields remain
recorded above.
