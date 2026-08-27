# Skipping or caching node/Electrum preflight on web — what is actually possible

**Reported by:** research pass, 2026-08-07, against KDF `25f6e1f0b` and the
`add/gas-free-tron` wallet tree
**Companion to:** [`docs/KDF_RPC_BURST_REPORT.md`](KDF_RPC_BURST_REPORT.md)
(read that first; this report closes its §4.1 open hedge and does not restate it)
**Scope:** two unrelated things that share the word *preflight* —
**(A)** the browser's CORS `OPTIONS` before a cross-origin node RPC, and
**(B)** KDF's own per-session node/Electrum handshake and health-probe work.

---

## 0. Answer first

**(A) Browser CORS preflight.** It can be *cached* but not *skipped* on the
endpoints that matter, and caching does not help the login burst at all. A cold
GLEEC login pays **on the order of 12 preflights, not 44** — the concurrency
budget, not the call count, bounds them — at roughly **one round trip (~200 ms)
each, paid concurrently, once**. The only mechanism that eliminates them
entirely is **WebSocket**, which is measured working for GLEEC and structurally
unavailable for TRON.

**(B) KDF's own handshake work.** Almost nothing is left to cache. EVM/TRON
activation issues **zero** per-node probe RPCs on the HTTP transport; the
per-node `web3_clientVersion` probe was deleted in `543598231` (PR #2527).
Electrum's handshake is one `server.version` frame on a socket that must be
opened anyway (~192 ms measured). The genuinely expensive per-session work is
the BIP44 gap scan, which KDF already caches across sessions in IndexedDB and
the **SDK then re-runs anyway** — that is a bigger prize than anything in this
report, and it is already recommended in the burst report §8.

### 0.1 Verdict table

| Option | Verdict | The single reason | Lands in |
|---|---|---|---|
| Make requests CORS-simple (`text/plain` / drop `Content-Type`) | **Not viable** | `evm-rpc.gleec.com` returns `415` (measured), and every mainnet TRON config gets a `komodo_proxy` node injected at runtime whose `X-Auth-Payload` forces a preflight regardless | — (dead end) |
| Rely on `Access-Control-Max-Age` | **Viable, small** | One header; fixes warm reloads and the 30 s balance poll. Does **not** reduce cold-login preflights — browsers do not coalesce concurrent preflights (measured) | node op (Caddy at `evm-rpc.gleec.com`) |
| WebSocket transport for EVM | **Conditional** | Measured: full JSON-RPC surface + 44/44 login-shaped burst on one socket, zero preflights. But GLEEC has only one node (no HTTP fallback if `url` is overwritten), TRON has **no** `ws_url` at all, and it reintroduces a per-session socket handshake | app (coins-config transform) — no KDF change |
| Same-origin proxy | **Not recommended** | Eliminates CORS entirely, but inserts a Gleec-controlled party into the delivery path of a non-custodial wallet's own code and RPC | new infra (Cloudflare Worker + DNS flip) |
| Service worker | **Not viable** | Spec-proven: a preflight never dispatches a `fetch` event, and the Cache API rejects non-GET. Production ships a self-unregistering tombstone SW | — (dead end) |
| Cache KDF's own handshake results (B) | **Not viable — nothing to cache** | EVM/TRON activation does zero probing; Electrum's negotiated version is written and never read anywhere in the codebase | — |
| Persist the pool's learned concurrency budget | **Conditional** | Real per-reload waste, but a naive cache pins a user at concurrency 2 after one throttled night | KDF eth layer (`web3_pool.rs`) |
| Do nothing | **Defensible** | The measured latency cost is ~200 ms once per cold login. The real cost is limiter budget, not milliseconds | — |

---

## 1. What actually happens today on web

| Coin family | Transport on wasm32 | CORS preflight? | Dispatch site |
|---|---|---|---|
| KMD, BTC-segwit (UTXO) | Electrum over **WSS** | **None, ever** | `electrum_rpc/connection.rs:469-525` (wasm arm; TCP/SSL are `Irrecoverable` at `:500-504`) |
| GLEEC, ETH, USDT/USDC-ERC20 | EVM JSON-RPC over `fetch` POST | **Yes** | `eth/web3_transport/http_transport.rs:311-321` |
| TRX, USDT-TRC20 | TRON HTTP API over `fetch` POST | **Yes** | `eth/tron/api.rs:427-438` |
| GasFree rail | `slurp_post_json_with_headers` | **Yes** | `mm2_net/src/wasm/http.rs:44-57` → `eth/tron/gasfree/client.rs:201` |

The app↔KDF hop has **no CORS at all** — on web the Dart layer calls the wasm
export in-process (`kdf_operations_wasm.dart:46`, `@js_interop.JS('mm2_rpc')`).

> **Correction to a common misreading.** KDF's own
> `Access-Control-Max-Age: 3600` at `mm2_main/src/rpc.rs:275` is inside
> `rpc_service`, which is gated `#[cfg(not(target_arch = "wasm32"))]` at
> `rpc.rs:222`. It is native-only dead code on web and must not be cited as
> evidence that KDF "already handles preflight caching" in a browser.

The default coin set is `lib/app_config/app_config.dart:199-214` (GLEEC, KMD,
BTC-segwit, ETH, TRX, USDT-ERC20, USDT-TRC20, USDC-ERC20). Two of eight are
already preflight-free by construction.

### 1.1 The `komodo_proxy` fact that reframes everything

The shipped `coins_config.json` contains **zero** `komodo_proxy` nodes (verified
by JSON scan: 2467 node entries, 0 with the flag). That is true and misleading.
`TronQuickNodeTransform` (`config_transform.dart:280-310`) is in the default
transform list (`:41`), is **not** platform-gated, and **prepends**
`{'url': 'https://quicknode.gleec.com/', 'komodo_proxy': true}` to every mainnet
TRX and TRC20 config at runtime (`:298-303`, `:308-309`).

**Every TRON request on web therefore carries `X-Auth-Payload`**
(`tron/api.rs:438`), which is not CORS-safelisted and forces a preflight
independent of `Content-Type`. TRX and USDT-TRC20 are 2 of the 8 default coins.

---

## 2. Sense (A) — the browser CORS preflight

### 2.1 What forces it

A POST is preflight-free only if it is a *simple request*: safelisted method
(GET/HEAD/POST) and no CORS-unsafe request header. Per Fetch §2.2.2, the
`Content-Type` value must parse to exactly
`application/x-www-form-urlencoded`, `multipart/form-data`, or `text/plain`;
`application/json` is never safelisted, and there is no exemption for it in the
"CORS protocol exceptions" list. Two independently sufficient triggers exist in
KDF:

| Trigger | Where | Applies to |
|---|---|---|
| `Content-Type: application/json` | `http_transport.rs:317`, `tron/api.rs:435`, `tendermint_wasm_rpc.rs:92`, `wasm/http.rs:36`/`:55` | all EVM/TRON/Tendermint POSTs |
| `X-Auth-Payload` | `http_transport.rs:320`, `tron/api.rs:438`, `gasfree/client.rs:95` | every `komodo_proxy` node — i.e. **all mainnet TRON**, per §1.1 |

`Accept: application/json` is safelisted (16 bytes, no CORS-unsafe byte) and is
**not** a trigger. GET paths (`slurp_url`, `send_request_to_uri` with
`auth_header: None` — e.g. NFT token-URI metadata at `nft.rs:1066`) are already
simple requests and cost zero preflights.

> **`FetchRequest::cors()` is a no-op.** Its doc comment at `wasm/http.rs:146-147`
> ("The request is no-cors by default") is wrong: `JsRequest::new_with_str_and_init`
> at `:260` passes a string URL, and Fetch sets `fallbackMode` to `"cors"` for
> string input. Measured in-browser: `new Request(url,{method:"POST"}).mode ===
> "cors"`. There is no "stop calling `.cors()`" escape hatch. Fix the comment.

Nothing in KDF sets `credentials` or `cache` mode — `RequestInit` receives only
`set_method`, `set_body`, `set_mode` (`wasm/http.rs:249-258`). Wildcard `ACAO`
therefore stays valid, and the preflight cache entry is the shared
uncredentialed kind. **Do not regress this**: Chromium skips the preflight cache
entirely when any of `LOAD_VALIDATE_CACHE|LOAD_BYPASS_CACHE|LOAD_DISABLE_CACHE`
is set (`preflight_controller.cc:59-62`, `:616-617`), which is what
`fetch(url,{cache:'no-store'|'reload'|'no-cache'})` and DevTools "Disable cache"
produce.

### 2.2 The exact code that would change

For the simple-request route the change is *smaller* than it looks and still
useless (§2.5). The often-cited enforcement — `build_post_json_fetch_request`
(`wasm/http.rs:52-57`, pinned by `test_post_json_content_type_cannot_be_overridden`
at `:526-534`) — governs only `slurp_post_json*`, i.e. the **GasFree** client.
The EVM and TRON JSON-RPC transports build a `FetchRequest` inline and hardcode
the header through the ordinary overridable `.header()` builder
(`wasm/http.rs:155-158`, a plain HashMap insert, last write wins). So the
content-type is un-overridable on those paths because it is a literal with no
caller input, not because of the tested helper.

Note the body-type interaction if anyone ever revisits this: `RequestBody::Utf8`
becomes a JS string, so *deleting* the header yields an automatic
`text/plain;charset=UTF-8`; `RequestBody::Bytes` becomes a `Uint8Array`, for
which fetch sets no `Content-Type` at all (`wasm/http.rs:434-444`).

Native parity is structurally safe: `mm2_net/src/transport.rs:8-15` re-exports
`native_http::*` and `wasm::http::*` under mutually exclusive `cfg`, with
separate content-type literals (`native_http.rs:116-122`,
`http_transport.rs:148-149`).

### 2.3 Measured endpoint behaviour

Origin `https://dex.gleec.com`, `Access-Control-Request-Method: POST`,
`Access-Control-Request-Headers: content-type`, measured 2026-08-06/07.

| Endpoint | OPTIONS | `Access-Control-Max-Age` | `text/plain` POST |
|---|---|---|---|
| **`evm-rpc.gleec.com`** (GLEEC, sole node) | 204 | **absent** | **415** |
| `ethereum-rpc.publicnode.com` | 204 | 172800 | 200 |
| `mainnet.gateway.tenderly.co` | 200 | **absent** | 200 |
| `public-eth.nownodes.io` | 204 | 1728000 | **415** |
| `rpc.mevblocker.io` | 200 | 172800 | 200 |
| `api.trongrid.io/wallet/*` | 204 | 1728000 | 200 |
| `tron-rpc.publicnode.com/wallet/*` | 204 | 172800 | 200 |
| `quicknode.gleec.com` (proxy) | 204 | 86400 | 404 (route dead) |
| `wss://…` Electrum + `wss://evm-ws.gleec.com` | *no preflight exists* | n/a | n/a |

Across all 16 HTTP node URLs of the five chains involved (ETH 4, BNB 5, MATIC 4,
TRX 2, GLEEC 1), `text/plain` works on **12 of 16** and 415s on 4. Scoped to the
default-activated coins (GLEEC, ETH, TRX) it is **5 of 7**.

Two further measured facts about the Gleec edge:

* **The 415 carries `access-control-allow-origin: *`** (it comes from the Caddy
  origin), so it is readable by the browser. Only the 429s are CORS-invisible.
* **The edge *reflects* `Access-Control-Request-Headers` verbatim** rather than
  serving a fixed allowlist. `ACRH: x-totally-made-up-header,x-auth-payload`
  comes back echoed in `access-control-allow-headers`, and `ACRM: PUT` is
  reflected too. The `vary: Origin, Access-Control-Request-Method,
  Access-Control-Request-Headers` on every response is the tell. **An earlier
  reading that the edge only allows `content-type`, and would therefore reject
  a `komodo_proxy` GLEEC node, is refuted** — the edge is not a blocker for
  proxy nodes.

Also measured and worth a separate ticket, unrelated to preflights: with
`Origin: https://evil.example` the endpoint returns a 204 preflight and a 200
POST with a readable body — it is fully open cross-origin to any website — and
`debug_traceBlockByNumber` with `callTracer` returns `{"result":[]}` rather
than `-32601`, i.e. the `debug` namespace is reachable by any origin on the
chain's **only** node. (`eth_accounts` → `[]`; `personal_*`, `admin_*`,
`txpool_*`, `miner_*` all `-32601`.)

