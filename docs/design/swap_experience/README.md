# Swap interaction reference

Open [index.html](index.html) directly in a browser. It is self-contained and
does not call a server, connect to a wallet, or send funds.

Use the scenario selector outside the app frame for ready, loading, slow,
failed, review, changed-price, starting, receiving, completed, wallet, and
recovery states. Inside the frame, asset selection, amount editing, pair
reversal, review, confirmation, details, return to wallet, tracking, and receipt
navigation are interactive. Turn on “Play illustrative timing” for a simulated
normal journey. Turn it off to inspect each state without automatic progress.

The “Wide layout” and “Reduce motion” controls are reference tools, not product
controls. The latter also follows the operating system's reduced-motion
preference. Light and dark modes use the corresponding current swap palette.

All amounts, rates, addresses, times, and execution outcomes are fixture data.
The Ethereum symbol is embedded unchanged from the repository's
`assets/blockchain_icons/svg/32px/eth.svg`; other assets use labelled text badges
instead of invented logos. The system font approximates the app's inherited
typeface without downloading fonts.

See [the delivery contract](../../SWAP_UX_DELIVERY.md) for state coverage,
implementation boundaries, motion timings, and the QA matrix. The reference
does not establish that Flutter or real-device validation has passed.

The [browser QA record](qa/README.md) includes screenshots and a repeatable
fixture-only interaction check. Max rounds a USD entry down to cents in this
reference; final concrete funding and quote validation belongs to the app.
