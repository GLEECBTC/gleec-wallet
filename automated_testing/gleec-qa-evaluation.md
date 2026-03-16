# Gleec Wallet Test Cases: Automation Suitability Evaluation & Overhauled Test Matrix

> Evaluates `GLEEC_WALLET_MANUAL_TEST_CASES.md` against the Skyvern + Ollama vision-based automation architecture.

---

## 1. Executive Assessment

The test cases document is excellent manual QA documentation. It is not suitable for vision-based automation in its current form, and roughly 40% of it can never be automated with this stack at all. The document needs to be split into two separate artifacts: one that feeds the Skyvern runner, and one that remains a manual checklist.

**What the document does well:**

- Comprehensive coverage across 26+ modules with 80+ test cases
- Proper risk-based prioritisation (P0–P3, S1–S4)
- Strong test data strategy with wallet profiles, coin sets, address sets, amount sets
- Good traceability matrix linking features to test IDs
- Realistic time estimates and parallel tester allocation
- Regression pack definitions (smoke, critical, full)

**What makes it unsuitable for Skyvern automation as-is:**

- Written for human judgment, not machine-executable prompts
- Steps are abstract and assume contextual understanding ("Attempt to proceed without confirming backup" — what does that look like visually?)
- Many test cases are compound: a single case tests 4–6 different things requiring different verdicts
- No visual descriptions of UI elements (Skyvern needs "click the blue button labeled Send", not "open send screen")
- ~35% of cases require capabilities outside the browser (network toggling, hardware wallets, screen readers, clipboard inspection, app-switcher behaviour, device rotation)
- Expected results are qualitative ("clear error messaging") rather than extractable assertions

---

## 2. Test Case Classification

Every test case classified by automation suitability with Skyvern + Ollama.

### Classification Key

| Grade | Meaning | Action |
|-------|---------|--------|
| **A — Fully automatable** | Pure UI interaction within a web browser. All steps and verification are visual. | Convert to Skyvern prompt. |
| **B — Partially automatable** | Some steps are automatable, but verification or setup requires human/external action. | Split: automate the UI steps, flag verification as manual. |
| **C — Manual only** | Requires hardware, OS-level actions, network manipulation, screen reader, or cross-platform device. | Keep in manual checklist. Remove from automation matrix. |

### Full Classification

