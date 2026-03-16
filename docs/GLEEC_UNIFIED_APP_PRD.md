# Gleec Unified App PRD (DEX + CEX + Pay + Card)

Date: March 2, 2026
Owner: Product
Status: Draft v2
Related documents:
- [GLEEC_UNIFIED_APP_PLAN.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/GLEEC_UNIFIED_APP_PLAN.md)
- [GLEEC_UNIFIED_APP_EXECUTIVE_BRIEF.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/GLEEC_UNIFIED_APP_EXECUTIVE_BRIEF.md)
- [GLEEC_UNIFIED_APP_UX_SPEC.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/GLEEC_UNIFIED_APP_UX_SPEC.md)
- [UNIFIED_GLEEC_APP_PRODUCT_PLAN.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/UNIFIED_GLEEC_APP_PRODUCT_PLAN.md)

## 1. Problem Statement

Gleec currently offers meaningful capabilities across wallet, fiat, DEX, bridge, exchange, Pay, and Card. However, the user experience is fragmented because those capabilities are distributed across separate app surfaces and separate mental models.

Users should not need to think in terms of:
- wallet vs fiat vs dex vs exchange vs Pay vs card
- custodial vs non-custodial implementation details
- provider-specific or issuer-specific states
- separate histories and balances for each Gleec surface

They should be able to think in terms of:
- buy
- swap
- move
- top up
- spend
- track activity

## 2. Product Goal

Create a single Gleec app experience where users can move across wallet, DEX, CEX, Pay, Card, fiat, and support flows without context-switching or losing transaction clarity.

## 3. Goals

1. Reduce navigation and flow fragmentation.
2. Increase first funded action completion.
3. Increase quote-to-execution conversion.
4. Increase verified-user activation into Pay/Card flows.
5. Reduce support tickets caused by hidden status, unclear fees, unclear custody boundaries, and split histories.
6. Create a scalable architecture for future Earn, advanced trading, and spend operations.

## 4. Non-Goals

1. Replace all backend services in the first release.
2. Achieve full feature parity rewrite before shipping a new unified shell.
3. Launch every advanced card feature in Phase 1.
4. Introduce new chains, providers, or issuers purely for roadmap optics.
5. Promise spend/banking timelines before Exchange/Pay/Card contract audits are complete.

## 5. Personas

### Persona A: Beginner investor
- Usually starts from fiat
- Prefers guided flows and clear outcomes
- Gets blocked by technical language or transaction ambiguity

### Persona B: Self-custody crypto user
- Wants transparency and control
- Cares about route quality, fees, and asset movement details
- Will tolerate complexity only if it provides value

### Persona C: Hybrid trader/investor
- Uses both exchange and on-chain flows
- Wants to move quickly between accounts and positions
- Expects one view of balances and one activity trail

### Persona D: Earner/spender/freelancer
- Receives fiat or crypto and wants to spend quickly
- Needs banking, top-up, statements, and predictable custody labeling
- Values card and IBAN flows as much as trading flows

## 6. Success Metrics

### Primary
1. New-user activation rate: first funded action within 24 hours
2. Quote acceptance rate: quotes accepted / quotes shown
3. Trade execution rate: completed trades / confirmed trade attempts
4. Spend activation rate: verified users who complete first Pay or Card action
5. 30-day retention for funded users

### Secondary
1. Median time to first successful buy
2. Median time to first successful swap
3. Median time to first successful card top-up
4. Weekly active usage of Activity tab
5. Weekly active usage of combined portfolio view
6. Funded Pay-account activation rate

### Guardrails
1. Execution failure rate
2. KYC abandonment rate
3. Failed bank/card operation rate
4. Crash-free sessions
5. Duplicate or conflicting balance states

## 7. Users and Jobs To Be Done

1. "Help me buy quickly with low friction and no surprises."
2. "Help me convert assets using the best route without making me compare systems myself."
3. "Help me understand where my money is across wallet, exchange, Pay, and card."
4. "Help me top up or move money without leaving the app."
5. "Help me recover when something is delayed, rejected, or partially complete."

