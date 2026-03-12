# Gleec Unified App UX Spec (DEX + CEX + Pay + Card)

Date: March 2, 2026
Owner: Product Design
Status: Draft v2
Related documents:
- [GLEEC_UNIFIED_APP_PLAN.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/GLEEC_UNIFIED_APP_PLAN.md)
- [GLEEC_UNIFIED_APP_PRD.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/GLEEC_UNIFIED_APP_PRD.md)
- [UNIFIED_GLEEC_APP_PRODUCT_PLAN.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/UNIFIED_GLEEC_APP_PRODUCT_PLAN.md)

## 1. UX Goals

1. Reduce product-module thinking.
2. Make custody and account status visible without overwhelming users.
3. Make every high-value action start from one obvious place.
4. Reduce uncertainty during pending, failed, and delayed states.
5. Support both beginner and advanced users through progressive disclosure.
6. Make banking and spend behavior feel native to the app, not bolted on.

## 2. Global UX Rules

1. Every asset or balance picker shows account context.
2. Every money-moving confirmation shows fees, ETA, route/provider/issuer, and funding source.
3. Every pending item must have a status explanation.
4. Every failed item must have at least one recovery action.
5. Every screen with custody implications must label `Wallet`, `CEX`, `Pay`, `Card`, or `External provider`.
6. Every capability-gated action must show why it is unavailable.
7. KYC prompts should appear only when an action actually requires them.

## 3. Navigation Shell

### Screen: App Shell

Purpose:
- Provide a unified, stable navigation model across wallet, trading, banking, and spending.

Primary elements:
- Bottom nav on mobile: `Home`, `Trade`, `Spend`, `Activity`, `Profile`
- Persistent top title and account state
- Global notification center entry
- Global asset/balance search or command entry on desktop/web

Behavior:
1. Active tab persists across app restarts if the user is logged in.
2. Deep links open the relevant screen inside the new shell.
3. Legacy routes can still be presented within the shell during migration.
4. If the user is not eligible for Spend, the tab still exists but clearly explains capability requirements.

Acceptance criteria:
1. User can switch between all primary tabs in one tap.
2. Legacy screens do not break shell navigation state.
3. Shell supports signed-out, wallet-only, CEX-only, Pay/Card-eligible, and hybrid users.

## 4. Home

### Screen: Home Dashboard

Purpose:
- Give users a fast answer to "what do I have" and "what can I do next".

Sections:
1. Portfolio header
- total balance
- 24h change
- privacy toggle for hiding balances

2. Balance split control
- `Combined`
- `Wallet`
- `CEX`
- `Pay`
- `Card`

3. Quick actions
- `Buy`
- `Swap`
- `Transfer`
- `Top Up`
- `Add Money`

4. Asset and balance preview
- top holdings
- top balances by account type
- gains/losses or balance deltas

5. Market module
- watchlist or movers

6. Incomplete setup card
- KYC incomplete
- wallet backup incomplete
- security setup incomplete
- Spend unavailable until verification complete

7. Needs-attention card
- delayed transfer
- failed top-up
- pending bank transfer
- quote expired

Behavior:
1. If the user has no funds, Home prioritizes onboarding and first action.
2. If the user has unresolved money movement, a summary card appears above the fold.
3. The split filter changes all visible balance blocks consistently.
4. Spend-related actions appear even for ineligible users, but open clear gating instead of dead ends.

Acceptance criteria:
1. Home loads with a meaningful empty state for unfunded users.
2. Quick actions remain visible above the fold on common mobile sizes.
3. If balances are hidden, all balance and value blocks are consistently masked.
4. User can reach Buy, Swap, Transfer, Top Up, or Add Money within one tap.

## 5. Trade

### Screen: Trade Hub

Purpose:
- Centralize all trading and conversion intents in one place.

Structure:
- top segmented control or tabs:
- `Simple`
- `Advanced`
- `History`

Default tab:
- `Simple`

Acceptance criteria:
1. Simple trade is the default for all new users.
2. Advanced trading is accessible without leaving the Trade area.
3. Trade history can be filtered without leaving the tab.

### Screen: Simple Trade Ticket

Purpose:
- Handle Buy, Sell, and Convert in one unified ticket.

Fields:
1. Intent selector
- `Buy`
- `Sell`
- `Convert`

2. From field
- asset or funding source
- account context
- available balance

3. To field
- asset
- account context
- expected receive

4. Amount entry
- source or destination mode

5. Route summary card
- recommended route label
- effective rate
- total fees
- ETA
- funding source

6. Expandable route details
- route path
- provider(s)
- custody changes
- min receive/slippage
- settlement expectations

