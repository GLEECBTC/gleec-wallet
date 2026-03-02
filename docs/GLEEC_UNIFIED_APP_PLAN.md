# Gleec Unified App Plan (DEX + CEX + Pay + Card)

Date: March 2, 2026
Owner: Product + Design + Mobile/Web Engineering
Status: Draft v2

## 1. Objective

Define the next major iteration of Gleec as one seamless app that combines:
- Non-custodial wallet + DEX flows
- Custodial CEX account flows
- Gleec Pay banking/account flows
- Gleec Card lifecycle and spend flows
- Unified portfolio, funding, transfer, support, and compliance experience

This document includes two delivery options:
- Option A: next iteration on current codebase
- Option B: clean-slate app with migration path

It also includes a recommended path, roadmap, UX architecture, service assumptions, and execution model.

## 2. Research Base

## 2.1 External benchmark: Exodus

Verified observations from current Exodus materials:
1. Exodus positions itself as a multi-platform self-custody wallet with exchange, portfolio, fiat rails, and trust education inside one app shell.
2. Exodus explicitly frames exchange as a user intent, not a protocol choice.
3. Exodus buy/sell is powered by provider rails and varies by region and KYC state.
4. Exodus uses trust UX heavily: fee explanation, support education, security boundaries, and custody clarity.
5. Exodus demonstrates that product simplicity can sit on top of complex backend/provider routing.

Implication for Gleec:
- Users should choose goals like `Buy`, `Swap`, `Move`, or `Spend`, not subsystems like `DEX`, `CEX`, `Pay`, or `Card`.

## 2.2 Current official Gleec ecosystem findings

From current official Gleec materials and public endpoints:
1. Gleec Pay is positioned as a crypto-friendly IBAN account for requesting, sending, and receiving funds.
2. Gleec Card is positioned as a virtual and plastic card product that can be topped up directly from the Gleec wallet.
3. Gleec Exchange exposes a current public API surface and publishes system status and regulatory information.
4. Exchange API maturity appears higher and more publicly documented than Pay/Card API maturity.
5. Publicly visible product positioning confirms that Pay and Card are not side features. They are part of the consumer value proposition.

Implication for Gleec:
- The official unified-app plan should treat `Banking and Spend` as a first-class domain, not as a later add-on.
- The roadmap must include API discovery and likely remediation for Pay/Card before front-end dates can be trusted.

## 2.3 Sources used