## 8. Product Principles

1. Intent first
2. Custody visible everywhere
3. Fees, route, and funding-source transparency before confirmation
4. Progressive disclosure for advanced controls
5. Region-aware and issuer-aware gating
6. Recovery UX is part of the core product
7. One activity model across crypto, banking, and spend flows

## 9. Scope

## 9.1 In scope for unified app initiative

1. New app shell and navigation
2. Home dashboard
3. Unified Trade area
4. Unified Spend area
5. Unified Activity timeline
6. Unified portfolio model
7. Wallet<->CEX<->Pay<->Card transfer flow orchestration
8. Capability matrix for region/provider/issuer gating
9. Shared instrumentation and transaction identity model
10. API discovery and remediation work for Exchange, Pay, and Card

## 9.2 Out of scope for initial phases

1. Full NFT redesign
2. Full market-maker-bot redesign
3. Social/community product layers
4. Institutional account features
5. Guaranteed support for every possible card-lifecycle or issuer-admin feature in v1

## 10. Functional Requirements

### FR1. Unified navigation
The app must expose a simplified primary navigation based on user intent.

Acceptance criteria:
1. Mobile primary navigation contains `Home`, `Trade`, `Spend`, `Activity`, `Profile`.
2. Existing module features remain reachable during migration.
3. Deep links and legacy routes continue to resolve without blocking user actions.

### FR2. Unified Home
The app must provide a single entry screen for portfolio overview and key actions.

Acceptance criteria:
1. Home shows total portfolio value and 24h delta.
2. Home shows quick actions for `Buy`, `Swap`, `Transfer`, `Top Up`, and `Add Money` where eligible.
3. Home shows custody-aware balances or a clear split toggle.
4. Home shows watchlist or market movers.
5. Home surfaces incomplete setup tasks such as KYC, wallet backup, and card/pay onboarding.

### FR3. Unified Trade intent engine
The app must support a single trade entry point that can route across CEX, DEX, and providers.

Acceptance criteria:
1. User selects source asset/account, destination asset/account, and amount in one ticket.
2. System returns ranked routes with best route marked.
3. User can inspect route details before confirming.
4. If only one route is available, the system still shows why it was selected.
5. Funding source and custody impact are visible before confirm.

### FR4. Confirmation transparency
The app must show clear fee, ETA, route, and funding-source detail before execution.

Acceptance criteria:
1. Confirmation includes route/provider path.
2. Confirmation includes effective price/rate.
3. Confirmation includes fee components.
4. Confirmation includes estimated completion time.
5. Confirmation includes custody-change warning if applicable.
6. Confirmation includes funding-source label when the source is Pay, Card, or provider-mediated.

### FR5. Unified Activity timeline
The app must provide one place to track all user-visible activity.

Acceptance criteria:
1. Timeline includes on-chain transactions, fiat orders, swaps, transfers, account actions, bank transfers, card top-ups, and card transactions where available.
2. Each item has a normalized status model.
3. Each item exposes identifiers relevant to support and tracing.
4. Delayed or failed items expose next-best actions.

### FR6. Unified portfolio model
The app must support combined and segmented balance views.

Acceptance criteria:
1. Portfolio can be viewed as `Combined`, `Wallet`, `CEX`, `Pay`, or `Card`.
2. Asset or balance detail shows account breakdown.
3. Locked or pending funds are separately labeled.
4. Price and fiat values update consistently across views.

### FR7. Unified transfers
The app must support movement between wallet, custodial account, Pay, and Card surfaces.

Acceptance criteria:
1. User can choose transfer direction.
2. App determines whether movement is internal, on-chain, provider-mediated, or issuer-mediated.
3. Network/fee/timing details are shown before confirm.
4. Final state appears in Activity with traceable identifiers.

### FR8. Spend hub
The app must provide a first-class destination for banking and spend actions.