7. CTA
- `Review`
- disabled with reason when blocked

Behavior:
1. The ticket re-quotes on amount and asset changes.
2. If multiple routes are valid, the recommended route is selected by default.
3. If the route requires KYC or account setup, the blocker is shown before confirm.
4. If the user selects non-custodial-only mode, custodial routes are filtered out.
5. If Pay balance can fund the action, it appears as a source option when supported.

Acceptance criteria:
1. Quote refresh is visibly in progress and does not create stale confirm states.
2. Disabled CTA always has a human-readable reason.
3. User can inspect route details without losing the quote state.
4. Ticket supports wallet-only, CEX-only, Pay-funded, and hybrid account states.

### Screen: Trade Confirmation

Purpose:
- Confirm value movement with no ambiguity.

Content:
1. From and to assets with account labels
2. Rate and expected receive
3. Fee breakdown
4. Route/provider path
5. ETA
6. Funding-source label
7. Risk or slippage warnings
8. Final CTA: `Confirm`

Behavior:
1. If the quote expires, the screen forces a refresh before confirmation.
2. If capability checks fail after review, the screen explains the change and returns to the ticket.
3. High-volatility or high-slippage conditions surface warnings inline.

Acceptance criteria:
1. User cannot confirm an expired quote.
2. Confirmation shows all fee components available to the system.
3. Custody changes are explicitly labeled.
4. Funding source is always explicit.
5. Warnings do not obscure or replace the primary financial details.

### Screen: Trade Status

Purpose:
- Track submitted trade progress and show next steps.

States:
1. Submitted
2. Awaiting provider action
3. Awaiting exchange action
4. On-chain confirmation
5. Completed
6. Delayed
7. Failed
8. Partial completion

Actions by state:
- view details
- copy identifiers
- retry when allowed
- change funding source when allowed
- contact support/provider

Acceptance criteria:
1. Every status has explanatory copy.
2. Every failed or delayed state has at least one next action.
3. Order ID, tx hash, provider reference, or transfer reference are copyable when available.

### Screen: Advanced Trade

Purpose:
- Expose expert features without polluting simple trade.

Content:
1. Orderbook/chart area
2. Advanced order forms
3. Open orders and history
4. Market details and depth
5. Funding actions from wallet/Pay where supported

Acceptance criteria:
1. Advanced mode is separated visually from Simple mode.
2. User can return to Simple without losing app-level navigation state.
3. Advanced actions still route into unified Activity where possible.

## 6. Spend

### Screen: Spend Hub

Purpose:
- Make banking and spending first-class product actions.

Sections:
1. Spend balances
- Pay balance
- Card balance
- available top-up sources summary

2. Primary actions
- `Top Up Card`
- `Send Bank Transfer`
- `Add Money`
- `View Card`
- `View IBAN`

3. Eligibility state
- KYC required
- region restricted
- card not ordered
- Pay not yet activated

4. Recent spend activity
- card transactions
- bank transfers
- top-ups

Behavior:
1. If the user is not yet eligible, Spend shows a clear unlock path instead of an empty state.
2. If card exists but Pay does not, Spend still remains useful and vice versa.
3. The most urgent spend-related issue appears at the top.

Acceptance criteria:
1. Spend makes both Pay and Card discoverable in one screen.
2. Eligibility blockers are explicit and actionable.
3. Primary spend tasks are reachable within two taps.

### Screen: Card Overview

Purpose:
- Centralize card state, spend balance, and controls.

Content:
1. Card status
- not ordered
- pending approval
- active
- frozen
- blocked

2. Card balance
3. CTAs
- `Top Up`
- `Freeze/Unfreeze`
- `Details`
- `Replace`

4. Spending controls
- monthly or daily limit where supported
- channel controls where supported

5. Recent card transactions

Behavior:
1. Virtual and physical card states are distinct when both exist.
2. Sensitive details are protected behind auth and only shown when allowed.
3. Unsupported issuer controls are hidden and replaced with explanatory copy.

Acceptance criteria:
1. Card status is always visible.
2. Balance and recent activity are accessible without leaving the screen.
3. Freeze/unfreeze actions require confirmation and reflect updated state.

### Screen: Card Top-Up

Purpose:
- Let users fund the card from the best source.

Fields:
1. Amount
2. Funding source selector
- Wallet
- CEX
- Pay
- eligible provider path if needed

3. Asset/currency selector when applicable
4. Conversion summary
- rate
- fees
- ETA
- source recommendation rationale

Behavior:
1. The app recommends the best funding source by default.
2. Stable and direct funding options rank above volatile sell paths.
3. If top-up requires conversion, price-impact or FX detail is shown before confirm.
4. If KYC or issuer checks block top-up, the screen explains this before submission.

