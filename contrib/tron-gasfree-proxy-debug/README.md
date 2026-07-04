# TRON gas-free proxy — local 401 reproduction stack

A self-contained Docker stack to reproduce and debug the **`401`** the wallet
gets on gas-free (`komodo_proxy`) calls to `https://quicknode.gleec.com/gasfree/...`.

Full root-cause write-up: [`docs/TRON_GASFREE_PROXY_401.md`](../../docs/TRON_GASFREE_PROXY_401.md).

## TL;DR of the bug

The proxy's `validation_middleware` runs on **every** route (including `gas_free`).
For a normal peer it asks **its own KDF node** — via the `peer_connection_healthcheck`
RPC — *"is this wallet's libp2p peer connected to our p2p network?"* If the answer
is not `true`, it returns **`401`** before the request ever reaches `open.gasfree.io`.

The wallet's KDF runs as a **WASM light node**: the proxy's KDF node can only answer
`true` if the wallet is **directly connected to that exact node** (gossipsub relays do
not forward the healthcheck to other relays). So this stack's whole purpose is to make
that check observable: flip the client between "meshed with the probe" and "not meshed"
and watch `peer_connection_healthcheck` (and the proxy's 401) follow.

## What runs

| Service | Role |
|---|---|
| `redis` | rate-limiter / address-status store the proxy needs |
| `kdf-probe` | the KDF node the **proxy** queries (`kdf_rpc_client`). netid-6133 seed. Analogue of the node behind quicknode.gleec.com |
| `kdf-client` | a wallet-like KDF node. Meshes with `kdf-probe` when its seednodes include it |
| `proxy` | `GLEECBTC/komodo-defi-proxy` built at the gas-free commit, `/gasfree` → `open.gasfree.io` |

The KDF binary is the exact Linux build the wallet ships
(`sdk/packages/komodo_defi_framework/linux/bin/kdf`), mounted read-only. It is
`x86-64`, so the KDF containers run `platform: linux/amd64` (emulated on Apple Silicon).

## Prerequisites

- Docker + Docker Compose v2 (`docker compose`), with amd64 emulation enabled
  (Docker Desktop: *Settings → General → Use Rosetta* on Apple Silicon).
- `jq` and `curl` on the host for `scripts/diagnose.sh` (optional but recommended).

## Run

```sh
cd contrib/tron-gasfree-proxy-debug
cp .env.example .env          # then edit .env (placeholders are fine for steps 1-2)
docker compose up --build -d  # first build compiles the proxy (Rust) — several minutes
docker compose logs -f        # watch startup; Ctrl-C to detach
```

The proxy waits for `kdf-probe`'s RPC before starting (it panics otherwise), so the
first healthy startup can take a minute after the KDF nodes come up.

## Debug procedure

### Step 1 — confirm the meshed (working) case

With `KDF_CLIENT_SEEDNODES=kdf-probe` (the default), the client connects directly to
the probe:

```sh
./scripts/diagnose.sh
```

Expected:
- both PeerIds print,
- **`peer_connection_healthcheck` → `{"result":true}`** (probe sees the client),
- the proxy logs show the request passing the gate (then a GasFree/upstream result —
  with placeholder HMAC creds that will be a GasFree-side error, *not* a proxy 401).

### Step 2 — reproduce the production 401 (client not meshed)

Point the client at a reachable subnet IP that has **no KDF** (so it starts but never
meshes with the probe — the same situation as a wallet that reaches *some* netid-6133
seeds but not the proxy's KDF node) and recreate it:

```sh
KDF_CLIENT_SEEDNODES=172.28.0.99 docker compose up -d --force-recreate --no-deps kdf-client
./scripts/diagnose.sh
```

> Do **not** use `KDF_CLIENT_SEEDNODES=""` — a non-seed node with p2p enabled and zero
> seednodes refuses to start (KDF requires ≥1 seednode unless `disable_p2p=true`), so it
> would crash-loop instead of reproducing the 401.

Expected: **`peer_connection_healthcheck` → `{"result":false}`**, and the proxy returns
`401` via the healthcheck branch (see Step 3 / `prove.sh` for the exact log line).

### Step 3 — see the exact proxy 401 branch (one command)

`scripts/prove.sh` runs the full A/B automatically: it recreates the client **connected**
then **disconnected**, and for each case sends a request through the proxy carrying a
well-formed `x-auth-payload` for the client's real PeerId. (The proxy checks
`peer_connection_healthcheck` *before* signature validity, so a dummy signature is enough
to reach — and reveal — the healthcheck branch.)

```sh
./scripts/prove.sh          # takes a few minutes (mesh formation under amd64 emulation)
```

Expected output — the two distinct proxy log lines that prove the gate:

```
CONNECTED    -> healthcheck {"result":true}   -> proxy: "Request has invalid signed message, returning 401"
DISCONNECTED -> healthcheck {"result":false}  -> proxy: "Peer isn't connected to KDF network, returning 401"
```

The **DISCONNECTED** line is the production failure, reproduced locally — the same line to
grep for in the production proxy logs:

```
docker compose logs proxy | grep -E "returning 401|not connected"
```

### Step 4 — end-to-end with a real signed request (optional)

`scripts/diagnose.sh` sends no `X-Auth-Payload`, so its 401 only proves the route is
gated. To exercise the full signed path, point a real KDF/wallet at the local proxy:

- `base_url`: `http://localhost:6150/gasfree/tron`, `service: "komodo_proxy"`,
- ensure that KDF node is on **netid 6133** and has the **probe's IP (`172.28.0.10`)
  in its seednodes** (so the probe can answer the healthcheck),
- because the proxy **bypasses validation for private/loopback source IPs**, send the
  request through something that sets `X-Forwarded-For` to a public IP (or test from a
  non-private address) to exercise the real validation path.

## How this maps to the production fix

If Step 1 yields `true` locally but production still 401s, the production proxy's KDF
node is **not** in the wallet's relay mesh. The fix is operational:

- run the proxy's KDF node on **netid 6133** (matching the wallet), and
- give it the **same netid-6133 seednodes the wallet uses** (the netid-6133 entries of
  `sdk/packages/komodo_defi_framework/assets/config/seed_nodes.json`), so it shares a
  relay with wallets.

A common seed relay is enough — the proxy's node does **not** have to be a seed wallets
dial directly. (Verified: see `prove.sh`'s topology vs. the relay-mesh experiment — two
light nodes that share only a common seed still complete `peer_connection_healthcheck`.)
The usual trap is **netid**: `seed_nodes.json` mixes 6133 and 8762 entries, so the proxy
node must use the 6133 ones and run on netid 6133.

Separately worth doing: widen the proxy's `MAX_SIGNATURE_EXP_SECS` (currently 15, equal
to the signer's 15s window → zero tolerance for browser clock drift).

## Testing with a local build of the app

Point a local wallet build at this proxy to exercise the **real gas-free flow** (creds +
forwarding + withdrawal UX) end-to-end.

### Credentials
The only secrets are the GasFree `api_key` / `api_secret`. They go in **`.env`** here —
`GASFREE_API_KEY` and `GASFREE_API_SECRET` — and nowhere else. The **app needs no
credentials**: in `komodo_proxy` mode the proxy holds them; the app only sends the proxy
`base_url` + `service_provider`. After editing `.env`:

```sh
docker compose up -d --force-recreate proxy
# verify creds work (should return provider data, not "Apikey not found"):
./scripts/run-app-local.sh   # its preflight checks this for you
```

### Run (macOS native — recommended)
```sh
./scripts/run-app-local.sh           # = flutter run -d macos with the dart-defines below
```
It launches the app with:
```
--dart-define=TRON_GASLESS_BASE_URL=http://localhost:6150/gasfree/tron
--dart-define=TRON_GASLESS_SERVICE_PROVIDER=<provider>
```
Requests to `localhost` are normally same-network, so the proxy **bypasses** its libp2p
healthcheck gate — validating creds, HMAC forwarding, and the gasless flow without needing
the app's KDF to mesh with the proxy. (The healthcheck gate itself is proven by `prove.sh`.)

> **If gas-free calls 401 locally:** the bypass only triggers when the proxy sees a
> private/loopback source IP. On some setups this machine presents a **public source IP /
> `X-Forwarded-For`** to the published port (observed during setup), which makes validation
> run and reject the app's request. Quick fix — mark the app's KDF peer Trusted:
> ```sh
> # find the peer id in the flutter/KDF console: "Local peer id: PeerId(\"12D3Koo...\")"
> ./scripts/trust-peer.sh 12D3Koo...
> ```

In-app: activate **TRX** + **USDT-TRC20**, fund the GasFree custody address, then withdraw
with the **gas-free** toggle on. Watch `docker compose logs -f proxy` for the forwarded
`/gasfree/...` calls.

### Web build (`chrome`) and the CORS fix — handled in NGINX (no proxy code change)
`open.gasfree.io` sits behind Cloudflare, which **403s browser-`Origin` requests and
returns no `Access-Control-Allow-Origin`**. The stock `gas_free` handler forwards the
upstream response **raw**, so a stock proxy is CORS-blocked for WASM/browser callers.

This stack solves that **entirely in the NGINX edge** (`nginx/nginx.conf`) in front of the
**stock** proxy — no Rust fork. NGINX:
- strips `Origin`/`Referer` before the proxy forwards upstream (so Cloudflare stops 403-ing),
- adds `Access-Control-Allow-*` on responses (hiding the proxy's own to avoid duplicates),
- (local-debug) clears `X-Forwarded-For` so the proxy sees internal traffic and bypasses
  its libp2p gate — so the web app needs no per-peer trusting.

Topology: app → **NGINX `:6160`** → stock proxy `:6150` → open.gasfree.io. The diagnostics
(`prove.sh`, `diagnose.sh`, `check-creds.sh`) still hit the proxy directly on `:6150`.
Verified: a browser-`Origin` GET via `:6160` returns `200` + data + `access-control-allow-origin: *`,
and OPTIONS preflight returns `204` + CORS.

**For production**: add the same `Origin`/`Referer` strip + `Access-Control-Allow-*` to the
NGINX (or equivalent edge) already fronting `quicknode.gleec.com` — **no komodo-defi-proxy
fork required**. Keep real `X-Forwarded-For` in production (don't clear it) and fix the
healthcheck `401` by meshing the proxy's KDF node onto netid 6133.

> `proxy/gasfree-cors.patch` (the in-proxy Rust alternative) is kept for reference only and
> is **not** applied by the Dockerfile.

## Logs & observability (local debug only)

The NGINX edge (OpenResty) is the richest signal — it sees every request and what GasFree
actually returned:

```sh
docker compose logs -f nginx
```
- **Access log** (every request): `<time> GET "<uri>" client=<status> upstream=<status> rt=<s> urt=<s> bytes=<n>`.
  `upstream=` is the status the proxy/GasFree returned, and the path shows e.g. whether
  `…/gasfree/submit` fired.
- **`[gasfree-error]` lines**: the upstream **response body**, logged whenever it's an error —
  HTTP 4xx/5xx (`Apikey not found`, `Authorization hash not match`, Cloudflare `error code: 1010`)
  **or** a GasFree envelope `code` ≠ 200 (business errors, which GasFree returns as HTTP 200 +
  `{"code":<n>,...}`). Capped at 4 KB.

The proxy logs only its own validation decisions (received / by-passed / `401`):
```sh
docker compose logs -f proxy
```
It runs at `RUST_LOG=info` (set in compose) to drop the default `Trace`/`mio`/`tokio` noise —
override with `PROXY_RUST_LOG=debug` (or `trace`) in `.env` if you need the firehose.

> This logging is **local-debug only** (verbose, logs response bodies, bypasses the gate) —
> it lives entirely in `nginx/nginx.conf` + the compose `RUST_LOG` env; nothing ships to prod.

## Teardown

```sh
docker compose down -v
```

## Security notes

- `.env` is gitignored. The only genuinely sensitive values are
  `GASFREE_API_KEY` / `GASFREE_API_SECRET`; everything else is local throwaway.
- Entrypoints render configs without printing secrets and no script enables shell
  tracing, so credentials are not emitted to logs.