Acceptance criteria:
1. `Spend` includes Pay account and Card entry points.
2. Spend surfaces both balances and action CTAs.
3. Spend entry respects KYC and regional capability state.
4. Users can reach card top-up and bank transfer in at most two taps from Spend.

### FR9. Gleec Pay banking operations
The app must support core Pay actions needed for consumer utility.

Acceptance criteria:
1. User can view Pay balance and account status.
2. User can view/share IBAN details where eligible.
3. User can initiate bank transfer where supported.
4. User can track Pay-related activity in Activity.
5. Conversion between Pay balance and crypto is exposed when supported.

### FR10. Gleec Card operations
The app must support core card actions needed for day-to-day use.

Acceptance criteria:
1. User can view card status and balance where supported.
2. User can top up card from eligible funding sources.
3. User can freeze/unfreeze card where supported.
4. User can access card transaction history or issuer-backed transaction states.
5. Card-related activity appears in Activity.

### FR11. Capability gating
The app must support server-driven restrictions by geography, provider, issuer, asset, and account state.

Acceptance criteria:
1. Unavailable actions are visibly disabled with explanation.
2. Users are not allowed into dead-end flows.
3. Capability checks are available before CTA tap and before final confirm.
4. Changes in provider or issuer availability can be reflected without app release.

### FR12. Security and trust messaging
The app must adapt risk and security messaging to custody mode.

Acceptance criteria:
1. Self-custody screens warn users not to share seed/private keys.
2. Account, Pay, and Card screens promote 2FA/passkey and session review where applicable.
3. High-risk destinations or volatile route conditions trigger warnings.
4. Support entry points are clearly verified and in-app.
5. The app clearly distinguishes what Gleec controls vs what the user controls.

### FR13. Service audit and remediation
The program must validate that required Exchange, Pay, and Card contracts exist before downstream commitments are frozen.

Acceptance criteria:
1. Exchange, Pay, and Card service audits are completed and documented.
2. Missing critical fields or statuses are categorized by severity.
3. Blocking service gaps are either remediated or explicitly accepted into scope/roadmap changes.
4. Activity and correlation-ID requirements have named service owners.

## 11. Non-Functional Requirements

1. Cross-platform support remains mobile, desktop, and web where feasible.
2. Core flows must remain responsive on low-memory devices.
3. All new screens meet WCAG AA contrast standards.
4. Analytics events must be emitted for all major state transitions.
5. Service timeouts and partial failures must degrade gracefully.
6. Sensitive card/banking data exposure must respect issuer/security boundaries.
7. Capability and KYC state must be queryable early enough to support pre-CTA gating.

## 12. Dependencies

1. CEX service interfaces and balance/order data access
2. DEX route and execution services
3. Fiat provider APIs and region rules
4. Pay service interfaces and account/transfer data access
5. Card service interfaces and lifecycle/top-up transaction data
6. Capability matrix backend or config service
7. Unified transaction identity and support tooling
8. Design system updates for shared components
9. Compliance and issuer/legal review

## 13. Risks

1. Legacy module boundaries may leak into the UX.
2. Route-quality logic may be difficult to explain if overly complex.
3. Region-specific legal, provider, and issuer rules may create uneven experiences.
4. Partial data quality across wallet, CEX, Pay, and Card ledgers may undermine trust.
5. Card/Pay API maturity may be lower than Exchange API maturity.

## 14. Release Strategy

1. Feature-flag all new shell and orchestration work.
2. Dogfood internally with staff and support team.
3. Roll out to a limited cohort before defaulting to all users.
4. Keep legacy paths accessible during migration.
5. Do not lock phase dates until Exchange/Pay/Card service audits are complete.

### 14.1 Delivery assumptions

The roadmap referenced by this PRD is the baseline planning case for the full `wallet + exchange + Pay + card` scope. It does include discovery and likely service remediation.

Baseline assumptions:
1. Cross-functional pods execute with normal engineering automation and standard QA/release workflows.
2. Product, design, engineering, analytics, and support operations can work in parallel where dependencies allow.
3. Exchange contracts are partially reusable from current/public APIs.
4. Pay/Card service gaps may require moderate remediation.
5. Major provider, issuer, compliance, or security blockers do not extend beyond normal review windows.

