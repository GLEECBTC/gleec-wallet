# Production proxy checklist

These files capture the production requirements that the local debug stack
proved but cannot apply directly to `quicknode.gleec.com`. They are templates,
not deployment evidence. Production remains blocked until Operations records
evidence for every gate below.

## KDF probe node

Use `kdf-mm2.netid6133.template.json` as the shape for the KDF node referenced by the
proxy's `kdf_rpc_client`.

Required properties:
- `netid` is `6133`.
- `disable_p2p` is `false`.
- `i_am_seed` is `false` unless this host is intentionally operating as a seed.
- `seednodes` contains the wallet's netid-6133 WSS seed mesh:
  `seed03.kmdefi.net`, `kdfseed1.decker.im`, `staking1.gleec.com`,
  `staking2.gleec.com`.
- The proxy config's `kdf_rpc_client` URL and `kdf_rpc_password` match this node's RPC
  bind address, port, and password.

## NGINX edge

Use `nginx-gasfree-location.conf` as the `/gasfree/` location shape.

Required properties:
- Clear browser request metadata (`Origin`, `Referer`) before forwarding.
- Add `Access-Control-Allow-*` headers on every browser-facing response, including
  successful forwarded GasFree responses.
- Forward a real, single-valued client IP in `X-Forwarded-For`.
- Never pass through client-supplied `X-Forwarded-For`, and never clear XFF in
  production.

## Required operational gates

- **Clock integrity:** synchronize the proxy, KDF probe, and edge with an
  authenticated time source. Measure and alert on skew before it exceeds the
  proxy's signed-message tolerance. Exercise accepted, expired, and
  future-dated `X-Auth-Payload` boundaries without widening the tolerance.
- **Rate limiting:** configure both per-client and global request limits at the
  trusted edge, return `429` with `Retry-After`, and prove that spoofed
  `X-Forwarded-For` values cannot select the private-IP bypass or evade a
  limit. Document the approved limits and burst budget in the deployment.
- **Credential isolation:** source GasFree HMAC and KDF RPC credentials from the
  production secret manager, expose them only to the process that needs them,
  prevent command-line/log/metric/support-payload exposure, and prove rotation
  plus revocation. No client build may contain these credentials.
- **Error sanitation:** browser responses, logs, and support data may contain
  only stable error codes and correlation IDs. Do not forward or log raw
  provider bodies, authorization payloads, signatures, addresses, amounts, or
  credentials.
- **Health and readiness:** provide separate liveness and readiness checks.
  Readiness must fail when the local KDF RPC is unavailable, the netid-6133
  probe is unhealthy, required peers cannot authenticate, or the GasFree route
  cannot serve a sanitized response. Health endpoints must not bypass auth on
  forwarded GasFree routes.
- **Metrics and alerts:** emit PII-free counts and latency for auth rejection,
  clock rejection, rate limiting, upstream status classes, KDF peer health,
  readiness, and relay availability. Alert on sustained failure rate, latency,
  peer disconnects, clock skew, and credential failures; verify alert routing
  before rollout.
- **CORS and trusted IP:** run browser preflight plus forwarded success/error
  checks through the real edge. Configure `real_ip_header` and
  `set_real_ip_from` only for known load-balancer ranges, then prove direct and
  spoofed requests cannot override `$remote_addr`.
- **Rollback:** retain the previous immutable proxy image and edge config.
  Test a rollback that disables new receives/activations while leaving Standard
  TRON, custody-balance visibility, pending-transfer reconciliation, and
  recovery available. Record the owner, trigger thresholds, and rollback time.

## Smoke checks

After deployment, run:

```sh
./scripts/check-prod-gasfree.sh
```

For the definitive 401 check, pass a real wallet KDF PeerId and the proxy host's KDF RPC
settings:

```sh
PROD_KDF_RPC_URL=http://127.0.0.1:7783 \
PROD_KDF_RPC_PASSWORD=... \
WALLET_PEER_ID=12D3Koo... \
./scripts/check-prod-gasfree.sh
```

Expected `peer_connection_healthcheck` result: `{"result":true}`.

The smoke script covers only CORS presence and an optional direct KDF peer
healthcheck. It does not prove rate limits, clock boundaries, credential
rotation, sanitization, monitoring, alerting, or rollback; those require signed
Operations evidence from the production topology.