Acceptance criteria:
1. Funding source is never ambiguous.
2. User sees rate, fees, and timing before confirm.
3. Top-up creates a timeline item immediately after submission.

### Screen: Pay Overview

Purpose:
- Give users a banking home for Gleec Pay.

Content:
1. Pay balance
2. IBAN details
3. CTAs
- `Send Transfer`
- `Receive`
- `Convert to Crypto`
- `Top Up Card`

4. Recent banking activity
5. Account restrictions or limit notices

Behavior:
1. IBAN details can be copied/shared when allowed.
2. If the user is not yet eligible, a clear verification setup path appears.
3. Pay-to-crypto and Pay-to-card actions are cross-linked.

Acceptance criteria:
1. User can understand the Pay account state at a glance.
2. IBAN and transfer actions are accessible without hidden navigation.
3. Capability restrictions are explicit.

### Screen: Send Bank Transfer

Purpose:
- Let users move funds from Pay to an external bank beneficiary.

Fields:
1. From balance
2. Beneficiary selector or entry
3. Amount
4. Reference/memo
5. Summary
- fees
- ETA
- limits
- compliance note when relevant

Behavior:
1. Validation happens inline.
2. The user sees expected settlement timing before confirm.
3. If compliance review is triggered, the screen explains the state.

Acceptance criteria:
1. Invalid beneficiary or amount errors are specific.
2. Submission creates a timeline item with normalized status.
3. Pending-review states are represented clearly.

### Screen: Receive / Add Money

Purpose:
- Help users receive funds via Pay or supported provider rails.

Options:
1. Share IBAN
2. Copy account details
3. Add payment method for supported provider flow
4. Direct users to `Buy` when banking is not available

Acceptance criteria:
1. The screen explains what type of incoming money it supports.
2. Unsupported paths are replaced with alternatives, not silent omission.

## 7. Transfers

### Screen: Transfer Selector

Purpose:
- Let users move value between wallet, CEX, Pay, and Card surfaces.

Controls:
1. Direction selector
- `Wallet -> CEX`
- `CEX -> Wallet`
- `Wallet -> Pay`
- `Pay -> Wallet`
- `CEX -> Pay`
- `Pay -> Card`

2. Asset or balance selector
3. Network selector when required
4. Amount input
5. Summary panel
- destination ownership
- fees
- ETA
- movement type: internal, on-chain, provider, issuer

Behavior:
1. If an internal movement is possible, it is recommended by default.
2. If on-chain transfer is required, network fees are shown clearly.
3. Destination ownership and custody context are always visible.

Acceptance criteria:
1. User always sees transfer direction and destination context.
2. App never presents an ambiguous destination.
3. Timeline entry is created immediately after submission.

## 8. Activity

### Screen: Activity Timeline

Purpose:
- Give users one place to understand everything that happened.

Filters:
1. All
2. Trades
3. Transfers
4. Fiat
5. Banking
6. Card
7. Failed / needs action

List item content:
1. action type
2. amount and asset/currency
3. status badge
4. timestamp
5. account/custody labels
6. issue indicator when applicable

Behavior:
1. Failed or delayed items rise toward the top when unresolved.
2. Pull-to-refresh or manual refresh is available on mobile.
3. Tapping an item opens a full detail view.

Acceptance criteria:
1. Timeline can represent all major movement types in one normalized design.
2. Filters update results without leaving the screen.
3. Empty states explain what will appear here and offer next steps.

### Screen: Activity Detail

Purpose:
- Provide detailed tracking and support-ready references.

Content:
1. normalized status
2. step timeline
3. amount and balance impact
4. route/provider/issuer
5. identifiers
6. recovery actions
7. support entry point

Acceptance criteria:
1. Status stepper matches the actual lifecycle for that activity type.
2. Support entry point includes enough metadata to reduce manual lookup.
3. User can copy all relevant identifiers.

## 9. Portfolio and Detail Views

### Screen: Portfolio View

Purpose:
- Help users understand total value and distribution.

Content:
1. total portfolio block
2. split filter
3. asset and balance list
4. pending/locked balances section

Behavior:
1. Combined view merges holdings by asset or account-currency as appropriate while preserving account breakdown.
2. Wallet, CEX, Pay, and Card filters show only relevant balances.
3. Sorting supports balance, 24h performance, and alphabetical.

Acceptance criteria:
1. No balance appears duplicated without context.
2. Locked and pending funds are visually distinct from spendable balance.
3. Sorting is consistent across filters.

