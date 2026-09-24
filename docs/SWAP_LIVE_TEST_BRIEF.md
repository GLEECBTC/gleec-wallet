# Unified Swap — live test brief

This round tests the **Swap** and **Activity** destinations of the Swap menu entry. **Advanced** is the existing trading interface, unchanged.

**Status:** unit-tested and checked against the pinned engine's wire format (KDF `feat/lifi-integration@4872ef2`). It has **not yet run real swaps on mainnet.** Start with small amounts, and move to larger ones only after the small ones behave as described below.

## What changed since the last brief

The four money-safety defects in the previous brief are fixed.

- **The atomic "receive at least" figure is now what the order enforces.** An atomic quote is priced against the single best maker order that can fill the whole amount. The minimum is amount × that order's price, less any fee taken from the received side. An amount no single order can fill is reported as "no swap available" instead of spinning forever.
- **Progress never says funds are safe after they moved.** Each stage says what is happening: approving spends a network fee, and sending can no longer be cancelled. Failure screens distinguish "nothing was sent", "only fees were spent" and "may have been sent".
- **Swaps survive navigation.** Running swaps live app-wide, not on the screen that started them. Leaving the progress screen, switching destination or visiting the wallet keeps the swap followed. A swap still running at sign-out is picked up again at the next sign-in. When it finishes, a notice appears wherever you are, with **View**.
- **Activity shows both kinds of swap.** Routed swaps come from `routed_swap::history`, and atomic swaps from the recent-swaps list. Activity has three filters:
  - **Active** — still running;
  - **Needs attention** — finished, but not as asked, or with funds or a permission to check;
  - **Completed**.

  If one source can't be read, the list says it may be incomplete. It never says "no swaps".

Also new:

- **Quotes refresh automatically** every 30 seconds while the form is on screen, and expire after 60. A rate limit pauses refreshing and asks for the default route only.
- **The review re-prices before starting.**
  - A lower minimum, or a total cost more than 10% and $0.50 higher, stops for old-versus-new consent.
  - A change in the steps sends you back to fresh options.
  - If the engine refuses mid-swap because the price moved (`QuoteWorsened`), the result screen offers the new price for consent.
- **A first routed swap shows the LI.FI terms**, with a link, above the start button. Starting the swap records acceptance for that wallet.
- **Max keeps back network fees.** For a network's own coin it holds back the estimated gas (probe quote × 1.25) and says how much. A token uses its whole balance. Atomic swaps use the engine's own maximum.
- **Other additions:** USD amount entry (tap the dollar line under the amount), a rate line (tap to invert), price impact with a warning at 5% or more, and a smart default pair.

What remains out of scope, and why, is in [`SWAP_DEFERRED_FEATURES.md`](SWAP_DEFERRED_FEATURES.md).

## What to try

For each item, note what the screen said before you confirmed and what actually happened. The most valuable report is *"it showed me X and I got Y"*.

### Entry
1. **Invalid amounts:** enter an empty amount, `0`, `1..2`, more decimals than the asset allows, more than your balance, and your exact balance. Each should get its own message, and **Review swap** should stay disabled.
2. **Max:** selling ETH (or another network's own coin) should leave a fee reserve and say so. Selling a token should use the whole balance.
3. **Selling a token with too little of the network's own coin** for gas should give the "You need about … for network fees" message.
4. **Switch pay and receive.** The amount should clear, because it was in the other asset's units.
5. **USD entry:** toggle it, type a dollar amount, and check the token amount beside it.
6. **Same ticker, different networks** (USDC on Ethereum and on Arbitrum): the picker should mark the rows **Same ticker**, and the review should show each asset's network and contract.
7. **An asset that isn't active:** it should offer **Activate**, then continue.

### Options and review
8. **With several options:** **Best net return** should appear only when at least two options can be compared. **Compare options** lists the minimum, total cost, time, number of steps and the permission asked for.
9. **Wait on the form for over a minute.** The countdown should appear from 20 s, then **Refresh quote**.
10. **Selling ERC-20 tokens:** the review should ask for an exact amount ("Approve exactly … & start"), never unlimited. A token that needs its permission reset first should say "Continue with reset".
11. **Leave the review while "Checking…"**. Nothing should start.

### Execution
12. **Same-chain routed swap**, e.g. ETH → USDC on Ethereum: the timeline, the hero text on each step, and the result.
13. **Cross-chain routed swap**, e.g. ETH on Ethereum → USDC on Arbitrum: the bridge step and "You can leave this screen". Leave, then come back through Activity or the notice.
14. **Cancel:** **Cancel swap** appears only before anything is sent. The confirmation says whether an approval already went out. Cancelling after the swap is sent should say so gently.
15. **Atomic swap** (GLEEC or a GRC-20 pair): the matching step, and the result. An amount larger than any single order should say no swap is available instead of hanging.

### Activity and recovery
16. **Refunds, partial fills and unfamiliar tokens:** a refunded or partially filled swap, or one that delivered another token, should appear under the right filter. Its detail should answer *What happened? · Where are the funds? · What can I do now?*
17. **Evidence and support:** **View evidence** should show hashes with explorer links. **Contact Gleec support** copies a support payload: ids, hashes and the provider's reference, but no addresses.

## How to report

- Open the swap in Activity, tap **View evidence**, then **Copy details for support**, and paste that into the report.
- Add screenshots of the review before you started and of the result.
- Note your window width if the layout looked wrong. Below 960 px of swap area the review is full screen; wider, it opens beside the form.
- **Settings → Export swap data** now includes the full routed history: timestamps, requested amounts, the accepted minimum, outcome, funds movement and gas spent.
