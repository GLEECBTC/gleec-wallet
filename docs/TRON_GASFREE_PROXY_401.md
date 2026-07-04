# TRON gas-free proxy `401` — diagnosis & fix

> Status: **root cause identified and reproduced** (code audited across wallet, SDK,
> KDF, and the GLEEC `komodo-defi-proxy`; cross-checked against the KDF API docs; and
> reproduced locally against the real proxy built from the gas-free commit). The
> remaining work is **operational** (proxy-side p2p topology), not a wallet code change.
> A local reproduction stack lives in
> [`contrib/tron-gasfree-proxy-debug/`](../contrib/tron-gasfree-proxy-debug/).
>
> **Reproduced locally** (proxy built from commit `4526f9d`), driving requests through the
> proxy with an `x-auth-payload` carrying a client KDF node's real PeerId:
> | client p2p state | `peer_connection_healthcheck` | proxy result |
> |---|---|---|
> | connected to the proxy's KDF node | `true` | passes the gate (then 401 only on a bad signature) |
> | **not** connected | `false` | **`401` — `"Peer isn't connected to KDF network"`** |

## Symptom

Gas-free (gasless TRC20) withdrawals fail. The wallet's KDF makes a `komodo_proxy`
request such as:

```
GET https://quicknode.gleec.com/gasfree/tron/api/v1/address/{tronAddress}
x-auth-payload: {"signature_bytes":[…64 bytes…],
                 "address":"12D3KooW…",                      # the node's libp2p PeerId
                 "raw_message":{"uri":"https://quicknode.gleec.com/gasfree/tron/api/v1/address/{addr}",
                                "body_size":0,"public_key_encoded":[…],"expires_at":…}}
```

…and the proxy responds **`401 Unauthorized`** (empty body).

## TL;DR

**Not a wallet/SDK/KDF bug.** The wallet, SDK and KDF gas-free code is correct and
matches the KDF API docs. The `401` is produced by the **proxy's authentication
middleware**, which gates *every* `komodo_proxy` route by asking **its own KDF node**
whether the wallet's libp2p peer is connected to the KDF p2p network
(`peer_connection_healthcheck`). For the wallet's **WASM light node** that check is
returning `false`, because the proxy's KDF node is **not in the wallet's p2p relay
mesh** (wrong netid, or simply not one of the seednodes the wallet connects to). The
fix is on the proxy/infrastructure side.

## Where the gas-free proxy is wired into KDF

In `komodo_proxy` mode the proxy is supplied as the **`tron_gasless_provider`** field
when activating the TRON platform coin (`enable_eth_with_tokens` /
`task::enable_eth::init`), plus a per-TRC20 `gasless: { enabled: true }` object:

```jsonc
"tron_gasless_provider": {
  "base_url": "https://quicknode.gleec.com/gasfree/tron",
  "service": "komodo_proxy",
  "service_provider": "T…"
}
```

Wallet → KDF chain:

| Layer | Location |
|---|---|
| Wallet constant | `lib/shared/constants.dart` → `tronGaslessBaseUrl`, `tronGaslessServiceProvider` |
| Wallet → SDK config | `lib/mm2/mm2.dart` builds the SDK `TronGaslessProviderConfig` |
| SDK activation | threaded to `enable_eth_with_tokens` (TRX arm) |
| KDF client | `mm2src/coins/eth/tron/gasfree/client.rs` (`TronGasfreeTransport::KomodoProxy`) |

KDF docs: [`tutorials/tron-gasfree`], [`common_structures/activation` → `TronGaslessProviderConfig`],
[`enable_eth_with_tokens`], [`withdraw`], [`gasless_trace_status`].

In `komodo_proxy` mode **no API secret lives on the node** — the node authenticates to
the proxy with **its libp2p key** (the `x-auth-payload` Ed25519 signature), and the
proxy holds the GasFree HMAC credentials and adds them server-side.

## How the proxy produces the 401

GLEEC `komodo-defi-proxy`, `src/proxy/http/mod.rs` → `validation_middleware`:

1. Requests from **private/loopback source IPs bypass validation** entirely
   (`src/proxy/mod.rs`, `is_private_ip`). Public requests (the real wallet, via
   `X-Forwarded-For`) go through the checks below.
2. Look up the signer's address status in redis:
   - `Trusted` → allow (bypasses the healthcheck);
   - `Blocked` → **`403`** (note: *not* 401);
   - `None` (the default for any peer) → continue.