### 2.4 Browser cache caps and behaviour

| Browser | Cap on `Access-Control-Max-Age` | Default when absent | Citation |
|---|---|---|---|
| Chromium | **7200 s** | 5 s | `services/network/cors/preflight_result.cc:35,40,74-76` |
| Firefox | 86400 s | 5 s | `netwerk/protocol/http/nsCORSListenerProxy.cpp:1403-1404`, `:67` |
| WebKit/Safari | **600 s** | 5 s | `Source/WebCore/loader/CrossOriginPreflightResultCache.cpp:42-43,66-68` |

Spec basis: Fetch §4.8 — *"If max-age is failure or null, then set max-age to 5"*
and *"If max-age is greater than an imposed limit on max-age, then set max-age
to the imposed limit."* **Any value above 7200 is decoration in Chrome.** Safari
is the binding constraint at 10 minutes; a session longer than that re-preflights
on iOS regardless.

Four behaviours that decide the design:

1. **No coalescing.** Chromium constructs a `PreflightLoader` per cache-missing
   request with no in-flight dedup (`preflight_controller.cc:616-634`; `loaders_`
   is keyed on pointer identity). *Measured predictively*: against
   `evm-rpc.gleec.com`'s ~20/s window, a non-coalescing model predicts N=14 cold
   → 6 successes / 8 rejections; a coalescing model predicts 14/0. Observed on
   three independent cold runs: **6 × 200 + 8 rejected, every time.** Warm
   control on a rested limiter: 14 × 200, 0 rejected.
