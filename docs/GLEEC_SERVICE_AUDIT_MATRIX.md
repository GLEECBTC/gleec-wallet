# Gleec Service Audit Matrix (Exchange, Pay, Card)

Date: March 2, 2026
Owner: Product + Engineering
Status: Draft v1
Related documents:
- [GLEEC_UNIFIED_APP_PLAN.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/GLEEC_UNIFIED_APP_PLAN.md)
- [GLEEC_UNIFIED_APP_PRD.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/GLEEC_UNIFIED_APP_PRD.md)
- [GLEEC_UNIFIED_APP_UX_SPEC.md](/Users/charl/Code/UTXO/gleec-wallet-dev/docs/GLEEC_UNIFIED_APP_UX_SPEC.md)

## 1. Purpose

This matrix is the starting audit artifact for the unified app program. It is meant to answer one question before front-end commitments are locked:

Can Exchange, Pay, and Card systems support the user experience we are designing?

This matrix uses current public evidence plus product requirements. Where internal documentation or service contracts are not available in this workspace, status is intentionally conservative.

## 2. Status Legend

- `Verified (public)`: current public documentation strongly evidences capability.
- `Partially evidenced`: public evidence exists, but key fields or lifecycle details are not confirmed.
- `Needs internal verification`: public evidence is insufficient; internal contract review required.
- `Blocked`: missing contract visibility prevents credible front-end planning.
- `Remediation required`: capability exists in principle, but the current contract is unlikely to support the target UX without changes.

## 3. Owner Model

Because named internal owners are not present in this workspace, owners below are role-based and should be converted to actual names during Phase 0.

Suggested role owners:
1. `Exchange backend lead`
2. `Exchange platform/SRE lead`
3. `Pay backend lead`
4. `Card integration lead`
5. `Issuer operations lead`
6. `Identity/KYC lead`
7. `Trust/compliance lead`
8. `Core app integration lead`
9. `Support tooling lead`

## 4. Evidence Base