3. **`peer_connection_healthcheck`** — call **the proxy's own KDF node's** RPC
   `peer_connection_healthcheck { peer_address }`. If the result is not `true` (or the
   PeerId is malformed) → **`401`** (`"Peer isn't connected to KDF network, returning 401"`).
4. `is_valid_message(MAX_SIGNATURE_EXP_SECS = 15)` — verify the Ed25519 signature and
   that the signature is within its **15-second** window → else **`401`**
   (`"invalid signed message, returning 401"`).
5. Rate-limit → `406` if exceeded.

The newly added gas-free handler (`src/proxy/http/gasfree.rs`) runs **after** this gate
and never returns `401` itself — only `500`/`503`, or it forwards `open.gasfree.io`'s
own response. So a `401` is always the middleware in steps 3–4, and never the GasFree
upstream.

### Why step 3 fails for the wallet

`peer_connection_healthcheck` (KDF `mm2src/mm2_main/src/lp_healthcheck.rs`) is **not** a
direct ping. It is a **gossipsub broadcast-and-await-reply**: the proxy's KDF node
publishes on topic `hcheck/<peerId>` and waits ~10 s for the target peer to gossip back
a signed reply; on timeout it returns `false`.

The wallet runs KDF as a **WASM light (non-relay) node** (outbound WSS only, no inbound
listener). For the publish to reach it and a reply to come back, the wallet and the
proxy's KDF node must be in the **same gossipsub relay mesh**. They do **not** have to be
directly connected to each other — sharing **a common seed relay is sufficient**
(empirically verified: a "proxy node" and a "wallet" connected only to a common seed,
never to each other, complete the healthcheck — see the relay-mesh experiment in
`contrib/tron-gasfree-proxy-debug/`). What breaks it is the proxy's KDF node not sharing
any relay with the wallet — most commonly a **netid mismatch** (e.g. the proxy node on
the legacy `8762` while the wallet is on `6133`), or the proxy node simply not being
connected to any of the seeds the wallet uses.

The wallet (web build) only connects to the **WSS, netid-6133** seednodes bundled in
`sdk/packages/komodo_defi_framework/assets/config/seed_nodes.json`
(`seed03.kmdefi.net`, `kdfseed1.decker.im`, `staking1.gleec.com`, `staking2.gleec.com`).
If the proxy's KDF node is on a **different netid**, or is not connected to **any** of
those seeds, it shares no relay with the wallet → healthcheck times out → **`401`**.

This gate guards **all** `komodo_proxy` traffic to `quicknode.gleec.com`, not just
gas-free — including mainnet TRON JSON-RPC, which the SDK routes there with
`komodo_proxy: true` (`sdk/.../coins_config/config_transform.dart`,
`TronQuickNodeTransform`).

## What was ruled out (with evidence)

| Hypothesis | Verdict | Evidence |
|---|---|---|
| Clock skew on the 15 s window | **Ruled out (measured)** | proxy `Date` header vs local clock = **0 s** skew on the dev machine. KDF signs `expires_at = now + 15` (`PROXY_REQUEST_EXPIRATION_SEC = 15`); proxy `MAX_SIGNATURE_EXP_SECS = 15` |
| `/gasfree` route not deployed | **Ruled out (probed)** | unauth `GET …/gasfree/tron/api/v1/...` → **401, not 404** (route exists and is gated); bare `/` → 404 |
| Signed-URI vs request-path mismatch (e.g. `/tron`) | **Ruled out** | `is_valid_message` never compares the signed `uri` to the request path |
| JSON schema mismatch vs docs | **Ruled out** | activation/withdraw/per-token shapes all match the documented `TronGaslessProviderConfig` etc. |
| Wallet disables p2p | **Ruled out** | single KDF instance via `noAuthStartup` → `disableP2p: false`, netid `6133` |
| KDF signs incorrectly | **Ruled out** | `gasfree/client.rs` `KomodoProxy` arm signs the full URL with the node libp2p key + `X-Auth-Payload` — matches the failing request exactly |
| Redis `Blocked` status | **Ruled out** | `Blocked` → `403`, not `401` |

> Caveat: the **zero-margin 15 s window** is a real latent fragility even though skew is
> ~0 here. A real user whose browser clock is ≥1 s ahead of the proxy gets a
> deterministic `401` on every `komodo_proxy` request. See the fix below.

## Fix