AI-assisted planning case:
1. If AI agents are adopted deliberately, the overall roadmap can compress by roughly 15% to 25%.
2. The most likely acceleration areas are story decomposition, design-spec expansion, UI scaffolding, analytics wiring, QA case generation, and regression-review support.
3. The least compressible areas remain provider integration, issuer integration, compliance approval, service remediation, security signoff, and rollout governance.

### 14.2 Team model by phase

1. Phase 0 assumes a definition team led by product, design, engineering, analytics, and compliance/operations stakeholders.
2. Phase 1 assumes a dedicated integration workstream for Exchange, Pay, and Card services.
3. Phase 2 assumes a Core Experience pod delivers shell, Home, and Activity with shared design-system/platform support.
4. Phase 3 assumes Trade and Funding pods work in parallel on route orchestration and buy/sell/provider flows.
5. Phase 4 assumes a Banking and Spend pod owns Pay, Card, issuer, and statement/transaction experience.
6. Phase 5 assumes tight coordination across wallet, CEX, Pay, Card, portfolio, transfer, and activity ownership.
7. Phase 6 assumes a growth-oriented workstream for Earn, notifications, and optimization while core flows stabilize.

### 14.3 Timeline reference

1. Baseline roadmap: about 50-58 weeks end to end.
2. AI-assisted roadmap: about 38-46 weeks end to end.
3. The baseline roadmap should remain the default planning case until Gleec commits to AI-assisted delivery as an explicit operating model.

## 15. Epics

### Epic 1: Unified shell and navigation
Outcome:
- Users can access most primary jobs through a simple, intent-first shell.

Stories:
1. As a new user, I want to land on a simple Home screen so I know what to do next.
2. As a returning user, I want one place to start Buy, Swap, Top Up, Transfer, or Add Money so I do not need to hunt across apps.
3. As a migration user, I want legacy screens to remain reachable so new navigation does not strand me.

Engineering notes:
- Introduce new navigation scaffold and route adapter layer.
- Preserve legacy route compatibility.

### Epic 2: Home and unified portfolio
Outcome:
- Users can understand their total position and take the next action quickly.

Stories:
1. As a user, I want to see my total portfolio with clear custody breakdown.
2. As a user, I want to filter between Combined, Wallet, CEX, Pay, and Card views.
3. As a user, I want detail views to show where the balance lives and what I can do with it.

Engineering notes:
- New portfolio aggregation domain.
- Shared asset/balance row and detail models.

### Epic 3: Unified Trade ticket
Outcome:
- Users can buy, sell, or convert from one entry point.

Stories:
1. As a user, I want the app to recommend the best route without making me compare subsystems manually.
2. As a power user, I want to inspect route details before execution.
3. As a user, I want to see fees, ETA, and minimum receive before I confirm.
4. As a user, I want meaningful fallback guidance if the preferred route fails.

Engineering notes:
- New trade orchestration domain.
- Quote normalization and ranking.
- Confirmation model shared across routes.

### Epic 4: Unified Activity timeline
Outcome:
- Users can track all activity and recover from issues in one place.

Stories:
1. As a user, I want one timeline for orders, swaps, transfers, bank operations, and card actions.
2. As a support user, I want normalized identifiers and states so issues are easier to diagnose.
3. As a user, I want failed or delayed items to show actionable next steps.

Engineering notes:
- New activity aggregation domain.
- Normalized status/state machine.
- Identifier correlation model.

### Epic 5: Transfers and funding orchestration
Outcome:
- Users can move value between custody and payment surfaces confidently.

Stories:
1. As a user, I want to choose transfer direction and see where funds are going.
2. As a user, I want to know whether the movement is internal, on-chain, provider-mediated, or issuer-mediated.
3. As a user, I want to understand fees, arrival time, and status checkpoints.

Engineering notes:
- Transfer orchestration with destination/account validation.
- Timeline integration.