Primary sources used:
- Exchange API docs: [https://api.exchange.gleec.com/](https://api.exchange.gleec.com/)
- Exchange system monitor: [https://exchange.gleec.com/system-monitor](https://exchange.gleec.com/system-monitor)
- Gleec verification guide: [https://exchange.gleec.com/Verifyingaccount](https://exchange.gleec.com/Verifyingaccount)
- Gleec licenses and regulations: [https://exchange.gleec.com/licenses-regulations](https://exchange.gleec.com/licenses-regulations)
- Gleec Pay: [https://www.gleec.com/pay](https://www.gleec.com/pay)
- Gleec Card: [https://www.gleec.com/card/](https://www.gleec.com/card/)

## 5. Cross-System Blockers First

| Area | Why it matters | Suggested owner | Current status | Blocker | Remediation status |
| --- | --- | --- | --- | --- | --- |
| Unified identity mapping | App cannot unify wallet, exchange, Pay, and card without a clear cross-system user identity model | Identity/KYC lead | Needs internal verification | No internal identity-link contract in workspace | Not started |
| Capability matrix | UX requires early gating by region, KYC tier, provider, and issuer | Trust/compliance lead | Needs internal verification | No server-driven capability schema in workspace | Not started |
| Correlation IDs | Activity and support need one traceable model across all systems | Core app integration lead | Needs internal verification | No unified cross-system correlation model documented | Not started |
| Event/webhook coverage | Good Activity UX depends on timely status changes | Core app integration lead | Partially evidenced | Exchange streaming is public; Pay/Card event coverage not evidenced | In discovery |
| Shared limits model | Trade, transfer, Pay, and Card actions need pre-submit limits and restriction visibility | Trust/compliance lead | Needs internal verification | No combined limits contract evidenced | Not started |
| Support metadata handoff | Support workflows depend on resolvable identifiers and consistent lifecycle states | Support tooling lead | Needs internal verification | No documented support handoff payload model | Not started |

## 6. Exchange Audit Matrix

### Summary

Exchange has the strongest public evidence. Trading, wallet balance, transfer, transaction history, and wallet streaming appear to be publicly documented. The main remaining questions are about identity, KYC, internal transfer relationships to Pay/Card, and whether the public API surface is the same one intended for the consumer app.

| Capability | Public evidence | Evidence level | Suggested owner | Current status | Main blocker | UX dependency | Remediation status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Spot trading orders | Public API docs show spot order endpoints and trading websockets | Strong | Exchange backend lead | Verified (public) | Need internal auth/session strategy | Trade hub, advanced trade | None known |
| Wallet balances | Public API docs show `/wallet/balance` | Strong | Exchange backend lead | Verified (public) | Need app auth strategy | Portfolio, trade funding | None known |
| Wallet transaction history | Public API docs show wallet transactions with statuses and subtypes | Strong | Exchange backend lead | Verified (public) | Need normalization strategy | Activity timeline | None known |
| Wallet to spot/derivatives transfer | Public API docs show `/wallet/transfer` | Strong | Exchange backend lead | Verified (public) | Need internal business rules for consumer app | Transfer flow | None known |
| Internal user-to-user wallet transfer | Public API docs show `/wallet/internal/withdraw` | Medium | Exchange backend lead | Partially evidenced | Unclear if consumer app should expose | Transfers, recovery | Needs product decision |
| Address ownership check | Public API docs show `address/check-mine` | Strong | Exchange backend lead | Verified (public) | Need app integration decision | Transfer confirmation safety | None known |
| Real-time wallet events | Public websocket docs show transaction and balance subscription | Strong | Exchange platform/SRE lead | Verified (public) | Need app-safe adapter layer | Activity freshness | None known |
| Currency/network capability flags | Public docs show `payin_enabled`, `payout_enabled`, `transfer_enabled` | Strong | Exchange backend lead | Verified (public) | Need mapping to UX capability system | Gating, funding source selection | Needs adapter only |
| Exchange system operational status | Public system monitor shows transfer/deposit/withdrawal health | Medium | Exchange platform/SRE lead | Partially evidenced | Need machine-consumable interface or internal equivalent | Pre-submit reliability messaging | Likely remediation |
| KYC/account-state API | Public verification help exists, but no public KYC state contract found | Weak | Identity/KYC lead | Needs internal verification | No documented API | Capability gates, onboarding | Discovery required |
| 2FA/security-state API | Sign-in surface shows 2FA/YubiKey flows, but no documented app-facing state contract | Weak | Identity/KYC lead | Needs internal verification | No app-facing security-state contract found | Profile, trust messaging | Discovery required |
| Exchange to Pay transfer | No public evidence found | None | Exchange backend lead + Pay backend lead | Blocked | Unknown cross-system contract | Unified transfer flow | Discovery required |
| Exchange to Card funding | No public evidence found | None | Exchange backend lead + Card integration lead | Blocked | Unknown cross-system contract | Top-up funding selection | Discovery required |

## 7. Pay Audit Matrix

### Summary

Public evidence confirms product positioning but not API maturity. Marketing copy supports the product thesis: crypto-friendly IBAN, send/receive payments, global access. However, no public API or lifecycle documentation was found for account state, beneficiaries, bank transfers, statements, or eventing. Pay should be treated as `high discovery / likely remediation`.

| Capability | Public evidence | Evidence level | Suggested owner | Current status | Main blocker | UX dependency | Remediation status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Pay account existence/product concept | Gleec Pay page describes a fully-digital bank account with crypto-friendly IBAN | Medium | Pay backend lead | Partially evidenced | Product exists; contract unknown | Spend hub, onboarding | Discovery required |
| Balance retrieval | No public API found | None | Pay backend lead | Blocked | Missing contract visibility | Spend hub, portfolio | Discovery required |
| IBAN details retrieval | Marketing confirms IBAN concept, not API | Weak | Pay backend lead | Needs internal verification | No documented payload | Pay overview, receive flow | Discovery required |
| Send bank transfer | Marketing confirms send/receive capability, not initiation contract | Weak | Pay backend lead | Needs internal verification | No documented transfer contract | Bank transfer flow | Discovery required |
| Receive bank transfer state | Marketing confirms receive capability, not event/status model | Weak | Pay backend lead | Needs internal verification | No documented status feed | Activity, receive flow | Discovery required |
| Beneficiary management | No public evidence found | None | Pay backend lead | Blocked | Unknown beneficiary object and validation rules | Bank transfer composer | Discovery required |
| Transfer status lifecycle | No public evidence found | None | Pay backend lead | Blocked | Unknown status model and review states | Activity detail, recovery | Discovery required |
| Statements/history access | No public evidence found | None | Pay backend lead | Blocked | Unknown statement/history contract | Spend hub, support | Discovery required |
| Pay-to-crypto conversion | Product vision supports it; no public contract found | None | Pay backend lead + Exchange backend lead | Blocked | Unknown conversion workflow and ledger model | Buy flow, transfer flow | Discovery required |
| Crypto-to-Pay conversion | Product vision supports it; no public contract found | None | Pay backend lead + Exchange backend lead | Blocked | Unknown conversion workflow and compliance checks | Sell/off-ramp, transfer flow | Discovery required |
| Pay-to-Card funding | Product/product-plan assumption strong; no public contract found | Weak | Pay backend lead + Card integration lead | Needs internal verification | Unknown funding orchestration | Card top-up | Discovery required |
| KYC/account restrictions | Pay likely depends on verification and region rules; no contract found | Weak | Identity/KYC lead | Needs internal verification | No capability schema | Spend gating | Discovery required |
| Limits and compliance review states | No public evidence found | None | Trust/compliance lead | Blocked | Unknown limits/review contract | Pre-submit warnings, error states | Discovery required |
| Event/webhook coverage | No public evidence found | None | Pay backend lead | Blocked | Unknown push/poll model | Activity freshness | Discovery required |
| Support references and reconciliation IDs | No public evidence found | None | Support tooling lead | Blocked | Unknown transaction-reference model | Activity, support handoff | Discovery required |

## 8. Card Audit Matrix

### Summary

Public evidence confirms core card value proposition: virtual and plastic cards, Apple Pay compatibility, wallet top-up, broad merchant acceptance. However, no public API or lifecycle documentation was found for balance, top-up operations, transaction history, controls, or disputes. Card should also be treated as `high discovery / likely remediation`.

| Capability | Public evidence | Evidence level | Suggested owner | Current status | Main blocker | UX dependency | Remediation status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Card product existence | Gleec Card page confirms product exists | Medium | Card integration lead | Partially evidenced | Product exists; contract unknown | Spend hub | Discovery required |
| Virtual + physical card states | Card page mentions both plastic and virtual cards | Medium | Card integration lead | Partially evidenced | No lifecycle/status contract | Card overview | Discovery required |
| Wallet-to-card top-up concept | Card page says users can send crypto from wallet to card in seconds | Medium | Card integration lead | Partially evidenced | No top-up API or quote model | Top-up flow | Discovery required |
| Card balance retrieval | No public API found | None | Card integration lead | Blocked | Missing balance contract | Spend hub, card overview | Discovery required |
| Top-up initiation | No public API found | None | Card integration lead | Blocked | Missing initiation contract | Top-up flow | Discovery required |
| Top-up quote / conversion breakdown | No public API found | None | Card integration lead | Blocked | Missing FX/fee/ETA contract | Top-up review | Discovery required |
| Card transaction history | No public API found | None | Card integration lead | Blocked | Missing ledger contract | Activity, card overview | Discovery required |
| Freeze / unfreeze | No public evidence found | None | Card integration lead + Issuer operations lead | Blocked | Unknown issuer control contract | Card controls | Discovery required |
| Limits / controls | No public evidence found | None | Card integration lead + Issuer operations lead | Blocked | Unknown issuer control contract | Card settings | Discovery required |
| Sensitive card details reveal | No public evidence found | None | Issuer operations lead | Blocked | Unknown PCI/tokenization boundary | Card detail | Discovery required |
| Replace / report lost card | No public evidence found | None | Issuer operations lead | Blocked | Unknown issuer workflow | Card management | Discovery required |
| Disputes / chargeback initiation | No public evidence found | None | Issuer operations lead + Support tooling lead | Blocked | Unknown dispute initiation and case model | Recovery, support | Discovery required |
| Apple Pay / wallet tokenization state | Marketing mentions Apple Pay support | Weak | Card integration lead | Needs internal verification | No platform integration contract found | Card overview, setup | Discovery required |
| Card eligibility / KYC tiering | Likely required, but no public contract found | Weak | Identity/KYC lead | Needs internal verification | No capability schema | Spend gating | Discovery required |
| Card activity references for support | No public evidence found | None | Support tooling lead | Blocked | Unknown reference and reconciliation model | Activity detail | Discovery required |

## 9. Suggested Remediation Priorities

### P0: Must know before experience lock

| Item | Why it is P0 | Suggested owner | Target phase | Current status |
| --- | --- | --- | --- | --- |
| Unified identity mapping | Every cross-domain flow depends on it | Identity/KYC lead | Phase 0 | Not started |
| Pay balance + transfer contract | Spend hub cannot exist credibly without it | Pay backend lead | Phase 1 | Not started |
| Card balance + top-up contract | Card top-up is a flagship flow | Card integration lead | Phase 1 | Not started |
| Capability matrix schema | Prevents dead-end UX | Trust/compliance lead | Phase 0 | Not started |
| Correlation ID model | Required for Activity and support | Core app integration lead | Phase 1 | Not started |

### P1: Needed for v1 quality

| Item | Why it matters | Suggested owner | Target phase | Current status |
| --- | --- | --- | --- | --- |
| Event/webhook coverage for Pay/Card | Needed for high-quality Activity UX | Pay backend lead + Card integration lead | Phase 1 | Not started |
| Limits/review-state contract | Needed for good error prevention and compliance UX | Trust/compliance lead | Phase 1 | Not started |
| System-status feed integration | Needed for pre-submit reliability messaging | Exchange platform/SRE lead | Phase 1-2 | In discovery |
| Card freeze/unfreeze and status model | Needed for credible card management | Issuer operations lead | Phase 4 | Not started |

### P2: Needed for deeper maturity

| Item | Why it matters | Suggested owner | Target phase | Current status |
| --- | --- | --- | --- | --- |
| Statements and export metadata | Important for banking credibility | Pay backend lead | Phase 4-6 | Not started |
| Dispute initiation and case references | Important for support quality | Issuer operations lead + Support tooling lead | Phase 4-6 | Not started |
| Rich card controls and channel-level limits | Nice-to-have for v1, strong for maturity | Card integration lead | Phase 6 | Not started |

## 10. Suggested Service Audit Checklist

For each domain, audit owners should answer:
1. What is the canonical account identifier?
2. What is the canonical balance model?
3. What actions are synchronous vs async?
4. What statuses are possible, and which are terminal?
5. What IDs can support and users see?
6. What events exist, and how quickly are they emitted?
7. What capability flags are available before submission?
8. What region/KYC restrictions apply?
9. What fields are safe to expose to mobile/web clients?
10. What manual operations still exist behind the scenes?

## 11. Recommended Deliverable Artifacts for Phase 0-1

1. Contract inventory by domain
2. Gap severity register
3. Correlation-ID map across systems
4. Capability matrix schema draft
5. Status normalization draft for Activity
6. Support metadata handoff payload
7. Service readiness scorecard by phase

## 12. Initial Service Readiness View

| Domain | Overall readiness for unified app | Reason |
| --- | --- | --- |
| Exchange | Medium-High | Strong public API evidence for trading, balances, transfers, and transaction states |
| Pay | Low | Product capability is visible publicly, but service contracts are not evidenced |
| Card | Low | Product capability is visible publicly, but lifecycle, top-up, ledger, and issuer controls are not evidenced |
| Cross-system orchestration | Low | Identity, capability, correlation, and event normalization are not yet documented |

## 13. Recommended Next Actions

1. Assign named owners for every row marked `Blocked` or `Needs internal verification`.
2. Run 90-minute audit sessions separately for Exchange, Pay, and Card.
3. Produce one-page contract summaries for each domain.
4. Freeze v1 UX assumptions only after P0 rows have clear answers.
5. Re-baseline timelines if Pay/Card remediation proves deeper than moderate.
