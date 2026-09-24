# Unified Swap — live test brief

This round tests the **Swap** and **Activity** destinations of the Swap menu entry. **Advanced** is the existing trading interface, unchanged.

**Status:** unit-tested, and checked live against the pinned engine (KDF `feat/lifi-integration@4872ef2`, native and WebAssembly) with a throwaway wallet holding no funds. Quotes, the supported-coin list and every quote error the engine can raise locally were recorded and parse correctly (`komodo_defi_harness/test/routed_swap_live_capture_test.dart`). **No real swap has run on mainnet yet.** Start with small amounts, and move to larger ones only after the small ones behave as described below.

**Quote limit while you test.** Cross-network prices come from the aggregator's public API without a key: **75 quotes every two hours for your network address**, shared by every device behind it. The form now spends about one quote per price, a comparison costs one more, and refreshing stops when you leave it alone. If you do hit the limit, cross-network prices pause and come back on their own, while order-book prices keep working. Note when it happened.

## What changed since the last brief

- **GLEEC and GRC-20 pairs no longer read as an outage.** They trade on the order book only, and the aggregator does not serve their network. They were being sent to it anyway, and the form said "We couldn't check swap options". Now:
  - only sources that can price a pair are asked;
  - with no order-book offer, the form says "No swap is available…", adding that GLEEC trades only on the order book.

  The same fix covers KCC, ETC, TAO and the other networks the aggregator doesn't serve.
- **A pair nobody can swap says why, and what to do.** For example, an asset only reachable across networks paired with one that trades only on the order book. Each message names the network reason and offers **Choose another asset**.
- **The picker offers every supported asset,** active or not. Choosing an inactive one activates it first, in the open. Nothing is activated just by opening the form. An inactive asset arriving from a coin page or a link shows **Activate {asset}**.
- **Choosing what to receive shows what you can reach.** Assets your pay asset can't be swapped for are listed apart, under "Not available with {asset}", with the reason.
- **If part of the asset list can't load,** the picker says the list may be incomplete and offers **Try again**. It keeps the last list rather than dropping assets.
- **Quotes are spent carefully** (see the limit above):
  - Each refresh prices the cheapest route only. The fastest is priced when you open **Compare options**, and kept fresh while you compare.
  - Refreshing runs every 30 seconds while the form is on screen and the app is in front. It stops after five minutes without a touch; the quote then expires, and **Refresh quote** brings it back.
  - Returning to the same pair and amount within 15 seconds reuses the last price. That includes starting a quote you reviewed moments ago.
  - A rate limit is waited out quietly, for longer each time.
- **A token with none of its network's own coin is stopped at the form.** For example, USDC on Polygon with no POL: "You need some POL on Polygon to pay the network fees." Such a quote used to fail as an unexplained service error.
- **Max on a network's own coin keeps back three times the quoted gas.** The engine checks the balance at start against a higher figure than the quote shows. If the check still fails, nothing is sent and the result screen shows the shortfall.
- **Slippage can be changed.** **Compare options** (or **Details**) shows the allowance for cross-network routes, with presets of 0.5%, 1% and 2% and a custom 0.05–5%. It warns above 1%. It lasts for the session only.
- **`/swap` works as an address,** as well as `/dex`, with the same link parameters.

Unchanged from the last brief:
- the atomic "receive at least" figure is what the order enforces;
- progress never says funds are safe after they moved;
- swaps survive navigation and sign-out;
- Activity lists both kinds of swap;
- the review re-prices before starting;
- a first routed swap shows the provider's terms.

What remains out of scope, and why, is in [`SWAP_DEFERRED_FEATURES.md`](SWAP_DEFERRED_FEATURES.md).

## What to run with real funds

Use small amounts: about $5–10 each. The cheapest network fees are on Arbitrum, Base and Polygon. Run these in order, and stop at the first surprise.

