# Unified swap release checklist

Current delivery: [SDK #407](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/407)
and [wallet #3557](https://github.com/GLEECBTC/gleec-wallet/pull/3557), specs
`7c388ea`, KDF `35f0bde`. See [validation evidence](KDF_LIFI_VALIDATION_2026-10-26.md)
and [release notes](KDF_LIFI_RELEASE_NOTES.md). This checklist records release
work; it does not authorize merges, deployment or funded transactions.

## Integration gates

| Gate | Status |
|---|---|
| Seven matching KDF archives | Complete. Linux rerun succeeded; all seven downloads and sidecars match the strict manifest. Coins pin preserved. |
| Commission | Confirmed: `gleec-dex-staging`, 178 + 22 bps. Wallet supplies typed startup policy, KDF requests/validates it, proxy retains API key. Defaults, overrides, disable and invalid settings covered. |
| Fee models | SDK supplies missing Base `op_stack`, Mantle `mantle`, Monad `monad`, Avalanche `avalanche` settings for bundled/cached/refreshed configs. Explicit settings remain authoritative; tokens inherit platforms. |
| Max and accepted minimum | KDF Max replaces client reserve multipliers. Concrete comparisons and execution; exact provider minimum, no extra 0.3% reduction. Review snapshots and reacceptance covered. |
| Funding and payouts | Required balance remains separate from estimated spending; measured/provider amounts remain optional and distinct. Approval/gas evidence retained on failures. |
| App, SDK and harness checks | Recorded with commands and final counts in the validation evidence. Analysis has existing diagnostics; it is not claimed to be clean. |
| Web/macOS builds | Web release and unsigned macOS validation recorded. Signed macOS distribution requires the release provisioning profile. |
| Native proxy quotes | Unfunded disposable wallet: Arbitrum/Base exact quotes, included 2% fee, funding totals, typed Max insufficiency. No funds committed. |
| Upstream KDF tests | Still failing: `validate_dex_fee_invalid_sender_erc`, `firo_lelantus_tx_details`, `test_block_header_utxo_loop`. Separate from artifact recovery. |

## Release gates owned by people

- Run [the funded round](SWAP_LIVE_TEST_BRIEF.md) on the PR preview; a person
  presses every control that commits funds. Not run for this delivery.
- Review production proxy capacity, per-peer limits and monitoring with the KDF
  team. The configured proxy is `https://quicknode.gleec.com/lifi`; limits are
  shared, and quote/status polling must fit the production allocation.
- Complete the [moderated usability session](SWAP_USABILITY_SESSION.md) and the
  release-owner review of UI/preview results. No new usability session was run.
- Resolve or explicitly disposition upstream CI failures before release.
- Prepare signing and the release version/changelog under the release process.

## Publication and later merge order

Publish SDK #407 first, then repin wallet #3557 to that published SDK commit.
The PRs stay open. If the SDK later squash-merges, repin the wallet to the squash
commit only after proving its tree matches the reviewed SDK head. KDF/specs/coins
upstream merges and any later engine repin are separate work. Such a repin must
again verify all seven matching archives, preserve the coins configuration and
recheck the atomic payment/refund gas constants.

SDK #389 and wallet #3507 were already merged; this delivery continues their
funding/payout work. The older Max multipliers and minimum reduction are
superseded, not release prerequisites. Scope remains Phase 1 EVM swaps.