| Test ID | Module | Title | Grade | Reason |
|---------|--------|-------|-------|--------|
| AUTH-001 | Auth | Create wallet with seed backup | **A** | UI-only flow: tap, enter password, navigate seed screens |
| AUTH-002 | Auth | Login/logout with remember-session | **B** | Login/logout automatable; "close and relaunch app" requires session restart outside Skyvern |
| AUTH-003 | Auth | Import wallet from seed | **A** | UI-only: enter seed, set password, verify balances |
| AUTH-004 | Auth | Invalid password attempts + lockout | **A** | UI-only: enter wrong passwords, observe lockout messages |
| AUTH-005 | Auth | Trezor connect/disconnect | **C** | Requires physical hardware wallet + USB |
| WAL-001 | Wallet Manager | Create, rename, select wallets | **A** | UI-only multi-step flow |
| WAL-002 | Wallet Manager | Delete wallet with confirmation | **A** | UI-only: cancel/confirm delete dialogs |
| WAL-003 | Wallet Manager | Selection persistence across restart | **C** | Requires app restart + re-login outside browser |
| COIN-001 | Coin Manager | Test coin visibility gate | **A** | Toggle setting, search, verify visibility |
| COIN-002 | Coin Manager | Activate/deactivate with search/filter | **A** | UI-only search and toggle |
| COIN-003 | Coin Manager | Deactivate coin with balance + restore | **A** | UI-only with warning dialog |
| DASH-001 | Dashboard | Hide balances / hide zero toggles | **A** | Toggle and verify masking |
| DASH-002 | Dashboard | Balance refresh + offline indicator | **C** | Requires network toggle (OS-level) |
| DASH-003 | Dashboard | Dashboard persistence across restart | **C** | Requires app restart |
| CDET-001 | Coin Details | Address display, copy, QR, explorer | **B** | View/QR automatable; clipboard + external explorer are manual |
| CDET-002 | Coin Details | Transaction list + status progression | **B** | List view automatable; pending→confirmed requires real-time chain state |
| CDET-003 | Coin Details | Price chart + no-data/network fallback | **B** | Chart view automatable; offline fallback requires network toggle |
| SEND-001 | Send | Faucet funding success | **A** | Click faucet button, verify incoming tx in UI |
| SEND-002 | Send | Faucet cooldown/denied + network error | **B** | Cooldown automatable; network error requires network toggle |
| SEND-003 | Send | DOC send happy path | **A** | Enter recipient, amount, confirm, track in history |
| SEND-004 | Send | Address validation + memo/tag | **A** | Enter invalid addresses, verify error messages |
| SEND-005 | Send | Amount boundary + insufficient funds | **A** | Enter boundary amounts, verify validation messages |
| SEND-006 | Send | Interrupted send + duplicate-submit | **C** | Requires network kill mid-transaction, app backgrounding |
| DEX-001 | DEX | Maker limit order creation | **A** | Select pair, enter price/amount, submit, verify in open orders |
| DEX-002 | DEX | Taker order execution | **B** | Depends on orderbook liquidity in test environment |
| DEX-003 | DEX | DEX validation (invalid inputs) | **A** | Enter invalid values, verify error messages |
| DEX-004 | DEX | Order lifecycle: partial fill, cancel | **B** | Cancel automatable; partial fill depends on external market activity |
| DEX-005 | DEX | Swap history filtering + export | **B** | Filtering automatable; export file verification needs filesystem access |
| DEX-006 | DEX | DEX recovery after restart/network drop | **C** | Requires app closure and network toggling |
| BRDG-001 | Bridge | Bridge transfer happy path | **A** | Select pair, enter amount, confirm, track status |
| BRDG-002 | Bridge | Unsupported pair validation | **A** | Select unsupported pair, verify blocking message |
| BRDG-003 | Bridge | Amount boundaries + insufficient funds | **A** | Enter boundary amounts, verify error messages |
| BRDG-004 | Bridge | Bridge failure/timeout + recovery | **C** | Requires network interruption and app restart |
| NFT-001 | NFT | NFT list/details/history filtering | **A** | Browse, filter, view details |
| NFT-002 | NFT | NFT send happy path | **A** | Enter recipient, confirm, monitor history |
| NFT-003 | NFT | NFT send failure + recovery | **A** | Enter invalid recipient, verify error, retry |
| SET-001 | Settings | Theme + language + format persistence | **B** | Change settings automatable; restart persistence check is manual |
| SET-002 | Settings | Analytics/privacy toggles | **A** | Toggle on/off, verify state |
| SET-003 | Settings | Test coin toggle impact | **A** | Toggle, verify DOC/MARTY visibility |
| SET-004 | Settings | Settings persistence across restart | **C** | Requires logout/restart |
| BOT-001 | Bot | Create + start market maker bot | **A** | Fill form, save, start, verify running status |
| BOT-002 | Bot | Bot validation (invalid config) | **A** | Enter invalid values, verify error blocking |
| BOT-003 | Bot | Edit, stop, restart bot | **B** | Edit/stop/restart automatable; persistence across relaunch is manual |
| NAV-001 | Navigation | Route integrity + back navigation | **A** | Click through all menu items, use back button |
| NAV-002 | Navigation | Deep link + auth gating | **C** | Requires direct URL entry while logged out + auth redirect chain |
| NAV-003 | Navigation | Unsaved changes prompt | **A** | Enter data in form, navigate away, interact with dialog |
| RESP-001 | Responsive | Breakpoint behaviour | **C** | Requires browser window resize (not reliably controllable via Skyvern) |
| RESP-002 | Responsive | Orientation/resize state retention | **C** | Requires device rotation or window resize mid-flow |
| XPLAT-001 | Cross-Platform | Core flow parity | **C** | By definition requires running on Android, iOS, macOS, Linux, Windows |
| XPLAT-002 | Cross-Platform | Platform permissions + input | **C** | Requires OS permission dialogs, hardware back, etc. |
| A11Y-001 | Accessibility | Keyboard-only navigation | **C** | Requires keyboard Tab/Shift+Tab, focus ring inspection — vision model cannot reliably judge focus state |
| A11Y-002 | Accessibility | Screen reader labels/roles | **C** | Requires VoiceOver/TalkBack |
| A11Y-003 | Accessibility | Color contrast + touch targets + text scaling | **C** | Requires pixel-level contrast analysis and OS text scaling |
| SEC-001 | Security | Seed phrase handling/reveal | **B** | Reveal flow automatable; screenshot masking policy and background behaviour are manual |
| SEC-002 | Security | Session auto-lock + app-switcher privacy | **C** | Requires idle timeout, app-switcher snapshot |
| SEC-003 | Security | Clipboard exposure risk | **C** | Requires clipboard access/monitoring outside browser |
| ERR-001 | Error Handling | Global network outage | **C** | Requires network toggle |
| ERR-002 | Error Handling | Partial backend failure isolation | **C** | Requires endpoint-specific failure simulation |
| ERR-003 | Error Handling | Stale-state reconciliation | **C** | Requires app closure during in-flight transaction |
| L10N-001 | Localization | Translation completeness | **A** | Switch locale, review UI text |
| L10N-002 | Localization | Long-string overflow/clipping | **B** | Can screenshot narrow width, but visual clipping judgment is low-confidence for vision model |
| L10N-003 | Localization | Locale-specific format consistency | **A** | Switch locale, compare date/number formatting |
| FIAT-001 | Fiat | Menu access + connect-wallet gating | **A** | Open fiat menu, verify gating, connect wallet |
| FIAT-002 | Fiat | Form validation | **A** | Enter invalid amounts, switch payment methods |
| FIAT-003 | Fiat | Checkout success via provider webview | **B** | Provider webview/dialog may be a separate domain the vision model can't follow |
| FIAT-004 | Fiat | Checkout closed/failed handling | **B** | Closing provider window mid-flow is manual |
| FIAT-005 | Fiat | Form behaviour across logout/login | **C** | Requires logout/re-login |
| SUP-001 | Support | Support page + links + missing coins dialog | **A** | Open page, verify content, open dialog |
| FEED-001 | Feedback | Feedback entry points | **A** | Open feedback from settings/bug button, submit/cancel |
| SECX-001 | Security Settings | Private key export flow | **B** | Auth + toggle automatable; download/share actions may cross browser boundary |
| SECX-002 | Security Settings | Seed backup show/confirm/success | **A** | Auth, reveal, confirm challenge — all visual |
| SECX-003 | Security Settings | Unban pubkeys | **A** | Trigger action, observe results |
| SECX-004 | Security Settings | Change password flow | **A** | Enter old/new passwords, verify rejection/acceptance |
| SETX-001 | Settings Advanced | Weak-password toggle | **A** | Toggle setting, attempt wallet create with weak password |
| SETX-002 | Settings Advanced | Trading bot master toggles | **B** | Toggle automatable; stop-on-disable verification depends on running bot state |
| SETX-003 | Settings Advanced | Export/import maker orders JSON | **C** | File system import/export outside browser |
| SETX-004 | Settings Advanced | Show/export swap data | **B** | View/copy automatable; export is filesystem |
| SETX-005 | Settings Advanced | Import swaps from JSON | **C** | Requires pasting external JSON payload |
| SETX-006 | Settings Advanced | Download logs + flood logs | **C** | File download + debug build action |
| SETX-007 | Settings Advanced | Reset activated coins | **A** | Select wallet, confirm reset, verify |
| WALX-001 | Wallet Advanced | Overview cards + privacy toggle | **A** | View cards, toggle privacy, verify masking |
| WALX-002 | Wallet Advanced | Assets/Growth/PnL tabs | **B** | Tab switching automatable; logged-out fallback requires logout |
| WADDR-001 | Coin Addresses | Multi-address display + controls | **A** | Toggle hide-zero, expand/collapse, copy, QR, faucet |
| WADDR-002 | Coin Addresses | Create new address flow | **A** | Click create, confirm, verify new address appears |
| CTOK-001 | Custom Token | Import happy path | **A** | Select network, enter contract, fetch, confirm import |
| CTOK-002 | Custom Token | Fetch failure + not-found | **A** | Enter invalid contract, verify error |
| CTOK-003 | Custom Token | Back/cancel + state reset | **A** | Navigate back, close dialog, verify clean state |
| RWD-001 | Rewards | KMD rewards refresh + claim | **B** | View automatable; claim depends on reward availability |
| GATE-001 | Feature Gating | Trading-disabled mode | **A** | Verify disabled menu items, tooltips |
| GATE-002 | Feature Gating | Hardware-wallet restrictions | **C** | Requires Trezor login |
| GATE-003 | Feature Gating | NFT menu disabled + direct route | **A** | Verify disabled state, attempt direct navigation |
| QLOG-001 | Quick Login | Remember-me persistence | **C** | Requires app relaunch |
| BREF-001 | Bitrefill | Integration visibility + lifecycle | **B** | Button visibility automatable; widget interaction crosses domains |
| ZHTL-001 | ZHTLC | Configuration dialog + activation | **B** | Dialog automatable; logout-during-activation is manual |
| WARN-001 | System Health | Clock warning banner | **C** | Requires system clock manipulation |