2. **Keyed on the full URL** (Fetch §4.9: NPK + byte-serialized origin + URL;
   credentials is an asymmetric *condition*, not a key component). Measured on
   four URLs differing only by query string: each paid its own preflight
   (413–421 ms first, 204–212 ms after). TRON's REST API spans 8 distinct
   `/wallet/*` paths (`tron/api.rs:820-900`), so one TRON node needs up to 8
   permissions where one EVM node needs 1.
3. **Survives page reload, lives in the network service.** Measured on a URL
   with max-age 172800: still 1-RTT at 716 s and after navigating to a new
   document, while a never-seen control URL paid 2 RTT.
4. **Absent header really means ~5 s.** Bracketed on tenderly with the socket
   pre-warmed to isolate preflight from connection cost: gaps of 2.82 s / 3.83 s
   → 180/182 ms (cached); 4.82 s / 4.86 s / 6.65 s → 371/495/366 ms (expired).

### 2.5 How many preflights a login actually costs

*This subsection is arithmetic over measured mechanics — labelled **inferred**.
No preflight count has ever been taken from the running app (§8).*

Inputs, all measured: concurrency budget **12** (`web3_pool.rs:121`); GLEEC HD
first login = **44 calls in 1.5 s** (burst report §2); permission lifetime **5 s**
with no max-age; preflights do not coalesce; the pool concentrates all traffic
on one node (`web3_pool.rs:517-529`, `eth_rpc.rs:196-236`), so node count does
not multiply URLs.