1. **Same network, native coin:** ETH → USDC on Arbitrum (or Base). No approval step; one transaction.
2. **Same network, token:** USDC → ETH on the same network. Expect an exact-amount approval ("Approve exactly … & start"), then the swap.
3. **Across networks:** USDC on Polygon → USDC on Arbitrum. Expect the bridge step and "You can leave this screen". Leave, and come back through Activity or the notice.
4. **Max on a native coin:** Max on ETH (Arbitrum) → USDC. Check the kept-back amount the form states, and that the swap starts.
5. **Cancel before anything is sent:** start a token sale and cancel while it says "Checking…" or while approving. The result should say whether an approval went out.
6. **Order book:** a small GLEEC or GRC-20 swap, if an offer exists. With no offer, check the "No swap is available" message and its GLEEC line.

## What to try

For each item, note what the screen said before you confirmed and what actually happened. The most valuable report is *"it showed me X and I got Y"*.

### Entry
1. **Invalid amounts:** enter an empty amount, `0`, `1..2`, more decimals than the asset allows, more than your balance, and your exact balance. Each should get its own message, and **Review swap** should stay disabled.
2. **Max:** selling ETH (or another network's own coin) should leave a fee reserve and say so. Selling a token should use the whole balance.
3. **A token with none of its network's coin:** "You need some … to pay the network fees", and nothing priced. With some but too little, you should see "You need about … for network fees".
4. **Switch pay and receive.** The amount should clear, because it was in the other asset's units.
5. **USD entry:** toggle it, type a dollar amount, and check the token amount beside it.
6. **Same ticker, different networks** (USDC on Ethereum and on Arbitrum): the picker should mark the rows **Same ticker**, and the review should show each asset's network and contract.
7. **An asset that isn't active:**
   - Pick one from **All**: it should activate, then take its place in the form.
   - Open a coin page's **Swap** for an inactive coin, or a `/swap?from_currency=…` link: the form should show **Activate {asset}**, and nothing is priced until you do.
8. **GLEEC as what you pay:**
   - Open the receive picker: order-book assets appear normally; cross-network-only tokens appear under "Not available with GLEEC", with the reason.
   - With no offer on the order book, the form should say no swap is available, not that it couldn't check.

### Options and review
9. **Compare options:** a cross-network price shows **Compare options**. Opening it prices the fastest route ("Checking for a faster route…"). **Best net return** appears only when at least two options can be compared.
10. **Slippage:** in the comparison, change it to 1% and 2%, then set a custom value. Every price should update. Above 1% there should be a warning. The review's **Costs & protection** should show the new value.
11. **Leave the form alone for six minutes.** Refreshing should stop, the quote expire, and **Refresh quote** appear. Switching to another app or tab should stop refreshing at once.
12. **Selling ERC-20 tokens:** the review should ask for an exact amount, never unlimited. A token that needs its permission reset first should say "Continue with reset".
13. **Leave the review while "Checking…"**. Nothing should start.

### Execution
14. **Same-chain routed swap:** the timeline, the hero text on each step, and the result.
15. **Cross-chain routed swap:** the bridge step; leave and come back.
16. **Cancel:** **Cancel swap** appears only before anything is sent. The confirmation says whether an approval already went out. Cancelling after the swap is sent should say so gently.
17. **Atomic swap:** the matching step, and the result. An amount larger than any single order should say no swap is available instead of hanging.

### Activity and recovery
18. **Refunds, partial fills and unfamiliar tokens:** a refunded or partially filled swap, or one that delivered another token, should appear under the right filter. Its detail should answer *What happened? · Where are the funds? · What can I do now?*
19. **Evidence and support:** **View evidence** should show hashes with explorer links. **Contact Gleec support** copies a support payload: ids, hashes and the provider's reference, but no addresses. On web, a provider error has no provider reference; the engine can't read it there.

## How to report

- Open the swap in Activity, tap **View evidence**, then **Copy details for support**, and paste that into the report.
- Add screenshots of the review before you started and of the result.
- Note your window width if the layout looked wrong. Below 960 px of swap area the review is full screen; wider, it opens beside the form.
- If cross-network prices paused, say roughly how many prices you had looked at in the previous two hours.
- **Settings → Export swap data** includes the full routed history: timestamps, requested amounts, the accepted minimum, outcome, funds movement and gas spent.