### Screen: Asset / Balance Detail

Purpose:
- Give one detailed page per asset or account balance regardless of where value sits.

Content:
1. total balance
2. split by wallet/CEX/Pay/Card/earn/locked when relevant
3. price chart or performance block for assets
4. quick actions
5. recent activity for that asset or balance

Behavior:
1. Actions are context-aware to available balances and account type.
2. If the item is only available in one context, hidden actions are explained.
3. Recent activity filters the global activity model.

Acceptance criteria:
1. User can understand where all balance for that item is held.
2. User can start Buy, Sell, Swap, Send, Transfer, Top Up, or Spend from this screen when available.
3. Unavailable actions are explained, not silently absent.

## 10. Profile

### Screen: Profile Overview

Purpose:
- Centralize security, account, support, and legal settings.

Sections:
1. account summary
2. verification status
3. payment methods and funding setup
4. security settings
5. wallet recovery health
6. support
7. legal and regional information

Acceptance criteria:
1. User can see KYC status without starting a transaction.
2. User can access support from Profile and from Activity.
3. Security actions are grouped by custody type where relevant.

### Screen: Security Center

Purpose:
- Make trust operations visible and actionable.

Content:
1. biometric/passcode status
2. 2FA/passkey status for account services
3. seed/recovery backup health for wallet layer
4. device/session management where applicable
5. anti-scam guidance
6. card/pay security notes where relevant

Acceptance criteria:
1. Wallet and account security are clearly separated.
2. The screen explains why some controls differ between custody models.
3. Critical security actions are never buried more than one level deep.

## 11. Onboarding

### Screen: Welcome and Path Selection

Purpose:
- Let users choose a starting path without forcing full product understanding.

Options:
1. `Start with Wallet`
2. `Start with Account`
3. `Connect Both`

Acceptance criteria:
1. All three paths are available on first run.
2. Each path includes plain-language explanation.
3. User can change or add the other path later.

### Screen: Custody Explanation

Purpose:
- Set trust expectations early.

Content:
1. what Gleec can access in wallet mode
2. what Gleec controls in CEX mode
3. what Gleec controls in Pay/Card mode
4. what recovery and security responsibilities differ

Acceptance criteria:
1. Copy is simple enough for beginner comprehension.
2. The screen avoids jargon unless explained inline.
3. The user can proceed without being forced into advanced details.

### Screen: Setup Checklist

Purpose:
- Guide user to funded and secure state.

Checklist items:
1. create/import wallet
2. finish account setup
3. verify identity when required
4. activate Pay/Card when desired
5. add payment method or funding source
6. back up recovery phrase
7. enable biometric/passcode or 2FA/passkey

Acceptance criteria:
1. Checklist reflects user’s chosen path.
2. Completed items remain visibly complete.
3. The user can skip non-blocking steps and return later.

## 12. Empty, Error, and Edge States

### Empty states
1. No portfolio yet
- encourage Buy, Deposit, or Create wallet

2. No activity yet
- explain what will appear here

3. No Spend access yet
- explain verification or regional requirements

4. No card yet
- explain ordering or activation path

Acceptance criteria:
1. Empty states are action-oriented, not decorative.
2. Empty states match user account/custody context.

### Error states
1. quote unavailable
2. provider unavailable
3. issuer unavailable
4. KYC required
5. network congestion
6. execution delayed
7. transfer under review
8. partial failure

Acceptance criteria:
1. Each error state provides a cause category when known.
2. Each error state offers retry, fallback, or support.
3. User data entry is preserved where safe.

## 13. Content and Copy Principles

1. Prefer direct verbs: Buy, Swap, Transfer, Top Up, Send, Track.
2. Avoid exposing internal architecture names unless needed.
3. Use `Wallet`, `CEX`, `Pay`, `Card`, and `Provider` consistently.
4. Use short, operational microcopy in status screens.
5. Explain restrictions rather than hiding them silently.

## 14. Accessibility Requirements

1. All primary actions meet touch target guidelines.
2. Numeric values are screen-reader friendly.
3. Status badges are not color-only.
4. Dynamic type does not break confirmation or timeline layouts.
5. Reduced-motion mode avoids animated status distractions.
6. Sensitive-data reveal patterns remain accessible while preserving security.

## 15. Design Deliverables Needed

1. Mobile shell and tab structure
2. Home dashboard
3. Simple trade ticket
4. Trade confirmation
5. Trade status screens
6. Spend hub
7. Card overview and top-up flow
8. Pay overview and bank transfer flow
9. Activity timeline and detail
10. Portfolio and detail views
11. Profile and security center
12. Onboarding path selection and checklist
