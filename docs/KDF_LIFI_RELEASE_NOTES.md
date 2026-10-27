# KDF LI.FI integration release notes

The wallet now uses KDF `35f0bde` for Phase 1 EVM swaps, following the routed-swap
contract at specs `7c388ea`.

- Swap state survives layout breakpoints. Review and replacement starts recheck
  policy, terms and quote-specific funding. Background recovery, approval
  timelines and external link handling include the fixes from #3554–#3556.
- Release builds retain the existing coin revision and fetch its exact files and
  icons, including when reusing a cache. Runtime coin updates remain enabled.
- Max asks KDF for the largest fundable amount and keeps it as form intent.
  Refresh updates the amount, receive minimum and funding together. Typing an
  amount returns to exact mode, and the review freezes the accepted quote.
- Affordability uses KDF's required gas balance separately from estimated gas
  spending. Insufficient-balance errors name the asset and retain known locked
  balances. A rejected Max never enables a full-balance swap.
- The quoted minimum is shown unchanged. KDF handles tighter-slippage retries;
  a worse quote needs fresh acceptance. Execution always sends a concrete amount.
- KDF receives the confirmed commission policy at every startup: integrator
  `gleec-dex-staging`, 178 bps commission and 22 bps LI.FI share. The combined
  included fee is shown once. Build overrides and explicit disable are documented
  in [BUILD_RUN_APP.md](BUILD_RUN_APP.md); invalid policy is rejected.
- Missing native fee models for Base, Mantle, Monad and Avalanche are normalized
  on bundled, cached and refreshed startup. Explicit settings are preserved.
- Activity and exports retain measured payouts separately from provider reports,
  including partial/refund and missing-measurement outcomes. Failed swaps retain
  approval hashes, allowance warnings and known gas spending. Absent fee records
  are not evidence that nothing was spent.

The SDK keeps commission unset by default. Applications supply deployment policy;
KDF requests and validates the allocation and the proxy holds the API key.

All seven archive pins and validation results are recorded in
[KDF_LIFI_VALIDATION_2026-10-26.md](KDF_LIFI_VALIDATION_2026-10-26.md).
A human-operated funded round is still required before release. This does not
add external recipients, Tron/BTC routing or production deployment.