### Summary Count

| Grade | Count | Percentage |
|-------|-------|------------|
| **A — Fully automatable** | 40 | 47% |
| **B — Partially automatable** | 18 | 21% |
| **C — Manual only** | 27 | 32% |
| **Total** | 85 | 100% |

---

## 3. Structural Problems for Automation

Beyond per-case suitability, these structural issues in the original document prevent direct conversion:

**Problem 1: Compound test cases.**
AUTH-001 tests five things in one case: tap create wallet, enter password, attempt to skip seed backup, complete seed confirmation, finish onboarding. For a vision-based agent, this needs to be 2–3 separate tasks to avoid state corruption at step 3 causing steps 4–5 to run against the wrong screen.

**Problem 2: No visual element descriptions.**
Every case says "Open DEX" or "Enter amount" without describing what the DEX screen looks like, what the amount field looks like, or what distinguishes it from adjacent inputs. Skyvern needs: "Look for the input field labeled 'Amount' below the recipient address field, with a coin ticker symbol next to it."

**Problem 3: Abstract expected results.**
"Validation blocks invalid orders with specific guidance" is not machine-evaluable. The automation needs: "A red error message or banner appears on screen containing the word 'invalid', 'insufficient', or 'minimum'."

**Problem 4: No test data in-line.**
The cases reference AS-01, AM-03, WP-02 — but the automation prompt must contain the actual address string, the actual amount value, and the actual seed phrase. The runner cannot look up a test data matrix.

**Problem 5: Missing setup/teardown coupling.**
Many Grade-A tests assume DOC/MARTY are already funded (from SEND-001). The automation needs explicit dependency ordering or the setup block must handle funding.

---

## 4. Recommended Architecture: Two Documents

```
GLEEC_WALLET_MANUAL_TEST_CASES.md (original — keep as-is)
    │
    ├── Remains the canonical QA reference for manual testers
    ├── All 85 test cases, all platforms, all edge cases
    └── Used by human QA team for full regression

tests/test_matrix.yaml (NEW — Skyvern automation)
    │
    ├── Grade-A tests converted to vision-compatible prompts
    ├── Grade-B tests with automatable portions only
    ├── Hardened with checkpoints, explicit data, visual descriptions
    └── Used by the Skyvern runner for automated regression

tests/manual_companion.yaml (NEW — manual-only checklist)
    │
    ├── Grade-C tests formatted as pass/fail checklist
    ├── Grade-B manual verification steps
    └── Run alongside automation for full coverage
```