### Primary (operational — proxy side)

The proxy's KDF probe-node (its `kdf_rpc_client`, `http://127.0.0.1:7783` on the
quicknode.gleec.com host) must:

1. run on **netid 6133** (matching the wallet — this is the part most likely wrong today), and
2. be connected into the **same relay mesh** as wallets. The simplest way is to give that
   KDF node the **same netid-6133 seednodes the wallet uses** — i.e. the netid-6133 entries
   from `sdk/packages/komodo_defi_framework/assets/config/seed_nodes.json`
   (`seed03.kmdefi.net`, `kdfseed1.decker.im`, `staking1.gleec.com`, `staking2.gleec.com`).
   It does **not** need to be a seed wallets dial directly — sharing a common seed relay is
   enough (verified). Making it one of those seeds also works, but is not required.

> So in practice: point the proxy's KDF node at the coins-repo seed list **filtered to
> netid 6133** and run it on netid 6133. The one trap is netid — `seed_nodes.json` mixes
> 6133 and 8762 entries; using the 8762 ones (or running the node on 8762) shares no mesh
> with the wallet and keeps the 401.

### Definitive diagnostic (run on the proxy host)

```sh
# Is the wallet peer reachable from the proxy's KDF node?
curl -s http://127.0.0.1:7783 -d '{"userpass":"<rpc_password>","mmrpc":"2.0",
  "method":"peer_connection_healthcheck","params":{"peer_address":"<wallet PeerId 12D3KooW…>"}}'
# Confirm that node's netid == 6133, and grep the proxy log:
#   "Peer isn't connected to KDF network, returning 401"  -> this diagnosis
#   "invalid signed message, returning 401"               -> signature/expiry instead
```

Reproduce both outcomes locally first with the stack in
[`contrib/tron-gasfree-proxy-debug/`](../contrib/tron-gasfree-proxy-debug/).

### Secondary (hardening)

- **Widen the proxy's `MAX_SIGNATURE_EXP_SECS`** (e.g. 15 → 30–60) so normal browser
  clock drift cannot deterministically `401`.
- **Surface the proxy `401`** distinctly in the wallet/SDK instead of silently falling
  back to a native TRX-paid transfer, so this failure mode is obvious next time.
- **Document the prerequisite**: `komodo_proxy` mode requires the node to be connected
  to the proxy's KDF p2p network on the matching netid. Currently undocumented — the
  tron-gasfree tutorial only says the node "authenticates with its libp2p key."

## Second issue for the **web** build: CORS on forwarded responses (latent behind the 401)

Distinct from the 401, and only reachable *after* it is fixed: `open.gasfree.io` is behind
**Cloudflare**, which **`403`s requests carrying a browser `Origin` and returns no
`Access-Control-Allow-Origin`**. The proxy's `gas_free` handler returns the upstream
response **raw** — it adds CORS to its *own* responses (preflight, `response_by_status`
errors) but **not** to forwarded `gas_free` responses. So a **WASM/web** build is
CORS-blocked when reading forwarded gas-free responses, even once the 401 is resolved.

- **Verified locally**: a no-`Origin` request forwards fine (`Apikey not found` with a
  placeholder key); the same request **with** `Origin` gets `403` + `server: cloudflare`,
  no ACAO.
- **Native builds are unaffected** (KDF's Rust HTTP client sends no `Origin`) — which is
  why the local test in [`contrib/tron-gasfree-proxy-debug/`](../contrib/tron-gasfree-proxy-debug/)
  uses the macOS build.
- **Web fix** — implemented as
  [`contrib/tron-gasfree-proxy-debug/proxy/gasfree-cors.patch`](../contrib/tron-gasfree-proxy-debug/proxy/gasfree-cors.patch):
  the `gas_free` route strips inbound `Origin`/`Referer` before forwarding upstream and
  adds `Access-Control-Allow-*` on the forwarded response. The local debug stack builds
  with it applied (verified: browser-`Origin` request → `200` + data + ACAO). **Apply this
  patch to the GLEEC `komodo-defi-proxy` repo (clean on `4526f9d`) and redeploy** for the
  production web app.

## Unrelated note (not the 401)

`tronGaslessServiceProvider` (`lib/shared/constants.dart`) must match the GasFree account
behind the proxy. Confirm it against `<base_url>/api/v1/config/provider/all`. A mismatch
surfaces as a `500`/`503` at **submit** time — it is not the address-lookup `401`.