### Epic 6: Banking and Spend
Outcome:
- Users can bank and spend without leaving the app.

Stories:
1. As a verified user, I want a dedicated Spend destination for Pay and Card.
2. As a user, I want to top up my card from the best available funding source.
3. As a user, I want to view my Pay balance and send a bank transfer.
4. As a user, I want card and bank activity to appear in the same history as my crypto activity.

Engineering notes:
- Banking and spend domain.
- Pay/account models, card models, and issuer/provider adapters.

### Epic 7: Capability gating and trust
Outcome:
- Users understand what is available to them and why.

Stories:
1. As a user in a restricted region, I want unavailable actions explained so I know what alternatives remain.
2. As a user, I want risk warnings before high-risk actions.
3. As a user, I want verified support paths in context if something goes wrong.
4. As a user, I want KYC progression explained only when needed.

Engineering notes:
- Capability matrix domain.
- Server-driven copy and policy gating.

### Epic 8: Service audit and remediation
Outcome:
- The program has credible backend assumptions.

Stories:
1. As a product team, we need audited Exchange/Pay/Card contracts before locking experience commitments.
2. As an engineering team, we need explicit remediation owners for missing fields, statuses, and identifiers.
3. As a support team, we need unified correlation IDs before scaling rollout.

Engineering notes:
- Contract matrix and severity register.
- Named service owners and remediation acceptance criteria.

## 16. Prioritized User Stories Backlog

### P0
1. Exchange/Pay/Card service audit and gap register
2. New shell with `Home`, `Trade`, `Spend`, `Activity`, `Profile`
3. Home dashboard with total portfolio and quick actions
4. Unified Activity read model
5. Buy/Swap route selection and confirmation transparency
6. Capability matrix and disabled-CTA reasons

### P1
1. Card top-up flow
2. Pay overview and bank transfer flow
3. Combined/Wallet/CEX/Pay/Card portfolio filter
4. Cross-domain transfer orchestration
5. Support handoff from Activity item

### P2
1. Advanced trading mode
2. Earn integration into portfolio model
3. Deeper card controls, statements, and disputes
4. Personalized watchlist and notifications

## 17. Analytics Requirements

Events:
1. `home_viewed`
2. `quick_action_tapped`
3. `quote_shown`
4. `quote_accepted`
5. `trade_submitted`
6. `trade_completed`
7. `trade_failed`
8. `activity_item_opened`
9. `support_opened_from_activity`
10. `portfolio_filter_changed`
11. `transfer_submitted`
12. `transfer_completed`
13. `capability_gate_seen`
14. `pay_transfer_submitted`
15. `pay_transfer_completed`
16. `card_topup_submitted`
17. `card_topup_completed`
18. `kyc_prompt_seen`
19. `kyc_completed`

Properties:
- asset pair
- route type
- custody source/destination
- funding source
- provider
- issuer
- region
- amount band
- failure reason category

## 18. Rollout Gates

Gate 1:
- Exchange/Pay/Card service gaps are understood and blocking issues are accepted or remediated.

Gate 2:
- Home and Activity increase discoverability and reduce route confusion in moderated testing.

Gate 3:
- Quote acceptance improves by at least 10% in beta cohort.

Gate 4:
- Trade-related support tickets per 1,000 transactions fall by at least 15%.

Gate 5:
- Verified-user Pay/Card activation reaches agreed threshold without unacceptable support load.

Gate 6:
- Combined portfolio is used weekly by at least 30% of funded users.

## 19. Open Questions

1. Which CEX services and balances are available to the app today via stable APIs?
2. Which Pay and Card APIs exist today, and which behaviors depend on non-public or manual workflows?
3. Can wallet<->CEX<->Pay<->Card transfers be internalized for some assets, or are they always mediated/on-chain?
4. Which compliance rules differ by country vs state vs provider vs issuer?
5. Which card features are truly available for in-app control vs external issuer surfaces?
6. How much support metadata can be surfaced directly in Activity without exposing internal systems?