At t≈0 all 12 permits are taken and 12 preflights go out. Each returns at
~220 ms; the POSTs at ~400 ms. No thirteenth request can be issued until a
permit frees, by which time the cache entry exists and is ~180 ms old. The
**concurrency budget, not the call count, bounds the preflight count**:

> **A cold GLEEC login costs ≈12 preflights, not 44 — so ≈56 wire requests at
> the edge, not 88.** This closes the hedge in burst report §4.1 ("can therefore
> approach 88 requests… not guaranteed to be exactly 88") in the client's favour.

Adding `Access-Control-Max-Age` changes that 12 **to 12**. The cache is empty
when all 12 are issued.

What max-age *does* change:

* **Warm reload:** 12 → 0 preflights (measured that the entry survives reload).
* **Steady state:** the SDK polls balances every 30 s
  (`balance_manager.dart:118`) and `EthBalanceEventStreamer` every 10 s. Both
  intervals exceed the 5 s default permission, so **every poll currently pays a
  preflight**. With the header, none do. That is a genuine recurring halving of
  steady-state request count against the limiter.

Whole-wallet cold login across the default set is *inferred* at the order of
25–40 preflights: GLEEC 1 URL, the ETH pool 1 URL (ERC20 tokens clone the
platform pool at `v2_activation.rs:643`/`:751`), the TRON pool 2–3 of its 8
REST paths, KMD/BTC zero.

### 2.6 What breaks

* **`text/plain` on GLEEC:** total outage. `415 invalid content type, only
  application/json is supported` — go-ethereum's `validateRequest` whitelist
  (`application/json`, `application/json-rpc`, `application/jsonrequest`;
  `mime.ParseMediaType("")` errors, so an absent header also 415s).
* **`text/plain` on TRON:** no effect. `X-Auth-Payload` is injected at runtime
  (§1.1) and forces the preflight anyway.
* **grpc-web (Z-coin/ARRR, BCHD):** structurally preflight-bound —
  `application/grpc-web+proto` is not safelisted and `x-grpc-web` is custom
  (`grpc_web.rs:185`, `tonic_client.rs:55`). Only max-age helps them.
* **`no-cors` mode / `sendBeacon`:** both drop non-safelisted headers silently
  and yield unreadable responses. Fatal for RPC.
* **Service worker:** Fetch §4.8 routes the preflight through
  HTTP-network-or-cache fetch, so no `fetch` event is ever dispatched for it;
  the Cache API rejects non-GET requests. A SW's own cross-origin fetch
  preflights identically. Production ships Flutter's 784-byte self-unregistering
  tombstone (`flutter_service_worker.js`, verified on both `dex.gleec.com` and
  `walletrc.web.app`), and the local Flutter 3.41.4 build emits a 0-byte one.

---

## 3. Sense (B) — KDF's own per-session handshake work

### 3.1 EVM / TRON: there is nothing left

`build_web3_instances` (`v2_activation.rs:1175-1210`) shuffles, parses each URI,
calls `create_transport`, pushes — **zero `.await` in the body**, therefore zero
RPCs. `build_tron_api_client` (`:1213-1261`) is the same. The per-node
`web3_clientVersion` probe was deleted by `543598231` (Onur Ozkan, 2025-07-07,
PR #2527, *"improvement(eth): drop parity support"*); if anyone remembers KDF
pinging every node at startup, that memory is ~13 months stale.

Two vestiges mislead readers and should be cleaned up:

* `UnreachableNodes("Failed to get client version for all nodes")` at
  `v2_activation.rs:1203-1207` and `ERR!("Failed to get client version for all
  urls")` at `eth.rs:7205-7207` — both guarded by an `is_empty()` that can no
  longer be true.
* `build_web3_instances` is still `async` for no reason: `create_transport`
  (`:1263`) is a plain synchronous `fn`.

Exactly **one** HTTP request precedes the first balance call, and it is not a
probe: `eth_blockNumber` via `get_activation_result`
(`eth_with_token_activation.rs:383-387` → `eth.rs:3086` → `eth_rpc.rs:504-509`),
whose value is returned to the caller as the response's `current_block` field.
Only one node is dialed on the happy path. Token activation adds nothing unless
`decimals` is absent or 0 in the conf (`v2_activation.rs:571-572`).

The one surviving `web3_clientVersion` is in `get_live_client`
(`eth.rs:3385-3436`), double-gated: it fires only for a transport whose
*previous* request failed, and `EthCoin::web3()` (`eth.rs:3467-3469`) has two
production call sites, both NFT fee lookups (`nft.rs:924`, `nft.rs:943`). The
modern path (`try_every_node`, `eth_rpc.rs:210`) bypasses it. On a healthy pool
it costs zero requests.

### 3.2 Electrum: cheap, and the negotiated value is never read

| Item | Cost | Cacheable? |
|---|---|---|
| WS open (TCP+TLS+upgrade) | ~825 ms measured | No — must happen |
| `server.version` | ~192 ms, one frame | **Skippable, not cacheable** |
| `blockchain.headers.subscribe` | 1 RPC per coin at activation | No — height is live, and a new socket has no subscription |
| `server.ping` | every 30 s (`constants.rs:7`) | n/a, steady state |

The negotiated protocol version is written into a **private field with no
getter** (`connection.rs:170`, set only at `:639`, cleared at `:209-211`/`:241`)
and is read nowhere in the codebase. Any "cache the negotiated version" proposal
is really "skip the compatibility gate", which is gated by `negotiate_version`
(`utxo.rs:1644-1646`, default `true`) and not reachable from the RPC surface
for `utxo_standard`. **Not worth pursuing.**

On web the wallet ships 2 Electrum coins, filtered to WSS-only by
`WssWebsocketTransform` (`config_transform.dart:222-268`), with `max_connected: 1`
— roughly 2 WS opens and 4 Electrum RPCs per login. That is a rounding error
against the 44-wide EVM burst.

Corrections worth carrying, because prior summaries got them wrong:

* Selection is **not** purely sequential. The manager's maintenance path is
  priority-ordered (`manager.rs:414-457`), but the request path fans out up to
  `max_connected` simultaneous handshakes via `FuturesUnordered`
  (`client.rs:433-462`), and `client.rs:381-386` says so explicitly.
* The first suspension is **20 s, not 10 s**: `SuspendTimer::double()` runs
  before the value is ever read (`connection_context.rs:36-48`), so
  `FIRST_SUSPEND_TIME = 10` is a pre-doubling seed. Series is 20/40/80…12 h.
* A `VersionMismatch` removal is scoped to that **coin's** client, not the KDF
  instance, and only happens on the manager's maintenance path
  (`manager.rs:443-445`). Disabling and re-enabling the coin restores the server.

### 3.3 What *is* lost every reload

Every login tears down and restarts KDF
(`auth_service_kdf_extension.dart:188`, `:237-264`), so all in-memory pool state
resets. Two candidates:

| State | Value of persisting | Failure mode if done naively |
|---|---|---|
| `ConcurrencyController` budget (starts 12, `web3_pool.rs:121`; converges to 2–3 for GLEEC per `:93-94`) | Real: re-learning costs refused requests, and `std::env::var` always fails on wasm32 so the browser has **no** lever today | Pins a user at 2 after one throttled night. Needs a TTL and an upward-probe path |
| `preferred` node cursor / `last_request_failed` | Low — the node list is deliberately shuffled per activation (`v2_activation.rs:1184-1186`) | — |
| Electrum suspend timers / `VersionMismatch` verdict | Low–medium | Pins out a server that has since been upgraded. Same TTL requirement |

**The real per-session cost is not a handshake at all.** It is the BIP44 gap
scan: 21 addresses × 2 RPCs = 42 of the 44 measured calls. KDF already caches it
across sessions — `enable_hd_wallet` skips rescanning when the account is in
storage, and `ScanIfNewWallet` is the default (`coin_balance.rs:159-171`,
`:520-546`, `:577`), backed by IndexedDB on wasm
(`hd_wallet/storage/mod.rs:24-26`). **The SDK then re-runs it anyway**, because
its skip-gate requires the protocol to expose a `scan_policy` and the ETH-family
activation params have no such field — the code says so at
`pubkey_manager.dart:776-789`. That is burst report §7.1 item 1, and it is worth
more than every preflight in this document.

---

## 4. Honest cost/benefit

**The win is small in latency and moderate in limiter budget. Say so.**

| Change | Cold login | Warm reload | Steady state | Effort | Risk |
|---|---|---|---|---|---|
| `Access-Control-Max-Age` on Caddy | **no change** | −12 preflights (~200 ms) | −1 request per 30 s poll per EVM coin | one header | none |
| WSS for GLEEC | −12 preflights, −1 RTT, immunity to 429-on-OPTIONS | same | one socket replaces per-request HTTP | config transform (new code) | see §5 |
| `text/plain` | breaks GLEEC | — | — | — | fatal |
| Fix the SDK duplicate gap scan | **−42 RPCs per EVM asset** | −42 | — | SDK | already scoped in burst report §8 |

A preflight costs ~1 RTT. Measured against `evm-rpc.gleec.com` from Johannesburg
on a reused HTTP/2 connection: `OPTIONS` 220 ms, `POST` 199 ms. HTTP/2 removes
the handshake but not the round trip — the preflight is serialized before the
real request by spec. On a 1.5 s login burst, 12 concurrent preflights add
roughly one round trip of wall clock, once.

**So frame the cost as limiter budget, not milliseconds.** `evm-rpc.gleec.com`
serves ~20 req/s (burst report §4). Every preflight is a full charge against
that limiter (measured: 25 concurrent `OPTIONS` → 20 × 204 + 5 × 429, none
carrying `ACAO`), and a refused preflight is unrecoverable — the POST is never
sent, and KDF retries at 150 ms base backoff, exponential to 2 s
(`eth_rpc.rs:38-48`), re-issuing the preflight each time. Measured at N=12 cold:
**3–4 of 12 lost**; warm: **12/12 succeed and the burst runs 2.7× faster**.

### 4.1 Reconciling with "web logins measured faster than native"

`docs/KDF_LATENCY_REPORT.md:310-325` measured web ~4× faster than native. **That
result places no bound on what preflights cost.** It was measured on the
Electrum/UTXO path, where web uses WSS and pays *zero* preflights, and the
report itself names the transport as an unremovable confounder (`:327-345`,
`:355-359` — "the 4× gap … is *not yet isolated* to the transport"). There is
currently **no** web-vs-native measurement of the EVM HTTP path. Do not use the
4× figure in either direction here.

---

## 5. Risks and objections

**CSRF / Content-Type semantics — the objection does not apply to this
endpoint.** geth's content-type whitelist exists as CSRF defence, and that
defence only functions when CORS is closed. Measured: `evm-rpc.gleec.com`
answers an arbitrary hostile `Origin` with a 204 preflight and a readable 200
POST. Any website on the internet can already issue arbitrary JSON-RPC to it and
read the results; the only residual difference is the no-JS `<form>`
fire-and-forget vector, and there is nothing to steal (`eth_accounts` → `[]`,
`personal_*`/`admin_*` absent). Argue against a Caddy content-type rewrite on
different grounds: it makes the wallet depend on non-standard edge behaviour
that a future geth or Caddy upgrade breaks silently, and WSS is measured
available. Separately, file the exposed `debug` namespace as its own ticket.

**Vendor MITM of a same-origin proxy.** The usual framing (address↔IP linkage)
undersells it. Orange-clouding `dex.gleec.com` inserts Cloudflare into the TLS
path for the wallet's **own JavaScript** — for a non-custodial wallet that is a
party positioned to serve modified signing code. Fastly/Firebase already
terminate TLS so it is not a new category, but it is a second party in the
code-delivery path. Signing itself stays local (KDF wasm in-process). Also:
`firebase.json:45-50` has exactly one rewrite (`**` → `/index.html`) and
Firebase rewrites cannot target an arbitrary external origin, so this needs new
infrastructure. `dex.gleec.com` is DNS-only at Cloudflare today (measured: A
199.36.158.100, Fastly headers, no `cf-ray`), so the mechanism is reachable —
but whether Cloudflare-proxying a CNAME to `*.web.app` keeps Firebase's cert
provisioning healthy is untested.

**Node-operator ToS.** The ETH pool is entirely third-party free public RPC
(publicnode, Tenderly, NOWNodes, MEV Blocker); TRON uses TronGrid. Relaying
these through one branded aggregator changes the usage profile from many
per-user clients to a single high-volume aggregator, which several providers
restrict or price differently. **Unread — flag as a required legal/ops check.**
It does not apply to the max-age or WSS options, which keep traffic per-user and
direct.

**Pinning a stale or bad server by caching.** Both persistence candidates in
§3.3 fail the same way: one bad night pins a bad value forever. Any such cache
needs a TTL and an upward-probe path, or it is worse than re-learning.

**Native-parity regressions.** An app-side `kIsWeb`-gated transform is safe for
native by construction. A change pushed to the shared `GLEECBTC/coins` repo
(runtime updates enabled, per `build_config.json`) **reaches native too**. These
are not interchangeable delivery paths; only one is safe.

**WSS-specific risks, which the option table calls "conditional" for:**

1. **GLEEC has exactly one node.** Rewriting `url` → `ws_url` leaves zero HTTP
   fallback for the chain. Emitting *both* an HTTP and a WS instance per node is
   a requirement, not an alternative.
2. **It reintroduces the per-session handshake §3 declares extinct.**
   `create_websocket_transport` (`v2_activation.rs:1311-1318`) spawns a real
   socket per WS node at activation on a 20 s window, and its own comment
   ("we close the connection once we have the client version below") refers to
   the probe deleted in `543598231`. Remove that scaffolding first, or the fix
   trades a preflight for a wasted socket. `maybe_spawn_connection_loop`
   (`websocket_transport.rs:373-397`) already opens lazily on first use.
3. **The HTTP 429 signal is lost.** `is_retryable` (`eth_rpc.rs:314-339`)
   discriminates on `TransportError::Code(408|425|429)`, an HTTP status that
   cannot exist on a WebSocket frame. It degrades gracefully —
   `Transport(_) => true` at `:329` and JSON-RPC-level
   `RPC_CODE_TOO_MANY_REQUESTS` at `:333-336` still fire — but the team just
   shipped 429-backoff work whose primary discriminator this silently disables.
4. **Socket-drop behaviour is unexamined.** Nobody has read what happens to
   in-flight requests in the WS transport's `TimedMap`
   (`websocket_transport.rs:29`) when the socket drops, nor the reconnect path.
   This team has already been bitten by a timed-map hang in the proxy stack.
5. **Steady-state cost changes shape:** a `net_version` keepalive every 10 s per
   connected node (`websocket_transport.rs:36`, `:127-135`) — cheaper than the
   preflight traffic it replaces, but worth naming for mobile web.

---

## 6. Recommended sequence

### 6.1 Do first — one header, zero code, zero risk

Add `Access-Control-Max-Age: 7200` to the Caddy CORS block at
`evm-rpc.gleec.com`. **Justify it on warm reloads and the 30 s balance poll, not
on the login burst** — it does nothing for the cold burst, and a reviewer who
checks will find that out. Values above 7200 are decoration in Chrome; Safari
clamps to 600 either way.

Reference implementation already in this repo:
`contrib/tron-gasfree-proxy-debug/production/nginx-gasfree-location.conf:21`
(`add_header Access-Control-Max-Age "86400" always;`), which is what
`quicknode.gleec.com` and `defistats.gleec.com` serve today.

Two caveats:

* A second Gleec-operated endpoint has the same gap:
  `gleec-wallet-bouncer.gleec.com/v1` returns 204 with no max-age. (Others
  deviate rather than match: `moralis.gleec.com` 3600, `nft-antispam.gleec.com`
  600, `faucet.gleec.com` 600.) The "every other Gleec endpoint already sends
  86400" framing is not accurate.
* If Cloudflare 429s the *first* preflight of a session, no cache entry is
  created and the client is exactly where it is today. **Ship this together
  with burst report §8 item 1 (exempt `OPTIONS` from rate limiting), not as an
  alternative to it.** The preflight reaches the origin (`via: 1.1 Caddy`), so
  answering `OPTIONS` at the Cloudflare edge with a long max-age would remove
  that load entirely.

### 6.2 Measure before deciding anything else

**No preflight count has ever been taken from the real app.** Every number in
§2.5 is arithmetic over measured mechanics. `tool/web/bench_recorder.js`
provably cannot see `OPTIONS` — it wraps `fetch`/`XHR` from inside the page
(`:1-12`), and the browser issues preflights below JS; grep confirms no `OPTIONS`
handling exists. The instrument must be server-side: the node's access log, or
an instrumenting proxy in the style of `tool/kdf_rpc_instrument.py`.

Take two numbers before touching the transport: **OPTIONS count on a hard reload
vs a warm reload**, and **the same after the max-age header lands**. That sizes
§6.1 honestly and tells you whether §6.3 is worth its risk.

### 6.3 WSS for EVM — behind a per-chain flag, GLEEC only

**The endpoint is verified working**, which removes the blocker that three prior
open questions were built around. Against `Origin: https://dex.gleec.com`,
`wss://evm-ws.gleec.com` answered `eth_chainId` → `0x2ba1` (11169, matching
`net_version`), `eth_blockNumber`, `eth_getBalance`, `eth_getTransactionCount`,
`eth_call`, `web3_clientVersion` → geth `Go go1.22.8`, and `eth_subscribe`. A
full GLEEC-login-shaped burst (1 `eth_blockNumber` + 22 `eth_getBalance` + 21
`eth_getTransactionCount`) on one socket: **44 ok, 0 errors** (1263 ms in one
run, 368–574 ms in others). No OPTIONS is involved — a raw-socket probe confirms
the 101 upgrade carries no `access-control-*` headers at all.

**No KDF change is required.** `create_transport` dispatches purely on URL
scheme (`v2_activation.rs:1269-1271`), `websocket_transport.rs` has **zero**
`cfg(` occurrences and rides the wasm-capable `tokio-tungstenite-wasm` fork, and
`Web3Transport::Websocket` is ungated (`web3_transport/mod.rs:16`, `:22-24`).

**Scope it honestly:**

| Chain | HTTP nodes | with `ws_url` | WSS coverage |
|---|---|---|---|
| GLEEC | 1 | 1 | full |
| ETH / USDT-ERC20 / USDC-ERC20 | 4 | 2 | partial |
| **TRX** | 2 | **0** | **none** |
| **USDT-TRC20** | 3 | **0** | **none** |

TRON — the one family with an *unavoidable* `X-Auth-Payload` preflight (§1.1) —
cannot use this route at all, and `build_tron_api_client` rejects any non-http(s)
scheme outright (`v2_activation.rs:1241-1249`). And not every configured
`ws_url` works: of the 9 in the config, `wss://polygon.gateway.tenderly.co`
404s the upgrade and `wss://pol3.cipig.net:38755` completes the 101 then answers
`-32601` to every `eth_*` method. **7 of 9 work.**

**Patch sketch (app-side, `kIsWeb`-gated, native untouched):**

1. `sdk/packages/komodo_defi_rpc_methods/…/activation/evm_node.dart` — `EvmNode`
   currently parses `{url, komodo_proxy}` only and `toJson()` (`:22`) emits the
   same two, so the `ws_url` in the coins config is dropped before it ever
   reaches KDF (`grep -rn ws_url mm2src/` returns nothing — it is dead data on
   both sides). Either carry `wsUrl` through, or emit a second `EvmNode` whose
   `url` *is* the wss value.
2. New `EvmWssTransform` in
   `sdk/packages/komodo_coin_updates/lib/src/coins_config/config_transform.dart`.
   **This is new code, not a tweak of the Electrum one** —
   `WssWebsocketTransform.needsTransform` (`:228-231`) only fires when an
   `electrum` key exists, which EVM configs do not have. On `kIsWeb`, for each
   node with a `ws_url`, emit **both** the WS entry and the original HTTP entry
   so the pool retains fallback. Register it in `_transforms` (`:37-43`).
3. Before enabling: delete the eager 20 s temporary connection loop at
   `v2_activation.rs:1311-1318` (and its twin at `eth.rs:7167-7178`), and the
   two dead client-version error strings (§3.1).

Do **not** push this through the `GLEECBTC/coins` repo — runtime updates are
enabled and it would reach native.

### 6.4 What to ask node operators for

Only `evm-rpc.gleec.com` needs anything; every third-party node already sends a
max-age. In priority order: (1) exempt `OPTIONS` from the Cloudflare rate limit
— no client can work around a 429 on a preflight; (2) add
`Access-Control-Max-Age: 7200`; (3) add `Access-Control-Allow-Origin` to error
responses including Cloudflare-generated ones, so `retry-after` becomes readable
(burst report §8). Do **not** ask for a Content-Type rewrite (§5).

### 6.5 Explicitly not recommended

`text/plain`/`simple_request` config flag (§2.6); service worker (§2.6);
same-origin proxy (§5); caching KDF's Electrum handshake (§3.2); a persistent
"node facts" cache — chain id already comes from config
(`v2_activation.rs:897`/`:1115`), method support and CORS posture are never
probed, so there is nothing to store.

---

## 7. Corrections to the record

| Claim in circulation | Status |
|---|---|
| "The Gleec edge only allows `content-type`, so a `komodo_proxy` GLEEC node would fail preflight" | **Refuted.** The edge reflects `ACRH` verbatim (§2.3) |
| "Zero `komodo_proxy` nodes ⇒ `X-Auth-Payload` is absent from the TRON path" | **Wrong in effect.** Injected at runtime (§1.1) |
| "Max-age collapses the per-session EVM preflight count toward 1" | **Wrong.** No coalescing; cold burst is unchanged (§2.5) |
| "Chromium does not cap max-age" | **Wrong.** 7200 s (`preflight_result.cc:40`) |
| "Safari's cap is unknown" | **Known.** 600 s (`CrossOriginPreflightResultCache.cpp:43`) |
| "`text/plain` works on 7 of 11 endpoints" | **12 of 16** across the five chains; 5 of 7 for default-activated coins |
| "Every `ws_url` in the config works" | **7 of 9** (§6.3) |
| "There is no per-session handshake left" | True on HTTP only; false under the WSS recommendation (§5) |
| "The 1inch client wastes a preflight — free win" | **Cut.** Never confirmed to be in the wasm32 build graph |
| "Web is 4× faster than native, so preflights are cheap" | **Invalid inference** (§4.1) |
| `rpc.rs:275`'s `Access-Control-Max-Age: 3600` proves KDF handles this on web | **No.** Native-only (§1) |

---

## 8. Open questions / not established

1. **The only measurement that matters is missing:** no `OPTIONS` count from the
   real app, cold or warm, before or after any change. Needs a server-side
   instrument (§6.2). Every preflight number here is derived from endpoint
   probes plus source reading.
2. **Does KDF's IndexedDB survive reload and logout/login in the Flutter web
   build?** §3.3's "the gap scan is already cached" holds only if it does. If
   the DB is wiped or per-session-namespaced, every reload silently re-pays 42
   RPCs per EVM asset while KDF believes it is caching. **Highest-value next
   check, and it is app-side.**
3. **WS socket-drop semantics** — in-flight request fate in the `TimedMap`,
   reconnect path, and whether `wss://evm-ws.gleec.com` has its own rate limit
   under sustained load (one 44-call burst was clean; a request-counting limiter
   would not see multiplexed RPCs at all). Not established.
4. **Has KDF's wasm `WebsocketTransport` ever run end-to-end in the real web
   build?** The endpoints answer correctly from a browser and scheme dispatch is
   verified, but the KDF wasm client was not run against them.
5. **Wall-clock value of removing the duplicate gap scan on web.** The request
   count is verified; the time it saves on a warm browser login is not measured,
   and that is what decides whether the SDK work is worth doing.
6. **Node-operator ToS** for relaying free public RPC through an aggregator —
   unread (§5).
7. **Does Cloudflare-proxying `dex.gleec.com` break Firebase cert provisioning
   or its `vary: x-fh-requested-host` routing?** Untestable without a DNS change.
8. **Whether Chrome's normal reload (F5) sets a cache load flag on subresource
   fetches.** Hard reload almost certainly bypasses the preflight cache; normal
   reload almost certainly does not. The reload→flag mapping was not read.
9. **Is `mainnet.gateway.tenderly.co` (the other no-max-age endpoint) selected
   often enough to matter?** The pool shuffles per activation, so its real
   traffic share is unknown. If small, dropping it from the ETH pool in the
   Gleec-controlled coins repo is cheaper than anything else.
10. **Should the dead `quicknode.gleec.com` TRON route be removed?** It 404s on
    `/wallet/getnowblock` (its `/gasfree` route is healthy) yet is injected
    *first* into every mainnet TRON node list, costing a preflight and a failure
    per activation.
11. **Out of scope, noted:** the QA harness's `base_url`
    (`automated_testing/test_matrix.yaml:18`, `https://app.gleecwallet.com`)
    does not resolve. Production `dex.gleec.com` was last deployed 2026-04-17
    and does not carry the 8× rate increase yet — there is still time to land
    §6.1 before it reaches users.
