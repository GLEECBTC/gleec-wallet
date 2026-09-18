# Wallet and engine diagnostics

Use [TESTING.md](../docs/TESTING.md) for release gates and
[WALLET_LOAD_MEASUREMENT.md](../docs/WALLET_LOAD_MEASUREMENT.md) for measurement
controls, interpretation and privacy limits. Raw captures belong outside the
release checkout.

| Tool | Purpose | Platform |
|---|---|---|
| `kdf_latency_probe.py` | Engine activation timings and RPC counts; `--plan-only` inspects batching | Native; `--web` serves browser probe |
| `web/kdf_web_probe.html` | Run KDF Wasm without Flutter | Browser |
| `parse_wallet_load_log.dart` | Parse app RPC, activation, balance and frame timing logs | Any |
| `kdf_fd_probe.py` | Sample native KDF file-descriptor use; compare binaries | macOS |
| `kdf_rpc_burst_bench.py` | Measure per-scenario RPC traffic | Native |
| `kdf_rpc_instrument.py` | Instrument RPC burst runs | Native |
| `web/bench_serve.py`, `web/bench_recorder.js` | Serve and record the real web app | Browser |
| `bench_web_jank.sh` | Repeat and compare login frame captures | Browser |
| `evm_ws_probe.py` | Probe WebSocket endpoints with/without Origin and compare baseline | Network |
| `verify_web_deploy.sh` | Verify served wallet wrappers and security/cache headers | Network |
| `web/bitrefill_widget.test.mjs` | Regression-test payment wrapper behavior | Node |

## Common commands

```bash
python3 tool/kdf_latency_probe.py --plan-only
python3 tool/kdf_latency_probe.py --quick --kdf /path/to/kdf
python3 tool/kdf_latency_probe.py --web
python3 tool/kdf_fd_probe.py --kdf before=/path/to/before --kdf after=/path/to/after --idle-seconds 30
python3 tool/evm_ws_probe.py --baseline docs/assets/evm_ws_probe/evm_ws_probe_2026-08-07.json
dart run tool/parse_wallet_load_log.dart /path/to/log --json
python3 tool/web/bench_serve.py --root build/web --port 8123
tool/bench_web_jank.sh baseline 5
tool/bench_web_jank.sh candidate 5
tool/bench_web_jank.sh --compare baseline candidate
node --test tool/web/bitrefill_widget.test.mjs
```

Inspect each tool's `--help` for supported scenarios. The KDF binary is an SDK
build artifact; `--kdf` can select a locally built engine. Native probes obtain
the seed from `KDF_TEST_SEED`. KDF receives its configuration in process
arguments, so use an unfunded disposable seed. Do not retain wallet databases or
include secrets in shared captures.

The WebSocket JSON baseline is a dated comparison fixture, not a claim about
current endpoint availability. Repeat probes with spacing; browser Origin
behavior differs from native clients. The FD probe measures KDF alone: Flutter,
storage and other application sockets also consume the device's limit.

For deployments, use the explicit project/target and verification steps in
[WEB_HOSTING_TOPOLOGY.md](../docs/WEB_HOSTING_TOPOLOGY.md). Diagnostics do not
publish builds or change hosting configuration.
