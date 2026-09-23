# Unified Swap — live test brief

**Status: testnet / tiny amounts only. Do not run mainnet value through the Swap
segment yet.** The reasons are below, and the one that decides it is the first.

Scope of this brief: the **Swap** and **Activity** segments of the Swap menu
entry. The **Advanced** segment is the existing trading interface, unchanged,
and is not what this round is testing.

## Why not mainnet yet

Two defects can cost a tester money with no warning on screen, and neither is
fixed:

1. **A "guaranteed" atomic amount can legitimately under-deliver.** The
   headline "You receive at least X" is computed by walking several maker
   orders, but the order actually submitted enforces only *volume × worst
   price*. On a thin book — GLEEC and GRC-20 tokens especially — the fill can
   return meaningfully less than the figure labelled as a guarantee, and no
   "price changed" prompt fires, because the pre-start re-check recomputes the
   same inflated number and compares like with like.
2. **The progress screen says "Nothing has left your wallet yet" after funds
   have moved.** It keeps saying it through "Approving token…" (the ERC-20
   approval is already on-chain and gas is spent) and through "Confirming…"
   (the swap transaction is broadcast). A tester is told their money is safe at
   exactly the moment it is not — and that is the state that invites a retry.

Until both are closed, mainnet testing risks losing value to a number the app
presented as a floor.

## Known broken — please don't file these

These are confirmed and already understood. Reporting them again costs you time
and tells us nothing new.

- **Activity does not show routed swaps.** The history parser expects a shape
  the pinned engine does not emit, so after a real routed swap the tab shows
  *"We could not check all of your swaps. Try again shortly."* permanently, and
  **Try again** keeps failing. Use **Advanced** or a block explorer to confirm a
  swap happened.
- **Activity does not show atomic swaps either** — and worse, it says *"No
  swaps yet."*, which is a false statement about your own money rather than a
  gap. GLEEC and GRC-20 trades are atomic, so this is the case you will hit.
- **An in-flight swap is lost if you leave the Swap segment.** The screen says
  *"You can leave this screen. The swap keeps running."* That is true of the
  engine but **not of the UI**: going to Wallet, Activity or Advanced destroys
  the live view and there is no route back to it. The swap continues; you just
  cannot watch it or cancel it.
- **An unfillable atomic quote hangs on a spinner.** If you sell more than the
  single best maker order covers, the fill-or-kill order never matches and the
  screen sits on a spinner. No funds move. This is not "peer-to-peer swaps are
  broken" — it is this specific bug.

## How to test so the results are useful

1. **Stay on the Swap screen from "Swap now" until the swap resolves.** Do not
   switch segments mid-swap. If you do, the swap is not lost but your view of
   it is, and you will not be able to report what happened.
2. **Record what you were shown before you confirm.** Screenshot the review
   screen — the pay amount, the "receive at least" figure, the fee breakdown,
   and which source filled it. The most valuable bug report in this round is
   *"it showed me X and I got Y."*
3. **Confirm outcomes outside the app.** Because Activity is unreliable, verify
   in Advanced or on a block explorer. Note the tx hash where you can.
4. **Try small and awkward amounts**, not just round ones — many decimal places,
   the exact balance, and the **Max** button.
5. **Note your window size if anything looks wrong.** Below 768px wide the
   layout changes materially (see below).

## Fixed today — only present in a build made after this commit

If you are testing the existing PR preview
(`walletrc--pull-3507-merge-*.web.app`), it was built **before** these and still
has them:

- A failed price check froze the button on "Checking price…" for the rest of the
  session — the swap could be neither started nor abandoned.
- Pressing **Back** during the pre-start price check did not stop the swap; it
  executed seconds later anyway.
- A start failure re-armed the button even when the engine may already have
  taken the swap, so a second press could submit a **second real swap**.
- **Max** and the reverse arrow changed the amount that would be traded while
  leaving the old figure on screen — the form showed one number and swapped
  another.
- A comma decimal keypad (most of Europe) produced an amount the app rejected as
  malformed, making fractional swaps impossible to enter.
- **Under 768px wide — a phone, or just a narrow browser window — the Swap menu
  opened the old trading page and the unified form could not be reached at
  all.**

## What has been verified

- The unified surface renders and is reachable in the deployed preview build at
  desktop width; the narrow-window failure above was reproduced against that
  same build.
- `dex_tests` and `misc_tests` pass on both CI runners, so the Advanced segment
  and the surrounding navigation are exercised end to end.
- Full unit suite: 1214 passing.
- `fiat_onramp_tests` fails, but for an unrelated reason: the Ramp host API key
  on `fiat-ramps.gleec.com` is rejected at the quote endpoint. Buy/Sell payment
  methods will not render until that key is rotated. Banxa is healthy.