External benchmark sources:
- Exodus mobile wallet: [https://www.exodus.com/mobile/](https://www.exodus.com/mobile/)
- Exodus support: “Getting started with Exodus”: [https://www.exodus.com/support/en/articles/8598609-getting-started-with-exodus](https://www.exodus.com/support/en/articles/8598609-getting-started-with-exodus)
- Exodus support: “How can I buy Bitcoin and crypto”: [https://www.exodus.com/support/en/articles/8598616-how-can-i-buy-bitcoin-and-crypto](https://www.exodus.com/support/en/articles/8598616-how-can-i-buy-bitcoin-and-crypto)
- Exodus support: “How do I swap crypto in Exodus?”: [https://www.exodus.com/support/en/articles/8598618-how-do-i-swap-crypto-in-exodus](https://www.exodus.com/support/en/articles/8598618-how-do-i-swap-crypto-in-exodus)
- Exodus support: “How do I buy crypto with XO Pay in Exodus?”: [https://www.exodus.com/support/en/articles/10776618-how-do-i-buy-crypto-with-xo-pay-in-exodus](https://www.exodus.com/support/en/articles/10776618-how-do-i-buy-crypto-with-xo-pay-in-exodus)
- Exodus support: “Getting started with Trezor on Exodus Desktop”: [https://www.exodus.com/support/en/articles/8598656-getting-started-with-trezor-on-exodus-desktop](https://www.exodus.com/support/en/articles/8598656-getting-started-with-trezor-on-exodus-desktop)

Official Gleec sources:
- Gleec Card: [https://www.gleec.com/card/](https://www.gleec.com/card/)
- Gleec Pay: [https://www.gleec.com/pay](https://www.gleec.com/pay)
- Gleec Exchange API v3: [https://api.exchange.gleec.com/](https://api.exchange.gleec.com/)
- Gleec system monitor: [https://exchange.gleec.com/system-monitor](https://exchange.gleec.com/system-monitor)
- Gleec licenses and regulations: [https://exchange.gleec.com/licenses-regulations](https://exchange.gleec.com/licenses-regulations)

Internal repository references used to ground the plan:
- [README.md](/Users/charl/Code/UTXO/gleec-wallet-dev/README.md)
- [fiat_page.dart](/Users/charl/Code/UTXO/gleec-wallet-dev/lib/views/fiat/fiat_page.dart)
- [main_menu_value.dart](/Users/charl/Code/UTXO/gleec-wallet-dev/lib/model/main_menu_value.dart)
- [UNIFIED_GLEEC_APP_PRODUCT_PLAN.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/UNIFIED_GLEEC_APP_PRODUCT_PLAN.md)

## 3. Current Gleec Baseline

## 3.1 Existing app baseline

The current Flutter app already contains major crypto domains:
- Wallet
- Fiat
- DEX
- Bridge
- Market Maker Bot
- NFT
- Settings/Support

Known product constraints visible in code:
- Fiat provider stack currently appears limited in active configuration.
- Fiat purchase-history flow appears intentionally deferred/TODO.
- Trading and wallet modes are partially separated by routing/menu logic.

Implication:
- The current app can still act as the shell for a unified product, but it does not currently represent the full consumer ecosystem.

## 3.2 Ecosystem baseline beyond the current app

The broader Gleec ecosystem includes:
- Self-custody wallet capabilities in the current app
- Exchange capabilities in separate product surfaces and APIs
- Gleec Pay banking/account behavior outside the current app shell
- Gleec Card behavior outside the current app shell

Implication:
- The unified-app effort is not only a UI redesign. It is also a cross-system product integration program.

## 4. Product Vision

"One Gleec app where users can hold, trade, bank, and spend across custody models without context-switching."

North Star:
- A user can complete any of these from Home in under 90 seconds:
- Buy crypto with fiat or Pay balance
- Swap between assets with best-route selection
- Move funds between wallet, CEX, Pay, and Card
- Top up a card from the best funding source
- Understand all activity in one coherent timeline

## 5. Strategic Options

## 5.1 Option A: next iteration on existing app

What it is:
- Keep the current Flutter codebase and existing crypto services
- Introduce unified IA shell and orchestration layer
- Integrate Exchange, Pay, and Card progressively behind feature flags

Pros:
- Faster learning and earlier release path
- Reuses existing wallet/DEX/bridge implementation
- Lower product-delivery risk than a full rewrite now

Cons:
- Transitional complexity is high
- Legacy UX and architecture constraints remain during migration
- Cross-system contract work is still required

## 5.2 Option B: clean-slate app

What it is:
- New app shell, new routing, new domain architecture
- Existing crypto services and new Exchange/Pay/Card services consumed through clean interfaces

Pros:
- Cleanest long-term product architecture
- Best long-term maintainability
- Strongest opportunity to design without legacy baggage

Cons:
- Longest path to parity
- Higher migration risk
- Expensive before demand and contract assumptions are validated

## 5.3 Recommendation

Use a hybrid strategy:
1. Deliver Option A over the next staged releases to validate unified flows and retention lift.
2. In parallel, build clean foundation domains where debt is highest: portfolio, activity, routing, banking/spend, and capability gating.
3. Decide on full migration only after KPI evidence and service-contract maturity are both validated.

## 6. Target Users and Jobs To Be Done

## 6.1 Segments

1. Beginner investor
- Wants easy buy/sell and confidence
- Needs guided flows, clear fees, and trust

2. Crypto-native self-custody user
- Wants routing quality, control, and chain tooling
- Needs transparent execution and advanced controls

3. Hybrid active trader
- Moves between CEX and on-chain often
- Needs one portfolio and low-friction transfers

4. Earner/spender/freelancer
- Receives value in fiat or crypto and wants to spend it quickly
- Needs Pay, card top-up, banking, statements, and predictable custody labeling

## 6.2 Core jobs

1. "Help me get exposure quickly with low friction."
2. "Help me trade at fair execution with clear costs."
3. "Help me move assets safely across wallet, exchange, and banking balances."
4. "Help me spend or transfer money without leaving the app."
5. "Help me understand what happened when something fails."

## 7. Product Principles

1. One intent, one flow: users choose `Buy`, `Swap`, `Move`, `Top Up`, or `Spend`, not subsystem names.
2. Custody clarity everywhere: wallet, exchange, Pay, card, and provider states are always visible.
3. Transparent execution: show route, fees, ETA, funding source, and fallback before confirm.
4. Progressive complexity: simple defaults, advanced controls on demand.
5. Recovery by design: every failed operation has a next-best action.
6. Region-aware UX: never dead-end users in unavailable flows.
7. Money graph over product graph: one coherent view of where value sits and how it moves.

## 8. Experience Architecture (IA)

## 8.1 Proposed top-level navigation

Mobile primary navigation:
1. Home
2. Trade
3. Spend
4. Activity
5. Profile

Desktop/sidebar expansion:
1. Home
2. Assets
3. Trade
4. Spend
5. Earn
6. NFTs
7. Settings
8. Support

Design decision:
- `Spend` becomes a first-class primary destination because Pay/Card is part of the official scope.
- `Earn` remains important, but should initially live as a secondary destination on mobile to avoid overcrowding the primary nav.

## 8.2 Core navigation model

1. One global asset picker used across all domains.
2. Intent-led entry points from Home and asset detail.
3. Contextual sub-tabs within Trade and Spend.
4. Unified activity and support access from anywhere.

## 9. Unified Trade and Funding Model

## 9.1 Trade intent engine

User inputs:
- Source asset/account
- Destination asset/account
- Amount
- Preference profile: best price, fastest, lowest slippage, non-custodial-only

Engine output:
- Ranked routes across:
- Internal CEX books/liquidity
- External DEX routes/aggregators
- Bridge + swap combinations
- Provider buy/sell rails
- Pay-funded purchase paths when available

## 9.2 Pre-trade confirmation card

Must show:
- Route/provider path
- Effective rate
- Fee breakdown by component
- Estimated completion time
- Min received / slippage bound
- Funding source and custody transition warning

## 9.3 Post-trade lifecycle

1. Pending: clear status and checkpoints
2. Partial failure: fallback actions, retry, support, or alternate route
3. Complete: receipt + what changed across balances and identifiers

## 10. Unified Banking and Spend Model

## 10.1 Spend intent model

User intents include:
- Add money
- Top up card
- Send bank transfer
- Receive via IBAN
- Spend and track card activity

System responsibilities:
- Recommend best funding source for card top-up
- Explain FX or crypto-sale impact before top-up
- Keep bank/card operations in the same activity model as crypto operations

## 10.2 Card funding hierarchy

Default recommendation order:
1. Stablecoin wallet balance
2. Available exchange balance
3. Available Pay balance
4. Volatile crypto balance with explicit price-impact warning

## 10.3 Banking operations in scope

1. View Pay balance
2. View/share IBAN details
3. Send bank transfer
4. Receive bank transfer
5. Convert Pay balance to crypto
6. Convert crypto to Pay balance
7. Fund card from Pay balance
8. View banking transaction history and statements metadata

## 10.4 Card operations in scope

1. Card overview and balance
2. Virtual/physical card status
3. Top up card
4. Freeze/unfreeze card
5. Set spending controls and limits where supported
6. Card transaction history
7. Replace/report card issue and dispute entry points where supported

## 11. Unified Portfolio Model

## 11.1 Portfolio layers

1. On-chain wallet balances
2. CEX account balances
3. Gleec Pay balances
4. Card balances
5. Earn positions
6. Pending/locked funds

## 11.2 Display logic

1. Default: combined total with clear labels by custody and account type
2. Filters:
- Combined
- Wallet
- CEX
- Pay
- Card

3. Asset detail includes:
- Total position
- Split by account type
- Available actions based on custody and capability state

## 12. Key User Flows

## 12.1 First-run onboarding

1. Choose starting path:
- Create/import self-custody wallet
- Start with account services
- Connect both

2. Explain custody models in plain language
3. Set security baseline:
- Passcode/biometric
- Recovery setup for wallet
- 2FA/passkey for account services

4. Unlock additional services progressively:
- CEX
- Pay
- Card

Success metric:
- >65% onboarding completion for new users

## 12.2 Buy crypto

1. Tap Buy
2. Input amount and target asset
3. See ranked routes by total received and ETA
4. Select payment/funding source
- card provider
- Pay balance
- exchange balance where supported

5. Complete KYC only when required
6. Track order in Activity

Success metric:
- +20% buy conversion vs current baseline

## 12.3 Convert/swap

1. Tap Swap
2. Choose assets and amount
3. See recommended route and why it was chosen
4. Confirm with full fee/ETA transparency
5. Track execution in Activity

Success metric:
- -25% support tickets related to status uncertainty

## 12.4 Internal transfers

1. Tap Transfer
2. Choose direction:
- Wallet -> CEX
- CEX -> Wallet
- Wallet -> Pay
- Pay -> Wallet
- CEX -> Pay
- Pay -> Card

3. System determines internal vs on-chain vs provider-mediated path
4. Show fees, network, ETA, and ownership context

Success metric:
- >95% transfer success without support contact

## 12.5 Card top-up

1. Tap Top Up Card
2. Enter amount
3. System recommends funding source
4. Show conversion, fees, and timing
5. Confirm and track in Activity

Success metric:
- >85% card top-up completion after intent start

## 12.6 Send bank transfer

1. Tap Send Bank Transfer
2. Select source Pay balance
3. Enter beneficiary and amount
4. Show settlement expectations and fee details
5. Confirm and track in Activity

Success metric:
- >90% successful submission for eligible users

## 13. Security, Trust, and Risk Controls

1. Distinct safeguards by custody mode
- Self-custody: key/seed education, signing prompts, recovery health checks
- CEX/Pay/Card: 2FA/passkey, device/session management, withdrawal and transfer controls

2. Transaction risk signals
- New address warnings
- High-volatility and slippage alerts
- Suspicious asset/contract warnings
- High-risk spend or transfer warnings when required by issuer/compliance rules

3. In-app anti-scam controls
- Verified support channels only
- Clear warning that support never asks for seed/private keys
- Clear separation between wallet security and custodial account security

4. Audit and observability
- Correlate order ID, tx hash, transfer reference, bank transfer ID, and card transaction reference in one activity entity

## 14. Compliance and Regionalization

1. Capability matrix service must cover:
- Country/state availability
- Provider availability
- KYC tier requirements
- Card ordering eligibility
- Pay account eligibility
- Transfer limits and restrictions

2. UX behavior
- Gray out unavailable actions with explanation and alternatives
- Never dead-end users inside unavailable flows
- Explain which capability is missing: region, KYC, issuer, provider, or account state

3. Policy model
- Action-level legal and compliance copy generated by region + service + provider/issuer

## 15. Design System Direction

1. Visual hierarchy
- Portfolio and primary actions above market noise
- Strong typography for balances, rates, and status

2. Component priorities
- Unified asset row
- Unified confirmation card
- Unified activity timeline item
- Unified capability gate component
- Unified funding-source selector

3. Motion
- Tie motion to state progression, not decoration
- Keep financial status readable at all times

4. Accessibility
- WCAG AA contrast
- Screen-reader labels for balances and statuses
- Dynamic type on mobile

## 16. Service Discovery and Remediation Plan

## 16.1 Why this is a dedicated workstream

A front-end unification plan is not credible unless the underlying services can provide:
- Stable account and balance models
- Transfer primitives and funding-source visibility
- Transaction status and event/webhook coverage
- Unified identifiers for support and activity
- Capability and compliance-state queries

Exchange public documentation suggests a meaningful API surface already exists. Pay/Card API maturity is less publicly documented and should be treated as a discovery item, not a silent assumption.

## 16.2 Required service audit outputs

1. Exchange API audit
- balances
- orders
- deposits/withdrawals
- internal transfers
- account state
- event/status coverage

2. Pay service audit
- balance model
- IBAN and beneficiary objects
- transfer initiation and status
- statements/history access
- FX/conversion operations
- KYC/account restrictions

3. Card service audit
- card lifecycle states
- top-up operations
- card balance and ledger
- freeze/unfreeze controls
- limits/controls
- disputes and support hooks
- tokenization/sensitive-data handling boundaries

4. Cross-system audit
- identity linkage
- activity normalization
- correlation IDs
- entitlement/capability model
- regional gating source of truth

## 16.3 Remediation categories

1. Thin adapter only
- Existing APIs are sufficient; app layer needs normalization only

2. Contract extension
- Missing fields, statuses, filters, or references need service changes

3. Event model remediation
- Polling or webhook/state coverage is insufficient for good Activity UX

4. Ledger and identity remediation
- Transaction IDs do not correlate cleanly across systems

5. Compliance/capability remediation
- Region/KYC state is not queryable early enough for UX gating

## 17. Technical Execution Plan

## 17.1 New product domains (BLoC aligned)

1. `portfolio_domain`
- combines wallet + CEX + Pay + Card + Earn balances

2. `trade_orchestration_domain`
- intent parsing, quote ranking, pre-trade model, execution state machine

3. `banking_spend_domain`
- Pay account state, card state, bank transfers, top-up orchestration

4. `activity_domain`
- unified activity entity model and status tracking

5. `capability_domain`
- region/provider/issuer availability matrix and policy gating

6. `identity_session_domain`
- progressive KYC state, custody-boundary messaging, session and security context

## 17.2 Integration constraints and opportunities

1. Keep existing wallet/DEX/bridge modules functional while introducing an orchestration layer.
2. Reuse current fiat components where possible, but move provider ranking and order tracking into unified flows.
3. Prefer shared transaction identity format across CEX orders, fiat orders, bank transfers, card top-ups, and on-chain tx.
4. Treat issuer/provider webviews or hosted flows as interim steps, not final UX states.

## 17.3 Instrumentation

Funnel events:
- onboarding_started/completed
- buy_initiated/completed/failed
- swap_initiated/completed/failed
- transfer_initiated/completed/failed
- pay_transfer_initiated/completed/failed
- card_topup_initiated/completed/failed

Quality events:
- quote_shown vs quote_accepted
- execution_latency_ms
- support_entry_from_activity
- capability_gate_seen

Trust events:
- security_setup_completed
- risk_warning_seen/overridden
- KYC_started/completed/abandoned

## 18. Delivery Roadmap

### 18.1 Roadmap assumptions

This roadmap is the baseline planning case for the broader `wallet + exchange + Pay + card` scope. It includes service discovery and likely remediation.

Baseline assumptions:
1. Delivery is led by normal cross-functional product, design, engineering, QA, analytics, and release workflows.
2. Multiple pods can work in parallel with shared platform and design-system support.
3. Exchange service contracts are partially reusable from public/current APIs.
4. Pay/Card services will require formal audit and likely at least moderate contract remediation.
5. Compliance, provider, issuer, and security reviews occur within normal operating windows.

### 18.2 Baseline timeline

1. Phase 0: 6 weeks
2. Phase 1: 8-12 weeks
3. Phase 2: 8 weeks
4. Phase 3: 10 weeks
5. Phase 4: 10 weeks
6. Phase 5: 8 weeks
7. Phase 6: 8 weeks
8. Total: about 50-58 weeks end to end with overlap and pod parallelization

### 18.3 AI-assisted timeline

If Gleec deliberately adopts AI agents across product, design, engineering, QA, and analytics workflows, the roadmap can compress materially.

AI-assisted assumptions:
1. Agents are used for requirements expansion, story decomposition, UX copy generation, UI scaffolding, analytics support, QA case generation, regression review, and documentation.
2. Human owners still approve architecture, code quality, compliance-sensitive behavior, and release readiness.
3. Provider integrations, issuer operations, legal/compliance approval, and security signoff remain the least compressible workstreams.

Accelerated range:
1. Total: about 38-46 weeks end to end

### 18.4 Where AI helps most

1. PRD-to-epic-to-ticket decomposition
2. Screen-spec expansion and design documentation
3. UI scaffolding and repetitive component implementation
4. Analytics event wiring and coverage audits
5. Test-case generation and regression checklist preparation
6. Documentation and internal enablement materials

### 18.5 Where AI helps least

1. Exchange/Pay/Card contract negotiation and remediation
2. Regulatory and compliance interpretation
3. Security signoff for custody-sensitive and spend-sensitive flows
4. Production rollout decisions and incident response
5. Final trust validation for money-moving experiences

### 18.6 Team model and per-phase assumptions

1. Phase 0 assumes a definition team: product lead, design lead, engineering lead, analytics lead, and compliance/operations representatives.
2. Phase 1 assumes a dedicated integration workstream for Exchange, Pay, and Card contracts.
3. Phase 2 assumes a Core Experience pod focused on shell, Home, and Activity.
4. Phase 3 assumes Trade and Funding pods work in parallel.
5. Phase 4 assumes a Banking and Spend pod owns card, Pay, issuer workflows, and transaction models.
6. Phase 5 assumes deep coordination across wallet, CEX, Pay, Card, and activity ownership.
7. Phase 6 assumes a growth-oriented workstream for Earn, notifications, and personalization.

## 19. Phase Detail

## Phase 0 (6 weeks): discovery and ecosystem audit

1. Validate user pain points across wallet, exchange, Pay, and Card
2. Finalize unified IA and component model
3. Produce service audit plan and critical unknowns list
4. Define initial capability matrix schema

Exit criteria:
- Approved PRD, UX flows, service-audit scope, and integration assumptions

## Phase 1 (8-12 weeks): API remediation and foundation

1. Audit Exchange, Pay, and Card contracts
2. Close blocking contract gaps
3. Define unified activity and correlation-ID model
4. Define capability and KYC state contracts

Exit criteria:
- Critical service gaps understood and remediation path approved

## Phase 2 (8 weeks): unified shell, Home, Activity v1

1. New nav shell and Home dashboard
2. Unified read-only Activity timeline
3. Global capability gating and service-status surfaces

Exit criteria:
- 80% of core tasks discoverable from new shell

## Phase 3 (10 weeks): trade and funding unification v1

1. Unified Swap/Convert/Buy flow with DEX+CEX+provider routing
2. Funding-source selection and clearer checkout states
3. Confirmation card with full fee/ETA/funding transparency

Exit criteria:
- +10% trade conversion and -15% trade-related support tickets

## Phase 4 (10 weeks): banking and spend v1

1. Spend hub with Pay and Card entry points
2. Card overview and top-up flow
3. Pay account overview and bank transfer flow
4. Banking/card operations added to Activity timeline

Exit criteria:
- Verified users can complete key Pay/Card tasks in-app with acceptable support load

## Phase 5 (8 weeks): portfolio, transfers, and Earn unification

1. Combined portfolio model with wallet/CEX/Pay/Card filters
2. Internal transfer orchestration across domains
3. Earn integrated into combined balance and action model

Exit criteria:
- >30% of active funded users use combined portfolio view weekly

## Phase 6 (8 weeks): advanced and growth

1. Advanced trading mode maturation
2. Deeper card controls, statements, and dispute entry points where supported
3. Notifications, personalization, and optimization

Exit criteria:
- +15% 30-day retention for funded users

## 20. KPI Framework

Primary:
1. New-user activation rate
2. Trade conversion rate
3. Spend activation rate for verified users
4. 30-day retention for funded users

Secondary:
1. Support tickets per 1,000 orders/transfers/top-ups
2. Average resolution time for failed operations
3. Portfolio engagement across combined and filtered views
4. Card top-up completion rate
5. Pay funded-account activation rate

Guardrails:
1. Failed execution rate
2. KYC drop-off rate
3. Failed bank/card operation rate
4. Crash-free sessions

## 21. Operating Model

Required cross-functional pods:
1. Core Experience pod
- shell, Home, Activity

2. Trade and Liquidity pod
- routing, quote, execution, exchange integration

3. Banking and Spend pod
- Pay, Card, issuer interactions, statements, spend controls

4. Funding and Transfers pod
- money movement between wallet, exchange, Pay, and Card

5. Trust, Compliance, and Support pod
- capability gating, KYC, policy, support workflows, escalation design

Cadence:
1. Weekly product/engineering/design triage
2. Biweekly KPI and funnel review
3. Biweekly integration-risk review for Exchange/Pay/Card
4. Monthly regional rollout decision review

## 22. Risks and Mitigations

1. Risk: DEX/CEX/Pay/Card route complexity confuses users
- Mitigation: recommended path by default with advanced details on demand

2. Risk: Regional restrictions create uneven capability sets
- Mitigation: capability matrix and clear alternatives from day one

3. Risk: Pay/Card contract maturity is weaker than Exchange contract maturity
- Mitigation: dedicated audit/remediation phase before experience commitments

4. Risk: Legacy architecture slows shipping
- Mitigation: domain-layer strangler approach with explicit module ownership

5. Risk: Support burden spikes during migration
- Mitigation: unified timeline IDs, in-flow issue recovery, provider/issuer-specific escalation paths

## 23. Decision Gates

Gate 1 (after Phase 1):
- If critical Exchange/Pay/Card service gaps are not understood and accepted, re-baseline the entire program.

Gate 2 (after Phase 2):
- If activation and discoverability metrics improve, continue phased unification.

Gate 3 (after Phase 3):
- If trade conversion improves >=10% and support load drops >=15%, scale rollout.

Gate 4 (after Phase 4):
- If Pay/Card activation and support load hit targets, proceed to full portfolio and transfer unification.

Gate 5 (after Phase 5):
- If cross-domain adoption hits targets, continue iterative path; otherwise trigger broader rebuild decision.

## 24. Immediate Next 30 Days

1. Run 12-15 user interviews split across beginner, self-custody, trader, and spender personas.
2. Audit current analytics against required funnel events and close gaps.
3. Produce high-fidelity prototypes for:
- Home
- Unified Trade ticket
- Spend hub
- Activity timeline with issue recovery

4. Audit Exchange, Pay, and Card service contracts and document gaps.
5. Define unified correlation-ID and activity-event model.
6. Define region/capability matrix schema and rollout ownership.

## 25. Final Recommendation

Proceed with the hybrid strategy now:
1. Start with iterative unification on the current app to win speed and validate demand.
2. Build clean foundation domains in parallel where debt is highest.
3. Treat Pay and Card as first-class scope, not as future embellishments.
4. Re-baseline timelines around explicit service discovery and remediation instead of assuming CEX/Pay/Card APIs are already sufficient.
5. Use strict KPI and service-readiness gates to decide whether to continue iteration or move to a broader rebuild.

This creates a credible path to a truly unified Gleec product across wallet, DEX, CEX, Pay, and Card behavior.
