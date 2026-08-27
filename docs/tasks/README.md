# Follow-up tasks from the EVM RPC burst investigation

Three self-contained work items arising from
[`KDF_RPC_BURST_REPORT.md`](../KDF_RPC_BURST_REPORT.md) and the source-level audit of it. Each file
stands alone — repo, branch, pinned commit, evidence with `file:line`, what not to do, and what
"done" means.

**They are independent.** No ordering constraint between them, and none blocks another. The one
cross-reference — node ordering, item 5 of the KDF task — is an *optimisation* for part 2 of the
gap-scan task, not a prerequisite.

| Task | Repo | Why it matters |
|---|---|---|
| [KDF_RPC_POOL_FIXES.md](KDF_RPC_POOL_FIXES.md) | `komodo-defi-framework` @ `25f6e1f0b` | Five defects that make KDF hammer a rate-limited node harder than it should. All measurement-independent. |
| [SDK_GAP_SCAN_AND_WEBSOCKET.md](SDK_GAP_SCAN_AND_WEBSOCKET.md) | wallet / `sdk` | The EVM HD gap scan repeats every 30s forever — the largest single load reduction available. Plus reaching the WebSocket endpoints the config already publishes, across all 13 EVM chains. |
| [SDK_BALANCE_STREAMERS.md](SDK_BALANCE_STREAMERS.md) | wallet / `sdk` | One KDF balance streamer per token where the platform streamer already covers them all — the only *permanent* node load. Plus a polling fallback that cannot observe a balance change. |

## Two things that decide how to read all three

**The report is a moving target.** `KDF_RPC_BURST_REPORT.md` was edited on 2026-08-07, after the
audit that produced these tasks. §7 in particular was rewritten. Re-read the section before
"correcting" it — a correction written against the old wording will introduce a new error.

**The KDF worktree is dirty.** `perf/evm-rpc-429-backoff` carried ~437 uncommitted lines across
`eth_rpc.rs`, `eth_rpc_retry_tests.rs`, `v2_activation.rs` and `nft.rs` — a
`Retry::Allowed`/`Retry::Forbidden` enum, `MAX_RPC_RETRY_ELAPSED = 30s`, and JSON-RPC `-32005` /
`-32029` classification. Run `git diff` before assuming any KDF item is unimplemented.

## What is *not* in these tasks, and why

- **A starting-concurrency value.** The report's §6 recommends 6; the raw data contradicts it once
  tokens are on (37 × 429 in the six-token arm). The value decision waits on the rate-ladder
  benchmark. See the "Deliberately out of scope" section of the KDF task.
- **The `text/plain` preflight fix.** Measured **HTTP 415** from the shipped endpoint for every
  CORS-safelisted content type. Not implementable client-side.
- **§8's "classify opaque browser transport failures as backpressure".** Already satisfied in
  `is_retryable`. It needs correcting in the report, not implementing.
- **Node-side fixes** — `Access-Control-Max-Age`, exempting `OPTIONS` from the rate limiter — belong
  with the node operator, not in either repo.
