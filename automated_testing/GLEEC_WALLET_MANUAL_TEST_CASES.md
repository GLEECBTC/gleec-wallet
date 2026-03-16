# Gleec Wallet Manual Test Case Document (Complete)

## 1. Test Strategy Summary

### Objective

Validate end-to-end manual quality of Gleec Wallet across Web, Android, iOS, macOS, Linux, and Windows for wallet lifecycle, money movement, DEX/bridge/NFT operations, settings, bot features, routing, responsiveness, accessibility, security/privacy, recovery, and localization using **testnet/faucet assets only** (DOC/MARTY).

### In-Scope

- All 18 requested scope areas (auth through localization).
- Additional implemented modules discovered during audit: Fiat on-ramp, support/help + feedback, advanced security controls, advanced settings tooling, custom token import, wallet advanced metrics/multi-address controls, rewards, feature-gating, quick-login remembered wallet, and conditional Bitrefill/ZHTLC/system-health warning behavior.
- Functional, negative, boundary, recovery, compatibility, accessibility, security/privacy checks.
- Faucet behavior through the in-app coin-page faucet action for DOC/MARTY (backed by endpoint pattern `https://faucet.gleec.com/faucet/{COIN}/{ADDRESS}`) including success, cooldown/denied, and network/error handling.

### Out-of-Scope

- Automation scripts/framework implementation.
- Smart-contract/protocol source code audit.
- Performance benchmarking with instrumentation tooling (manual perception checks only).
- Production/mainnet value transfers.

### Assumptions

- Test environment has reachable testnet backend, in-app faucet availability on faucet-coin pages, and DEX/bridge services.
- Testers have at least one valid seed for import flow.
- At least one memo/tag-required asset and one NFT test asset are available in test environment.
- Trezor flows are executed only on supported platforms/configurations.

### Risks

- External service instability (faucet/DEX/bridge nodes) can produce flaky outcomes.
- Cross-platform behavior differences (permissions, deep links, background lifecycle).
- Security/privacy regressions in seed handling, clipboard, session-lock behavior.
- Feature-flag and policy-gated modules (NFT, trading, optional integrations) may differ by environment and require variant-specific execution.
- UI truncation/localization regressions on smaller breakpoints and scaled text.

### Entry Criteria

- QA build installed and launchable on each target platform.
- Access to DOC/MARTY test coins with test-coins toggle available.
- Test wallets and addresses prepared per Section 3.
- Known failing automated tests acknowledged; manual/static-analysis focus accepted.

### Exit Criteria

- All `P0` and `P1` tests executed; no open `S1`/`S2` defects for release candidate.
- Regression pack execution complete with documented evidence.
- Critical recovery/security/accessibility checks executed and signed off.
- Defect triage complete with disposition for all opened issues.

---

## 2. Test Environment Matrix

| Platform | OS / Device / Browser                                             | Build Type                        | Network Condition Notes                        | Required Test Accounts / Wallet Setup |
| -------- | ----------------------------------------------------------------- | --------------------------------- | ---------------------------------------------- | ------------------------------------- |
| Web      | Chrome latest, Firefox latest, Safari latest (macOS), Edge latest | QA/Staging web build              | Normal broadband, throttled 3G, offline toggle | WP-01, WP-02, WP-03                   |
| Android  | Android 13/14 on mid-range + flagship devices                     | QA APK/AAB (debuggable QA flavor) | Wi-Fi, LTE, airplane on/off transitions        | WP-01, WP-02, WP-03                   |
| iOS      | iOS 17/18 on iPhone + iPad                                        | QA/TestFlight build               | Wi-Fi, cellular, Low Data Mode                 | WP-01, WP-02, WP-03                   |
| macOS    | macOS 14/15 Intel + Apple Silicon                                 | QA desktop build                  | Ethernet/Wi-Fi, VPN on/off                     | WP-01, WP-02, WP-03, WP-04            |
| Linux    | Ubuntu 22.04+ desktop                                             | QA desktop build                  | Ethernet/Wi-Fi, packet loss simulation         | WP-01, WP-02, WP-03, WP-04            |
| Windows  | Windows 11 desktop                                                | QA desktop build                  | Ethernet/Wi-Fi, firewall-restricted scenario   | WP-01, WP-02, WP-03, WP-04            |

---

## 3. Test Data Strategy

### Wallet Profiles

| ID    | Profile                                    | Purpose                                             |
| ----- | ------------------------------------------ | --------------------------------------------------- |
| WP-01 | New wallet (freshly created)               | Onboarding, auth, seed backup, default state checks |
| WP-02 | Imported wallet (valid 12/24-word seed)    | Restore, sync, returning-user behavior              |
| WP-03 | Funded faucet wallet (DOC + MARTY balance) | Send/DEX/bridge/NFT transactions                    |
| WP-04 | Hardware wallet (Trezor where supported)   | Hardware connect/sign/reject paths                  |

### Coin Sets

| ID    | Coin Set                                                           | Purpose                              |
| ----- | ------------------------------------------------------------------ | ------------------------------------ |
| CS-01 | Test coins enabled; DOC and MARTY visible/activated                | Primary blockchain activity tests    |
| CS-02 | Test coins disabled                                                | Visibility and settings gate checks  |
| CS-03 | Mixed activation (DOC active, MARTY inactive, another coin active) | Filter/search/activation state tests |

### Address Sets

| ID    | Address Type                                              | Example Use                           |
| ----- | --------------------------------------------------------- | ------------------------------------- |
| AS-01 | Valid DOC recipient                                       | Happy-path send/faucet                |
| AS-02 | Valid MARTY recipient                                     | Happy-path send/faucet                |
| AS-03 | Invalid format/checksum                                   | Negative send/bridge/NFT              |
| AS-04 | Valid-looking wrong-network address                       | Unsupported format/network validation |
| AS-05 | Unsupported asset address                                 | Error handling                        |
| AS-06 | Self address                                              | Self-send restrictions/warnings       |
| AS-07 | Valid memo/tag coin address with missing tag vs valid tag | Memo/tag validation                   |

### Amount Sets

| ID    | Amount Pattern               | Purpose                             |
| ----- | ---------------------------- | ----------------------------------- |
| AM-01 | `0`                          | Required positive amount validation |
| AM-02 | Below minimum transfer       | Boundary negative                   |
| AM-03 | Minimum valid transfer       | Boundary positive                   |
| AM-04 | Excess precision decimals    | Decimal precision handling          |
| AM-05 | Spendable balance minus fee  | Max-send boundary                   |
| AM-06 | Amount + fee > balance       | Insufficient funds                  |
| AM-07 | Large valid amount           | Upper-range acceptance              |
| AM-08 | Bridge below min / above max | Bridge validation                   |

### Faucet Outcomes

| ID    | Faucet Condition            | Expected                                       |
| ----- | --------------------------- | ---------------------------------------------- |
| FD-01 | First valid request         | Success response + incoming tx/pending state   |
| FD-02 | Rapid repeat request        | Denied/cooldown message shown and handled      |
| FD-03 | Network failure/500/timeout | Error state + retry guidance without app crash |

---

## 4. Requirement/Feature Traceability Matrix (RTM)

| Feature ID | Feature Name                      | Risk   | Mapped Test Case IDs                                | Platform Coverage                 |
| ---------- | --------------------------------- | ------ | --------------------------------------------------- | --------------------------------- |
| F01        | Authentication & wallet lifecycle | High   | GW-MAN-AUTH-001..005                                | All; Trezor subset on desktop/web |
| F02        | Wallet manager                    | High   | GW-MAN-WAL-001..003                                 | All                               |
| F03        | Coin manager                      | Medium | GW-MAN-COIN-001..003                                | All                               |
| F04        | Dashboard & balances              | Medium | GW-MAN-DASH-001..003                                | All                               |
| F05        | Coin details                      | Medium | GW-MAN-CDET-001..003                                | All                               |
| F06        | Withdraw/Send                     | High   | GW-MAN-SEND-001..006                                | All                               |
| F07        | DEX flows                         | High   | GW-MAN-DEX-001..006                                 | All                               |
| F08        | Bridge flows                      | High   | GW-MAN-BRDG-001..004                                | All                               |
| F09        | NFT flows                         | Medium | GW-MAN-NFT-001..003                                 | All                               |
| F10        | Settings & persistence            | Medium | GW-MAN-SET-001..004                                 | All                               |
| F11        | Market maker bot                  | Medium | GW-MAN-BOT-001..003                                 | All                               |
| F12        | Navigation & routing              | Medium | GW-MAN-NAV-001..003                                 | All                               |
| F13        | Responsive behavior               | Medium | GW-MAN-RESP-001..002                                | Web + mobile/tablet + desktop     |
| F14        | Cross-platform differences        | High   | GW-MAN-XPLAT-001..002                               | All                               |
| F15        | Accessibility (WCAG 2.2 AA)       | High   | GW-MAN-A11Y-001..003                                | All                               |
| F16        | Security & privacy                | High   | GW-MAN-SEC-001..003                                 | All                               |
| F17        | Error handling & recovery         | High   | GW-MAN-ERR-001..003 + SEND-006 + DEX-006 + BRDG-004 | All                               |
| F18        | Localization/readability          | Medium | GW-MAN-L10N-001..003 + SET-001                      | All                               |
| F19        | Fiat on-ramp                      | High   | GW-MAN-FIAT-001..005                                | All                               |
| F20        | Support/help and feedback         | Medium | GW-MAN-SUP-001 + GW-MAN-FEED-001                    | All                               |
| F21        | Advanced security controls        | High   | GW-MAN-SECX-001..004                                | All                               |
| F22        | Advanced settings tooling         | Medium | GW-MAN-SETX-001..007                                | All                               |
| F23        | Wallet advanced address/portfolio | Medium | GW-MAN-WALX-001..002 + GW-MAN-WADDR-001..002        | All                               |
| F24        | Custom token import               | High   | GW-MAN-CTOK-001..003                                | All                               |
| F25        | Rewards and optional integrations | Medium | GW-MAN-RWD-001 + GW-MAN-BREF-001 + GW-MAN-ZHTL-001  | All (conditional as flagged)      |
| F26        | Feature gating and quick-login    | High   | GW-MAN-GATE-001..003 + GW-MAN-QLOG-001 + GW-MAN-WARN-001 | All                          |

---

## 5. Detailed Manual Test Cases (Core)

### Authentication & Wallet Lifecycle

#### GW-MAN-AUTH-001

**Module:** Authentication and Wallet Lifecycle
**Title:** Create wallet with mandatory seed backup confirmation
**Priority/Severity/Type:** P0 / S1 / Smoke, Functional, Security
**Platform(s):** Web, Android, iOS, macOS, Linux, Windows
**Preconditions:** Fresh install; app on welcome screen.
**Test Data:** WP-01
**Steps:**

1. Tap `Create Wallet`.
2. Enter a valid password and confirm it.
3. Continue to seed phrase screen and attempt to proceed without confirming backup.
4. Complete required seed confirmation challenge.
5. Finish onboarding.
   **Expected Result:** Progress is blocked until seed confirmation is completed; wallet is created and user lands on dashboard.
   **Post-conditions:** Authenticated session exists for newly created wallet.
   **Dependencies/Notes:** Seed must not be exposed outside explicit seed screens.

#### GW-MAN-AUTH-002

**Module:** Authentication and Wallet Lifecycle
**Title:** Login/logout with remember-session behavior
**Priority/Severity/Type:** P0 / S1 / Smoke, Functional, Regression
**Platform(s):** All
**Preconditions:** Existing wallet and password.
**Test Data:** WP-01
**Steps:**

1. Log out from settings/account menu.
2. Log in with correct password and enable remember option (if available).
3. Close and relaunch app.
4. Verify whether session follows remember option behavior.
5. Log out again and relaunch.
   **Expected Result:** Login works with valid credentials; remember option persists correctly; logout always clears active session.
   **Post-conditions:** User logged out after final step.
   **Dependencies/Notes:** Validate identical behavior across platforms.

#### GW-MAN-AUTH-003

**Module:** Authentication and Wallet Lifecycle
**Title:** Import wallet from valid seed and sync balances
**Priority/Severity/Type:** P0 / S1 / Functional, Regression
**Platform(s):** All
**Preconditions:** User is on onboarding/import screen.
**Test Data:** WP-02 seed; CS-01
**Steps:**

1. Choose `Import Wallet`.
2. Enter valid seed phrase and set password.
3. Complete import.
4. Enable test coins if disabled.
5. Open DOC and MARTY balances/history.
   **Expected Result:** Import succeeds; wallet addresses match expected profile; balances/history synchronize.
   **Post-conditions:** Imported wallet available in wallet manager.
   **Dependencies/Notes:** Use only testnet-derived seed.

#### GW-MAN-AUTH-004

**Module:** Authentication and Wallet Lifecycle
**Title:** Invalid password attempts and cooldown/lock handling
**Priority/Severity/Type:** P0 / S1 / Negative, Security
**Platform(s):** All
**Preconditions:** Wallet locked at login screen.
**Test Data:** Wrong password variants
**Steps:**

1. Enter incorrect password repeatedly until limit is reached.
2. Observe lockout/cooldown feedback.
3. Attempt login during cooldown.
4. Wait for cooldown expiry and login with correct password.
   **Expected Result:** Invalid attempts are rejected; cooldown is enforced and messaged; valid login works after cooldown.
   **Post-conditions:** Session active after successful login.
   **Dependencies/Notes:** No sensitive hints about correct password should appear.

#### GW-MAN-AUTH-005

**Module:** Authentication and Wallet Lifecycle
**Title:** Trezor connect/disconnect and signing availability (where supported)
**Priority/Severity/Type:** P0 / S1 / Functional, Compatibility, Security
**Platform(s):** Web (supported browsers), macOS, Linux, Windows
**Preconditions:** Trezor connected and recognized by OS; supported build.
**Test Data:** WP-04
**Steps:**

1. Open hardware wallet flow and connect Trezor.
2. Authorize access and import/select hardware account.
3. Start a sign-required action (e.g., send preview) and confirm on device.
4. Disconnect device and retry action.
   **Expected Result:** Device-based flow succeeds when connected; app blocks or prompts reconnection when disconnected; no crash.
   **Post-conditions:** Hardware account state is consistent.
   **Dependencies/Notes:** Skip on unsupported platform and mark N/A.

---

### Wallet Manager

#### GW-MAN-WAL-001

**Module:** Wallet Manager
**Title:** Create, rename, and select among multiple wallets
**Priority/Severity/Type:** P0 / S2 / Functional, Regression
**Platform(s):** All
**Preconditions:** Logged in with one wallet.
**Test Data:** WP-01 + additional created wallet
**Steps:**

1. Open wallet manager and create second wallet.
2. Rename both wallets with unique names.
3. Switch active wallet multiple times.
4. Verify dashboard content changes with selected wallet.
   **Expected Result:** Wallet list updates immediately; rename persists; selected wallet context switches correctly.
   **Post-conditions:** Two wallets exist with distinct names.
   **Dependencies/Notes:** Names should reject invalid-only-whitespace input.

#### GW-MAN-WAL-002

**Module:** Wallet Manager
**Title:** Delete wallet with confirmation and active wallet safety
**Priority/Severity/Type:** P0 / S1 / Functional, Negative, Security
**Platform(s):** All
**Preconditions:** At least two wallets exist.
**Test Data:** Wallet to delete contains no critical unsaved operation
**Steps:**

1. Open wallet manager and choose a non-active wallet to delete.
2. Cancel deletion at confirmation prompt.
3. Repeat and confirm deletion.
4. Attempt deleting final remaining wallet (if app prevents it).
   **Expected Result:** Cancel keeps wallet unchanged; confirm removes target wallet; safety rule for last wallet is enforced as designed.
   **Post-conditions:** Only intended wallet removed.
   **Dependencies/Notes:** Verify no orphaned data remains visible.

#### GW-MAN-WAL-003

**Module:** Wallet Manager
**Title:** Selected wallet persistence across restart/login
**Priority/Severity/Type:** P1 / S2 / Functional, Recovery
**Platform(s):** All
**Preconditions:** Multiple wallets available; remember option known state.
**Test Data:** WP-01 + WP-02
**Steps:**

1. Select wallet B as active.
2. Close and relaunch app.
3. Log in if prompted.
4. Check active wallet selection.
   **Expected Result:** Active wallet persistence follows app design and remains consistent after relaunch/login.
   **Post-conditions:** Wallet selection state stable.
   **Dependencies/Notes:** Validate same behavior on mobile and desktop.

---

### Coin Manager

#### GW-MAN-COIN-001

**Module:** Coin Manager
**Title:** Test coin visibility gate for DOC and MARTY
**Priority/Severity/Type:** P1 / S2 / Functional, Smoke
**Platform(s):** All
**Preconditions:** Logged in; coin manager accessible.
**Test Data:** CS-01, CS-02
**Steps:**

1. Disable test coin setting; search for DOC/MARTY.
2. Enable test coin setting.
3. Search for DOC and MARTY again.
4. Activate both coins.
   **Expected Result:** DOC/MARTY hidden when test coins disabled; visible and activatable when enabled.
   **Post-conditions:** DOC/MARTY active for subsequent tests.
   **Dependencies/Notes:** Mandatory pre-step for blockchain test cases.

#### GW-MAN-COIN-002

**Module:** Coin Manager
**Title:** Activate/deactivate coin with search and filter behavior
**Priority/Severity/Type:** P1 / S2 / Functional, Regression
**Platform(s):** All
**Preconditions:** Test coins enabled.
**Test Data:** CS-03
**Steps:**

1. Use search to find MARTY and activate it.
2. Apply active-only filter and verify MARTY listed.
3. Deactivate MARTY.
4. Clear filters and verify list updates.
   **Expected Result:** Activation state changes immediately and filter/search reflect current status correctly.
   **Post-conditions:** Coin states match final user actions.
   **Dependencies/Notes:** Confirm no duplicated entries.

#### GW-MAN-COIN-003

**Module:** Coin Manager
**Title:** Deactivate coin with balance/history and restore state
**Priority/Severity/Type:** P1 / S2 / Functional, Recovery
**Platform(s):** All
**Preconditions:** DOC has non-zero balance/history.
**Test Data:** WP-03, DOC funded
**Steps:**

1. Attempt to deactivate DOC with non-zero balance.
2. Confirm warning dialog behavior.
3. Complete deactivation if allowed.
4. Reactivate DOC and open its details.
   **Expected Result:** Warning is shown; deactivation policy enforced; reactivation restores historical data and address correctly.
   **Post-conditions:** DOC active for money-flow tests.
   **Dependencies/Notes:** No loss of transaction history after reactivation.

---

### Dashboard & Balances

#### GW-MAN-DASH-001

**Module:** Wallet Dashboard
**Title:** Hide balances and hide zero balances toggles
**Priority/Severity/Type:** P1 / S2 / Functional, Security
**Platform(s):** All
**Preconditions:** Multiple coins with zero and non-zero balances.
**Test Data:** WP-03
**Steps:**

1. Enable `Hide Balances`.
2. Verify amounts are masked on dashboard and coin list.
3. Enable `Hide Zero Balances`.
4. Verify zero-balance assets are hidden while non-zero remain.
   **Expected Result:** Masking and zero-balance filtering apply consistently across applicable views.
   **Post-conditions:** Restore preferred toggle states for later tests.
   **Dependencies/Notes:** Sensitive values must not flash during transitions.

#### GW-MAN-DASH-002

**Module:** Wallet Dashboard
**Title:** Balance refresh, loading states, and offline indicator
**Priority/Severity/Type:** P1 / S2 / Functional, Recovery
**Platform(s):** All
**Preconditions:** Dashboard loaded with active DOC/MARTY.
**Test Data:** WP-03
**Steps:**

1. Trigger manual refresh.
2. Observe loading indicator behavior.
3. Disable network and refresh again.
4. Re-enable network and retry refresh.
   **Expected Result:** Loading and failure states are clear; offline state shown without crash; data refresh recovers after network returns.
   **Post-conditions:** Fresh balance state loaded.
   **Dependencies/Notes:** Stale timestamp/last-updated marker should update.

#### GW-MAN-DASH-003

**Module:** Wallet Dashboard
**Title:** Dashboard state persistence for returning user
**Priority/Severity/Type:** P2 / S3 / Regression
**Platform(s):** All
**Preconditions:** User has customized dashboard toggles/order (if supported).
**Test Data:** WP-03
**Steps:**

1. Set balance visibility and preferred sorting options.
2. Log out and log back in.
3. Relaunch app.
4. Re-open dashboard.
   **Expected Result:** User preferences persist according to product rules and remain consistent after relaunch.
   **Post-conditions:** User returns to preferred dashboard state.
   **Dependencies/Notes:** Validate no preference reset on minor restart.

---

### Coin Details

#### GW-MAN-CDET-001

**Module:** Coin Details
**Title:** Address display, copy, QR, and explorer launch
**Priority/Severity/Type:** P1 / S2 / Functional, Compatibility
**Platform(s):** All
**Preconditions:** DOC active.
**Test Data:** AS-01
**Steps:**

1. Open DOC coin details.
2. Copy receive address.
3. Open QR view and verify address matches.
4. Tap explorer link.
   **Expected Result:** Address is consistent across text/QR/copy; explorer opens correct network/address URL.
   **Post-conditions:** Address copied to clipboard.
   **Dependencies/Notes:** Validate clipboard handling with SEC tests.

#### GW-MAN-CDET-002

**Module:** Coin Details
**Title:** Transaction list, detail view, and status progression
**Priority/Severity/Type:** P1 / S2 / Functional, Regression
**Platform(s):** All
**Preconditions:** DOC or MARTY has pending and confirmed tx history.
**Test Data:** WP-03
**Steps:**

1. Open transaction list for DOC.
2. Open a pending transaction detail.
3. Refresh after confirmation period.
4. Open confirmed transaction detail.
   **Expected Result:** Correct fields shown (hash, amount, fee, status, timestamp, addresses); pending transitions to confirmed accurately.
   **Post-conditions:** Tx detail views validated.
   **Dependencies/Notes:** Timestamp/date formatting also checked in L10N suite.

#### GW-MAN-CDET-003

**Module:** Coin Details
**Title:** Price chart visibility and no-data/network fallback
**Priority/Severity/Type:** P2 / S3 / Functional, Recovery
**Platform(s):** All
**Preconditions:** Coin details screen available.
**Test Data:** DOC/MARTY with possible missing chart feed
**Steps:**

1. Open chart tab for coin.
2. Switch time ranges.
3. Disable network and retry chart load.
4. Re-enable network and reload.
   **Expected Result:** Chart renders when data exists; graceful placeholder/message shown on no-data/offline states; recovery works.
   **Post-conditions:** Chart state restored.
   **Dependencies/Notes:** No UI overlap/truncation on small screens.

---

### Send / Withdraw

#### GW-MAN-SEND-001

**Module:** Send/Withdraw
**Title:** Faucet funding success for DOC/MARTY
**Priority/Severity/Type:** P0 / S1 / Smoke, Functional
**Platform(s):** All
**Preconditions:** CS-01 enabled; receive addresses available.
**Test Data:** AS-01, AS-02, FD-01
**Steps:**

1. Copy DOC receive address from app.
2. Open DOC coin page and trigger the in-app faucet action.
3. Open MARTY coin page and trigger the in-app faucet action.
4. Refresh balances/history from within the app.
   **Expected Result:** Faucet success response is shown; incoming transactions appear as pending then confirmed; balances increase accordingly.
   **Post-conditions:** Wallet funded with DOC/MARTY for transaction tests.
   **Dependencies/Notes:** Testnet assets only; no real-value funds.

#### GW-MAN-SEND-002

**Module:** Send/Withdraw
**Title:** Faucet cooldown/denied and network/error handling
**Priority/Severity/Type:** P0 / S1 / Negative, Recovery
**Platform(s):** All
**Preconditions:** At least one successful faucet request already made recently.
**Test Data:** FD-02, FD-03
**Steps:**

1. From the faucet coin page, re-submit in-app faucet request immediately for the same coin/address.
2. Observe cooldown/denied response.
3. Trigger network failure (offline or unreachable endpoint) and retry the in-app faucet request.
4. Restore network and retry later.
   **Expected Result:** Cooldown/denied responses are surfaced clearly; network failure shows retriable error; app remains stable.
   **Post-conditions:** Faucet retry policy understood and logged.
   **Dependencies/Notes:** Capture response message text for defect reporting if inconsistent.

#### GW-MAN-SEND-003

**Module:** Send/Withdraw
**Title:** DOC send happy path with fee and confirmation
**Priority/Severity/Type:** P0 / S1 / Smoke, Functional, Regression
**Platform(s):** All
**Preconditions:** WP-03 funded; destination AS-01 available.
**Test Data:** AM-03/AM-07
**Steps:**

1. Open DOC send screen.
2. Enter valid recipient and amount.
3. Review fee and confirmation summary.
4. Confirm transaction.
5. Track status in history until confirmed.
   **Expected Result:** Transaction submitted once; fee/amount match summary; history shows pending then confirmed with correct net balance change.
   **Post-conditions:** Outgoing transaction recorded.
   **Dependencies/Notes:** Validate tx hash opens correct explorer page.

#### GW-MAN-SEND-004

**Module:** Send/Withdraw
**Title:** Address validation and memo/tag-required enforcement
**Priority/Severity/Type:** P0 / S1 / Negative, Boundary
**Platform(s):** All
**Preconditions:** Send screen open.
**Test Data:** AS-03, AS-04, AS-05, AS-07
**Steps:**

1. Enter invalid address and valid amount; attempt continue.
2. Enter wrong-network/unsupported address; attempt continue.
3. For memo/tag-required asset, enter valid address without memo/tag.
4. Add valid memo/tag and continue.
   **Expected Result:** Invalid/unsupported addresses blocked with clear error; memo/tag-required transfer blocked until valid memo/tag provided.
   **Post-conditions:** No invalid transaction broadcast.
   **Dependencies/Notes:** Use any available memo/tag-required test asset.

#### GW-MAN-SEND-005

**Module:** Send/Withdraw
**Title:** Amount boundary, precision, max-send, and insufficient funds
**Priority/Severity/Type:** P0 / S1 / Boundary, Negative
**Platform(s):** All
**Preconditions:** Funded wallet.
**Test Data:** AM-01, AM-02, AM-04, AM-05, AM-06
**Steps:**

1. Enter amount `0` and attempt continue.
2. Enter below-minimum amount and attempt continue.
3. Enter overly precise decimal amount.
4. Use max-send/spendable boundary amount.
5. Enter amount that exceeds balance after fees.
   **Expected Result:** Invalid amounts rejected with specific messages; max-send computes correctly; insufficient-balance scenario blocked pre-submit.
   **Post-conditions:** No failed broadcast from client-side validation cases.
   **Dependencies/Notes:** Fee recalculation must be deterministic.

#### GW-MAN-SEND-006

**Module:** Send/Withdraw
**Title:** Interrupted send flow recovery and duplicate-submit prevention
**Priority/Severity/Type:** P0 / S1 / Recovery, Regression
**Platform(s):** All
**Preconditions:** Valid send form prepared.
**Test Data:** AS-01, AM-03
**Steps:**

1. Submit send transaction.
2. Immediately disable network or background/close app during pending state.
3. Re-open app and return to history/send screen.
4. Re-enable network and sync.
5. Attempt to resubmit same transaction quickly.
   **Expected Result:** Pending transaction state is recovered; app prevents accidental duplicate submits; final state reconciles to confirmed/failed accurately.
   **Post-conditions:** Transaction history consistent after recovery.
   **Dependencies/Notes:** Critical data-integrity check.

---

### DEX

#### GW-MAN-DEX-001

**Module:** DEX
**Title:** Maker limit order creation and open-order visibility
**Priority/Severity/Type:** P0 / S1 / Functional, Smoke
**Platform(s):** All
**Preconditions:** Funded wallet with tradable pair assets.
**Test Data:** DOC/MARTY pair; AM-03
**Steps:**

1. Open DEX and select DOC/MARTY pair.
2. Choose maker/limit order.
3. Enter valid price and amount.
4. Submit order and open `Open Orders`.
   **Expected Result:** Order created successfully and appears in open orders with correct pair, price, amount, and status.
   **Post-conditions:** One active maker order exists.
   **Dependencies/Notes:** Verify locked balance reflects open order.

#### GW-MAN-DEX-002

**Module:** DEX
**Title:** Taker order execution from orderbook
**Priority/Severity/Type:** P0 / S1 / Functional, Regression
**Platform(s):** All
**Preconditions:** Orderbook has available liquidity.
**Test Data:** DOC/MARTY amount in AM-03..AM-07
**Steps:**

1. Select an existing orderbook level.
2. Choose taker action and review estimated fill.
3. Confirm trade.
4. Track swap/order status to completion.
   **Expected Result:** Taker order executes against orderbook; execution details and final balances match expected trade outcomes.
   **Post-conditions:** Completed swap/order appears in history.
   **Dependencies/Notes:** If no liquidity, use test environment seeding before run.

#### GW-MAN-DEX-003

**Module:** DEX
**Title:** DEX validation for invalid pair/price/amount/insufficient funds
**Priority/Severity/Type:** P0 / S1 / Negative, Boundary
**Platform(s):** All
**Preconditions:** DEX form open.
**Test Data:** Invalid pair, AM-01, AM-02, AM-06
**Steps:**

1. Attempt order with unsupported/disabled pair.
2. Enter zero/negative/below-min amount.
3. Enter price outside allowed precision/range.
4. Attempt submit with insufficient funds.
   **Expected Result:** Validation blocks invalid orders with specific guidance; no invalid order enters orderbook.
   **Post-conditions:** No new open order created from invalid input.
   **Dependencies/Notes:** Decision-table style checks across pair+amount+balance conditions.

#### GW-MAN-DEX-004

**Module:** DEX
**Title:** Order lifecycle: partial fill, cancel, final state consistency
**Priority/Severity/Type:** P0 / S1 / Functional, Recovery
**Platform(s):** All
**Preconditions:** Maker order placed with potential partial fills.
**Test Data:** Existing open order
**Steps:**

1. Place maker order with moderate size.
2. Wait for partial fill.
3. Cancel remaining quantity.
4. Verify final status in open/history tabs.
   **Expected Result:** Lifecycle transitions are accurate (open -> partial -> canceled/filled); balances/locked funds reconcile correctly.
   **Post-conditions:** No stale locked balance remains.
   **Dependencies/Notes:** High-risk integrity path.

#### GW-MAN-DEX-005

**Module:** DEX
**Title:** Swap/order history filtering and export
**Priority/Severity/Type:** P1 / S2 / Functional, Regression
**Platform(s):** All
**Preconditions:** Multiple historical swaps/orders exist.
**Test Data:** Time ranges, pair filters, status filters
**Steps:**

1. Open history tab.
2. Filter by pair, date range, and status.
3. Validate filtered rows.
4. Export history (CSV/file) and open exported file.
   **Expected Result:** Filtered results are accurate; exported data matches visible records and formatting expectations.
   **Post-conditions:** Export artifact generated.
   **Dependencies/Notes:** Verify timestamp/decimal localization impact.

#### GW-MAN-DEX-006

**Module:** DEX
**Title:** DEX recovery after app restart/network drop
**Priority/Severity/Type:** P0 / S1 / Recovery
**Platform(s):** All
**Preconditions:** At least one active/pending DEX operation.
**Test Data:** Open order and pending swap
**Steps:**

1. Start DEX operation and force app closure or temporary offline state.
2. Reopen app and navigate to DEX.
3. Refresh open orders/history.
4. Verify status reconciliation with backend.
   **Expected Result:** DEX state is restored without duplication; final statuses are correct; no ghost orders.
   **Post-conditions:** DEX state synchronized.
   **Dependencies/Notes:** Capture any stale-state mismatch as S1/S2.

---

### Bridge

#### GW-MAN-BRDG-001

**Module:** Bridge
**Title:** Bridge transfer happy path with valid pair/protocol
**Priority/Severity/Type:** P0 / S1 / Functional, Smoke
**Platform(s):** All
**Preconditions:** Bridge-supported test pair available and funded.
**Test Data:** AM-03, valid recipient
**Steps:**

1. Open Bridge and select supported source/destination pair.
2. Enter valid amount and destination details.
3. Review fees/ETA and confirm.
4. Track bridge status to completion.
   **Expected Result:** Bridge transfer is created; status progresses correctly; destination balance/history updates after completion.
   **Post-conditions:** Successful bridge record in history.
   **Dependencies/Notes:** Testnet routes only.

#### GW-MAN-BRDG-002

**Module:** Bridge
**Title:** Unsupported pair/protocol validation
**Priority/Severity/Type:** P0 / S1 / Negative
**Platform(s):** All
**Preconditions:** Bridge screen available.
**Test Data:** Unsupported pair selection attempts
**Steps:**

1. Select unsupported token-chain pair (or disable protocol prerequisite).
2. Enter amount and attempt continue.
3. Observe validation messaging.
   **Expected Result:** Unsupported combinations are blocked before submission with clear corrective message.
   **Post-conditions:** No bridge operation started.
   **Dependencies/Notes:** Validate both pair-level and protocol-level constraints.

#### GW-MAN-BRDG-003

**Module:** Bridge
**Title:** Amount boundaries, fees, and insufficient funds checks
**Priority/Severity/Type:** P0 / S1 / Boundary, Negative
**Platform(s):** All
**Preconditions:** Bridge form open with supported pair.
**Test Data:** AM-08, AM-06
**Steps:**

1. Enter below-minimum bridge amount.
2. Enter above-maximum amount.
3. Enter amount causing insufficient funds after fees.
4. Enter valid boundary amount and recheck fee preview.
   **Expected Result:** Invalid amounts are rejected; fee preview is consistent; valid boundary amount proceeds.
   **Post-conditions:** No invalid bridge request submitted.
   **Dependencies/Notes:** Confirm displayed min/max source is current.

#### GW-MAN-BRDG-004

**Module:** Bridge
**Title:** Bridge failure/timeout and retry/recovery after restart
**Priority/Severity/Type:** P0 / S1 / Recovery
**Platform(s):** All
**Preconditions:** Active bridge request in progress.
**Test Data:** Simulated timeout/network interruption
**Steps:**

1. Initiate bridge transfer.
2. Introduce network outage or wait for timeout condition.
3. Observe failed/pending timeout state and retry option.
4. Restart app and reopen bridge history.
5. Retry or resync status.
   **Expected Result:** Failure state is explicit; retry/resync is available; final state reconciles correctly after restart.
   **Post-conditions:** Bridge history reflects final authoritative status.
   **Dependencies/Notes:** Must not duplicate transfer on retry.

---

### NFT

#### GW-MAN-NFT-001

**Module:** NFT
**Title:** NFT list/details/history filtering
**Priority/Severity/Type:** P1 / S2 / Functional
**Platform(s):** All
**Preconditions:** Wallet contains NFT test assets.
**Test Data:** NFT collection with multiple items
**Steps:**

1. Open NFT module and view list.
2. Open one NFT detail page.
3. Apply filters (collection/status/date if available).
4. Open NFT history.
   **Expected Result:** List and details load correctly; filters return expected subset; history shows accurate actions/statuses.
   **Post-conditions:** NFT module state stable.
   **Dependencies/Notes:** Metadata fallback handled in NFT-003 if needed.

#### GW-MAN-NFT-002

**Module:** NFT
**Title:** NFT send happy path
**Priority/Severity/Type:** P1 / S2 / Functional, Regression
**Platform(s):** All
**Preconditions:** Transferable NFT available; recipient valid.
**Test Data:** Valid recipient address for NFT network
**Steps:**

1. Open NFT detail and choose `Send`.
2. Enter valid recipient.
3. Review fee/confirmation.
4. Confirm transfer and monitor history.
   **Expected Result:** NFT transfer submits successfully; history updates pending -> confirmed; ownership moves accordingly.
   **Post-conditions:** Sender no longer owns transferred NFT after confirmation.
   **Dependencies/Notes:** Testnet NFT assets only.

#### GW-MAN-NFT-003

**Module:** NFT
**Title:** NFT send failure for invalid recipient/not-owner and recovery
**Priority/Severity/Type:** P1 / S2 / Negative, Recovery
**Platform(s):** All
**Preconditions:** NFT send form available.
**Test Data:** AS-03/AS-04; already transferred NFT
**Steps:**

1. Attempt NFT send with invalid recipient.
2. Attempt resend from wallet that no longer owns NFT.
3. Correct recipient and retry with owned NFT.
   **Expected Result:** Invalid/not-owner actions are blocked with clear errors; valid retry succeeds without UI corruption.
   **Post-conditions:** NFT ownership remains correct.
   **Dependencies/Notes:** Verify no duplicate pending rows after failed attempts.

---

### Settings

#### GW-MAN-SET-001

**Module:** Settings
**Title:** Theme + language + date/number format persistence
**Priority/Severity/Type:** P1 / S2 / Functional, Regression
**Platform(s):** All
**Preconditions:** Logged in; settings accessible.
**Test Data:** Two themes; two locales
**Steps:**

1. Change theme.
2. Change app language/locale.
3. Verify dates/numbers on dashboard/history.
4. Restart app and recheck.
   **Expected Result:** Theme and locale apply immediately; formats match locale; settings persist after restart.
   **Post-conditions:** User preferences retained.
   **Dependencies/Notes:** Supports L10N coverage linkage.

#### GW-MAN-SET-002

**Module:** Settings
**Title:** Analytics/privacy/diagnostic toggles behavior
**Priority/Severity/Type:** P1 / S2 / Functional, Security
**Platform(s):** All
**Preconditions:** Settings page loaded.
**Test Data:** Toggle matrix (on/off combinations)
**Steps:**

1. Toggle analytics off.
2. Toggle privacy/diagnostic options on/off.
3. Navigate across app and relaunch.
4. Re-open settings and verify states.
   **Expected Result:** Toggles persist and reflect chosen consent; UI indicates effective state clearly.
   **Post-conditions:** Privacy preferences set as configured.
   **Dependencies/Notes:** Ensure defaults are explicit for first-time user.

#### GW-MAN-SET-003

**Module:** Settings
**Title:** Test coin toggle immediate impact and persistence
**Priority/Severity/Type:** P1 / S2 / Functional, Smoke
**Platform(s):** All
**Preconditions:** Coin manager accessible.
**Test Data:** CS-01, CS-02
**Steps:**

1. Disable test coins in settings.
2. Open coin manager and verify DOC/MARTY hidden.
3. Re-enable test coins.
4. Verify DOC/MARTY visible and previous activation state behavior.
5. Restart app and recheck.
   **Expected Result:** Visibility updates immediately; setting persists after restart.
   **Post-conditions:** Test coins enabled for blockchain tests.
   **Dependencies/Notes:** Mandatory for test policy compliance.

#### GW-MAN-SET-004

**Module:** Settings
**Title:** Settings persistence across logout/login/restart
**Priority/Severity/Type:** P1 / S2 / Regression, Recovery
**Platform(s):** All
**Preconditions:** Multiple settings customized.
**Test Data:** Theme, privacy, test coin toggle, balance masking
**Steps:**

1. Configure settings.
2. Log out.
3. Log back in and verify settings.
4. Restart app and verify again.
   **Expected Result:** Persistent settings retain expected values according to account/device scope.
   **Post-conditions:** Stable persisted preferences.
   **Dependencies/Notes:** Record any setting that should intentionally reset.

---

### Market Maker Bot

#### GW-MAN-BOT-001

**Module:** Market Maker Bot
**Title:** Create and start market maker bot with valid config
**Priority/Severity/Type:** P1 / S2 / Functional
**Platform(s):** All
**Preconditions:** Bot feature enabled; funded tradable pair.
**Test Data:** Valid pair, spread, volume, frequency
**Steps:**

1. Open bot module and select `Create Bot`.
2. Enter valid pair and trading parameters.
3. Save and start bot.
4. Verify running status and generated activity entries.
   **Expected Result:** Bot is created and enters running state with valid config reflected in UI.
   **Post-conditions:** One active bot exists.
   **Dependencies/Notes:** Use non-production/test funds only.

#### GW-MAN-BOT-002

**Module:** Market Maker Bot
**Title:** Bot validation for invalid boundaries
**Priority/Severity/Type:** P1 / S2 / Negative, Boundary
**Platform(s):** All
**Preconditions:** Bot creation form open.
**Test Data:** Invalid spread/volume/frequency values
**Steps:**

1. Enter out-of-range spread.
2. Enter zero/negative volume.
3. Enter unsupported pair.
4. Attempt to save.
   **Expected Result:** Invalid configurations are blocked with field-level validation; no bot instance created.
   **Post-conditions:** Bot list unchanged by invalid submission.
   **Dependencies/Notes:** Validate precision/range messages are actionable.

#### GW-MAN-BOT-003

**Module:** Market Maker Bot
**Title:** Edit, stop, restart bot and persistence after relaunch
**Priority/Severity/Type:** P1 / S2 / Functional, Recovery
**Platform(s):** All
**Preconditions:** Active bot exists.
**Test Data:** Existing bot from BOT-001
**Steps:**

1. Edit bot parameters and save.
2. Stop bot and confirm status change.
3. Restart bot.
4. Relaunch app and verify bot config/status.
   **Expected Result:** Edits persist; start/stop actions work; state survives relaunch.
   **Post-conditions:** Bot returns to intended final state.
   **Dependencies/Notes:** Check no duplicate bot instances after restart.

---

### Navigation & Routing

#### GW-MAN-NAV-001

**Module:** Navigation and Routing
**Title:** Main menu route integrity and back navigation
**Priority/Severity/Type:** P1 / S2 / Functional, Regression
**Platform(s):** All
**Preconditions:** Logged in.
**Test Data:** N/A
**Steps:**

1. Navigate via menu to Dashboard, Coin Manager, DEX, Bridge, NFT, Settings, Bot.
2. Use back navigation from each route.
3. Repeat with hardware back (Android) and browser back (Web).
   **Expected Result:** Routes open correct pages; back navigation follows expected stack without exiting unexpectedly or losing critical state.
   **Post-conditions:** User returns safely to start screen.
   **Dependencies/Notes:** Validate route titles and URL segments on web.

#### GW-MAN-NAV-002

**Module:** Navigation and Routing
**Title:** Deep link handling with auth gating
**Priority/Severity/Type:** P1 / S2 / Functional, Security
**Platform(s):** Web, Android, iOS, macOS, Linux, Windows
**Preconditions:** Deep-link format available for coin/tx/order pages.
**Test Data:** Valid and invalid deep-link targets
**Steps:**

1. Open deep link while logged out.
2. Complete login.
3. Verify post-login redirect to intended route.
4. Open malformed or unauthorized deep link.
   **Expected Result:** Auth gating is enforced; valid deep link resolves after login; invalid links show safe fallback/error page.
   **Post-conditions:** App remains on valid route.
   **Dependencies/Notes:** No sensitive content exposed pre-auth.

#### GW-MAN-NAV-003

**Module:** Navigation and Routing
**Title:** Unsaved changes prompt on form exit
**Priority/Severity/Type:** P2 / S3 / Functional, Recovery
**Platform(s):** All
**Preconditions:** Open send/order form with entered but unsent data.
**Test Data:** Partial form input
**Steps:**

1. Enter data into send or DEX form.
2. Attempt to navigate away.
3. Choose `Stay` in confirmation dialog.
4. Navigate away again and choose `Discard`.
   **Expected Result:** Unsaved-changes dialog appears; `Stay` preserves form; `Discard` exits and clears pending input as designed.
   **Post-conditions:** Form state matches user choice.
   **Dependencies/Notes:** Important for interrupted-flow safety.

---

### Responsive Behavior

#### GW-MAN-RESP-001

**Module:** Responsive UI
**Title:** Breakpoint behavior on mobile/tablet/desktop
**Priority/Severity/Type:** P1 / S2 / Compatibility, Usability
**Platform(s):** Web, Android, iOS, desktop
**Preconditions:** App available on devices or emulator/responsive mode.
**Test Data:** Common routes with dense content (DEX, history, settings)
**Steps:**

1. Open app at mobile width.
2. Verify nav style, card/list readability, and action button visibility.
3. Resize to tablet and desktop widths.
4. Re-check layout adaptation.
   **Expected Result:** Layout adapts without overlap/cutoff; primary actions remain visible and reachable at all breakpoints.
   **Post-conditions:** No route-specific layout breakage.
   **Dependencies/Notes:** Include landscape and portrait checks.

#### GW-MAN-RESP-002

**Module:** Responsive UI
**Title:** Orientation/window resize state retention
**Priority/Severity/Type:** P2 / S3 / Recovery, Compatibility
**Platform(s):** Android, iOS, Web, desktop
**Preconditions:** Active workflow in progress (e.g., send form or DEX order draft).
**Test Data:** Partial form state
**Steps:**

1. Enter partial data in a transaction form.
2. Rotate device or resize desktop window significantly.
3. Continue workflow.
   **Expected Result:** UI reflows cleanly; essential in-progress form data remains or follows defined reset behavior with warning.
   **Post-conditions:** Workflow can continue safely.
   **Dependencies/Notes:** Validate no accidental submission on rotate/resize.

---

### Cross-Platform

#### GW-MAN-XPLAT-001

**Module:** Cross-Platform
**Title:** Core-flow parity (create -> fund -> send -> history)
**Priority/Severity/Type:** P0 / S1 / Compatibility, Regression
**Platform(s):** Web, Android, iOS, macOS, Linux, Windows
**Preconditions:** QA build installed on all target platforms.
**Test Data:** WP-01, FD-01, AS-01, AM-03
**Steps:**

1. Create wallet on each platform.
2. Fund DOC using the in-app faucet action on the DOC coin page.
3. Send DOC to valid recipient.
4. Verify transaction appears in history with correct status.
   **Expected Result:** Core user journey succeeds consistently on all platforms with no platform-specific blockers.
   **Post-conditions:** Comparable evidence captured per platform.
   **Dependencies/Notes:** High release-gate coverage.

#### GW-MAN-XPLAT-002

**Module:** Cross-Platform
**Title:** Platform-specific permissions and input behavior
**Priority/Severity/Type:** P1 / S2 / Compatibility, Security
**Platform(s):** All
**Preconditions:** Permission prompts can be reset per platform.
**Test Data:** Clipboard, camera/QR (if used), notification, filesystem export
**Steps:**

1. Trigger permission-required actions (QR scan, export, notifications as applicable).
2. Deny permission and retry action.
3. Grant permission and retry.
4. Validate keyboard shortcuts (desktop) and hardware back gestures (mobile/web).
   **Expected Result:** Permission denial handled gracefully with guidance; granted permission enables action; platform input conventions work.
   **Post-conditions:** Permissions states documented.
   **Dependencies/Notes:** Verify no crash on denied permission paths.

---

### Accessibility

#### GW-MAN-A11Y-001

**Module:** Accessibility
**Title:** Keyboard-only navigation and logical focus order
**Priority/Severity/Type:** P1 / S2 / Accessibility
**Platform(s):** Web, macOS, Linux, Windows, tablet with keyboard
**Preconditions:** Keyboard access enabled.
**Test Data:** Critical routes (auth, send, DEX, settings)
**Steps:**

1. Navigate entire screen using Tab/Shift+Tab only.
2. Activate controls with keyboard keys.
3. Open and close modal dialogs.
4. Verify visible focus indicator is always present.
   **Expected Result:** All interactive elements reachable; focus order logical; no keyboard trap; dialogs trap/release focus correctly.
   **Post-conditions:** Accessibility keyboard path validated.
   **Dependencies/Notes:** WCAG 2.2 AA focus requirements.

#### GW-MAN-A11Y-002

**Module:** Accessibility
**Title:** Screen reader labels, roles, and state announcements
**Priority/Severity/Type:** P1 / S2 / Accessibility, Compatibility
**Platform(s):** iOS (VoiceOver), Android (TalkBack), desktop screen readers, web SR
**Preconditions:** Screen reader enabled.
**Test Data:** Auth, send confirmation, error dialogs
**Steps:**

1. Navigate key screens with screen reader gestures.
2. Read form fields, toggles, and buttons.
3. Trigger validation errors and confirmation dialogs.
4. Verify announcements for status changes (pending/confirmed).
   **Expected Result:** Controls have meaningful labels/roles/states; dynamic changes are announced; no unlabeled actionable controls.
   **Post-conditions:** SR usability evidence captured.
   **Dependencies/Notes:** Prioritize money-movement screens.

#### GW-MAN-A11Y-003

**Module:** Accessibility
**Title:** Color contrast, touch targets, and text scaling
**Priority/Severity/Type:** P1 / S2 / Accessibility
**Platform(s):** All
**Preconditions:** UI theme available; text scaling controls available on OS/app.
**Test Data:** Normal and large text sizes
**Steps:**

1. Check contrast of text/icon/button states in light/dark themes.
2. Verify touch targets for primary actions.
3. Increase text size to large accessibility setting.
4. Re-open core flows and verify readability/no clipping.
   **Expected Result:** Contrast and target sizes meet usability expectations; scaled text remains readable and functional.
   **Post-conditions:** Accessibility visual checks complete.
   **Dependencies/Notes:** Track any clipped critical labels as accessibility defects.

---

### Security & Privacy

#### GW-MAN-SEC-001

**Module:** Security and Privacy
**Title:** Seed phrase handling, reveal controls, and confirmation safeguards
**Priority/Severity/Type:** P0 / S1 / Security
**Platform(s):** All
**Preconditions:** Seed-management screen accessible for test wallet.
**Test Data:** WP-01
**Steps:**

1. Open seed phrase view from secure settings route.
2. Verify re-auth requirement before reveal (if designed).
3. Attempt navigation/screenshot/background while seed visible.
4. Exit screen and return to app.
   **Expected Result:** Seed access is protected; exposure minimized; seed not visible after leaving secure context.
   **Post-conditions:** Seed screen closed; session remains secure.
   **Dependencies/Notes:** Record platform behavior for screenshot masking policy.

#### GW-MAN-SEC-002

**Module:** Security and Privacy
**Title:** Session auto-lock, logout clearing, and app-switcher privacy
**Priority/Severity/Type:** P0 / S1 / Security, Recovery
**Platform(s):** All (app-switcher check on mobile/desktop as applicable)
**Preconditions:** Logged in with funded wallet.
**Test Data:** Auto-lock timeout setting
**Steps:**

1. Set short inactivity timeout.
2. Leave app idle until timeout.
3. Confirm re-auth is required.
4. Log out and relaunch app.
5. Check app-switcher/recents snapshot for sensitive data exposure.
   **Expected Result:** Auto-lock enforces re-auth; logout clears session; sensitive data is not exposed in recents snapshot where policy applies.
   **Post-conditions:** User logged out at end.
   **Dependencies/Notes:** Security-critical release gate.

#### GW-MAN-SEC-003

**Module:** Security and Privacy
**Title:** Clipboard exposure risk for address/seed copy actions
**Priority/Severity/Type:** P0 / S2 / Security, Negative
**Platform(s):** All
**Preconditions:** Clipboard-access actions available.
**Test Data:** Address copy and seed-copy scenario (if allowed)
**Steps:**

1. Copy receive address.
2. Paste into external app and verify exact value.
3. If seed copy is allowed, copy seed and observe warning/guardrails.
4. Wait configured timeout and check clipboard clearing behavior (if implemented).
   **Expected Result:** Clipboard actions are explicit and accurate; warnings appear for sensitive data; timeout-clearing behavior matches policy.
   **Post-conditions:** Clipboard content follows security design.
   **Dependencies/Notes:** Log policy mismatch as security defect.

---

### Error Handling & Recovery

#### GW-MAN-ERR-001

**Module:** Error Handling and Recovery
**Title:** Global network outage messaging and retry pattern
**Priority/Severity/Type:** P0 / S1 / Recovery, Compatibility
**Platform(s):** All
**Preconditions:** App online and synced.
**Test Data:** Simulated offline mode
**Steps:**

1. Disable network while navigating core screens.
2. Trigger refresh/actions on dashboard, send, DEX.
3. Observe global and module-level error messaging.
4. Re-enable network and retry.
   **Expected Result:** Clear outage indicators and retries provided; no crashes; operations recover when network returns.
   **Post-conditions:** App returns to healthy synced state.
   **Dependencies/Notes:** Ensure no stale loading spinner persists indefinitely.

#### GW-MAN-ERR-002

**Module:** Error Handling and Recovery
**Title:** Partial backend failure isolation (one module fails, app survives)
**Priority/Severity/Type:** P1 / S2 / Recovery, Regression
**Platform(s):** All
**Preconditions:** Ability to simulate/observe endpoint-specific failure.
**Test Data:** Failed chart/DEX/faucet response with other services up
**Steps:**

1. Trigger failure in one module endpoint.
2. Navigate to unaffected modules.
3. Confirm unaffected modules remain functional.
4. Retry failed module after recovery.
   **Expected Result:** Failure is contained to impacted module with actionable error; global app remains usable.
   **Post-conditions:** Failed module recovers after service restore.
   **Dependencies/Notes:** Critical resilience behavior.

#### GW-MAN-ERR-003

**Module:** Error Handling and Recovery
**Title:** Stale-state reconciliation after offline transaction lifecycle changes
**Priority/Severity/Type:** P0 / S1 / Recovery, Data Integrity
**Platform(s):** All
**Preconditions:** Pending send/DEX/bridge transaction exists.
**Test Data:** In-flight transaction while app closed/offline
**Steps:**

1. Start transaction and close app before confirmation.
2. Wait until backend confirms/fails transaction.
3. Reopen app and refresh relevant module.
4. Compare local status with authoritative history/explorer.
   **Expected Result:** Local state reconciles to final authoritative status with correct balances/history; no duplicate/ghost entries.
   **Post-conditions:** State integrity verified post-recovery.
   **Dependencies/Notes:** High-priority integrity checkpoint.

---

### Localization & Readability

#### GW-MAN-L10N-001

**Module:** Localization and Readability
**Title:** Translation completeness and fallback behavior
**Priority/Severity/Type:** P2 / S3 / Functional, Compatibility
**Platform(s):** All
**Preconditions:** At least two locales available.
**Test Data:** Locale A and Locale B
**Steps:**

1. Switch app to Locale A and review key routes.
2. Switch app to Locale B and review same routes.
3. Check for untranslated keys/placeholders.
4. Trigger an error dialog and confirmation dialog in each locale.
   **Expected Result:** Strings are translated; fallback language appears only where intended; no raw localization keys visible.
   **Post-conditions:** Locale can be restored to default.
   **Dependencies/Notes:** Include auth/send/DEX/settings dialogs.

#### GW-MAN-L10N-002

**Module:** Localization and Readability
**Title:** Long-string overflow and UI clipping checks
**Priority/Severity/Type:** P2 / S3 / Compatibility, Usability
**Platform(s):** All
**Preconditions:** Locale with longer text enabled; small screen width available.
**Test Data:** Long labels in settings/errors/buttons
**Steps:**

1. Open key screens at narrow width.
2. Verify buttons, headers, and dialog text with long translations.
3. Increase text scaling and re-check.
4. Navigate through send/DEX confirmation screens.
   **Expected Result:** No critical text clipping/overlap; labels remain understandable and actionable.
   **Post-conditions:** Readability status documented.
   **Dependencies/Notes:** Coordinate with A11Y text scaling results.

#### GW-MAN-L10N-003

**Module:** Localization and Readability
**Title:** Locale-specific date/number/currency formatting consistency
**Priority/Severity/Type:** P2 / S3 / Functional
**Platform(s):** All
**Preconditions:** Transaction history present; multiple locales supported.
**Test Data:** Same transaction set viewed under different locales
**Steps:**

1. View transaction history and balances in Locale A.
2. Record date/time and decimal/thousand formatting.
3. Switch to Locale B and compare formats.
4. Verify consistency across dashboard, history, export.
   **Expected Result:** Date/number formatting follows selected locale consistently across modules.
   **Post-conditions:** Format behavior validated.
   **Dependencies/Notes:** Ensure exported history uses documented format rules.

---

### Additional Audited Feature Coverage


#### GW-MAN-FIAT-001
**Module:** Fiat On-ramp  
**Title:** Fiat menu access and connect-wallet gating  
**Priority/Severity/Type:** P0 / S1 / Smoke, Functional  
**Platform(s):** Web, Android, iOS, macOS, Linux, Windows  
**Preconditions:** App installed; test user available.  
**Test Data:** Logged-out and logged-in states  
**Steps:**
1. Open Fiat from main menu while logged out.
2. Verify connect-wallet gating.
3. Connect wallet from Fiat flow.
4. Re-open Fiat form and verify fields are enabled.
**Expected Result:** Logged-out users are gated; logged-in users can access Fiat form and controls.  
**Post-conditions:** Logged-in session active.  
**Dependencies/Notes:** Covers routed `fiat` menu behavior.

#### GW-MAN-FIAT-002
**Module:** Fiat On-ramp  
**Title:** Fiat form validation (currency/asset/amount/payment method)  
**Priority/Severity/Type:** P0 / S1 / Functional, Boundary, Negative  
**Platform(s):** All  
**Preconditions:** Logged in; Fiat page loaded.  
**Test Data:** Min/max fiat amounts, unsupported combinations  
**Steps:**
1. Select fiat currency and crypto asset.
2. Enter below-minimum amount.
3. Enter above-maximum amount.
4. Enter valid amount and switch payment methods.
5. Attempt submit when invalid and when valid.
**Expected Result:** Validation messages are accurate; submit only enabled for valid combinations.  
**Post-conditions:** No invalid order submitted.  
**Dependencies/Notes:** Boundary behavior must match provider constraints.

#### GW-MAN-FIAT-003
**Module:** Fiat On-ramp  
**Title:** Fiat checkout success via provider webview/dialog  
**Priority/Severity/Type:** P0 / S1 / Functional, Recovery  
**Platform(s):** All  
**Preconditions:** Valid fiat form inputs and payment method selected.  
**Test Data:** Valid provider-supported pair and amount  
**Steps:**
1. Submit `Buy Now`.
2. Complete provider checkout flow.
3. Return to app.
4. Verify success status dialog/message.
**Expected Result:** Checkout launches correctly; successful completion state is shown and form status resets appropriately.  
**Post-conditions:** Successful fiat order event recorded.  
**Dependencies/Notes:** Use QA/test provider mode where available.

#### GW-MAN-FIAT-004
**Module:** Fiat On-ramp  
**Title:** Fiat checkout closed/failed/pending handling  
**Priority/Severity/Type:** P0 / S1 / Negative, Recovery  
**Platform(s):** All  
**Preconditions:** Fiat checkout opened.  
**Test Data:** Provider failure or window close before completion  
**Steps:**
1. Submit fiat checkout.
2. Close provider dialog/window before completion.
3. Repeat and trigger provider-side failure.
4. Verify failure messaging and retry capability.
**Expected Result:** Closed/failed states are handled gracefully with user-visible status and no app crash.  
**Post-conditions:** User can retry cleanly.  
**Dependencies/Notes:** Ensure no stale submitting state.

#### GW-MAN-FIAT-005
**Module:** Fiat On-ramp  
**Title:** Fiat form behavior across logout/login transitions  
**Priority/Severity/Type:** P1 / S2 / Regression  
**Platform(s):** All  
**Preconditions:** Fiat page open with prefilled values.  
**Test Data:** Existing logged-in session  
**Steps:**
1. Fill Fiat form partially.
2. Log out from settings while on Fiat module.
3. Verify form resets to logged-out state.
4. Log back in and verify re-initialization.
**Expected Result:** Fiat state resets safely on logout; re-login reloads supported lists and addresses.  
**Post-conditions:** Clean Fiat form state.  
**Dependencies/Notes:** Data integrity and privacy check.

#### GW-MAN-SUP-001
**Module:** Support and Help  
**Title:** Support page content, external link, and missing-coins dialog  
**Priority/Severity/Type:** P2 / S3 / Functional, Compatibility  
**Platform(s):** All  
**Preconditions:** Support page accessible from settings/menu route.  
**Test Data:** N/A  
**Steps:**
1. Open Support page.
2. Verify support content and FAQ items render.
3. Open contact link and confirm target URL opens.
4. Open `My Coins Missing` dialog and verify help link behavior.
**Expected Result:** Support resources are readable and actionable; links/dialog work correctly.  
**Post-conditions:** Returned to app context.  
**Dependencies/Notes:** Browser/app-link handling differs by platform.

#### GW-MAN-FEED-001
**Module:** Feedback  
**Title:** Feedback entry points from settings and floating bug button  
**Priority/Severity/Type:** P2 / S3 / Functional, Compatibility  
**Platform(s):** All  
**Preconditions:** Feedback provider available in current build.  
**Test Data:** Sample feedback text and screenshot attachment  
**Steps:**
1. Open feedback from settings menu (if shown).
2. Open feedback from floating bug button.
3. Submit valid feedback.
4. Repeat and cancel submission.
**Expected Result:** Both entry points open feedback UI; submit/cancel work; success/failure feedback appears.  
**Post-conditions:** No blocking overlays remain.  
**Dependencies/Notes:** If provider unavailable, verify controls are hidden.

#### GW-MAN-SECX-001
**Module:** Security Settings  
**Title:** Private key export flow with show/hide, copy/share/download  
**Priority/Severity/Type:** P0 / S1 / Security  
**Platform(s):** All  
**Preconditions:** Logged in with software wallet and active assets.  
**Test Data:** Wallet password, active assets including blocked/non-blocked assets if applicable  
**Steps:**
1. Open Settings -> Security -> Private Keys.
2. Authenticate with wallet password.
3. Toggle `Show Private Keys`.
4. Execute copy/download/share actions.
5. Toggle blocked assets include/exclude if available.
6. Navigate away and return.
**Expected Result:** Access is password-gated; keys are hidden by default; actions work with security warnings; sensitive state is cleared on navigation.  
**Post-conditions:** Private key screen closed; sensitive data no longer visible.  
**Dependencies/Notes:** Treat any leakage as S1.

#### GW-MAN-SECX-002
**Module:** Security Settings  
**Title:** Seed backup show/confirm/success lifecycle  
**Priority/Severity/Type:** P0 / S1 / Security, Functional  
**Platform(s):** All  
**Preconditions:** Software wallet without confirmed backup marker (or reset profile).  
**Test Data:** Wallet password  
**Steps:**
1. Open seed backup flow.
2. Authenticate and reveal seed.
3. Complete seed confirmation challenge.
4. Verify success state and return to security menu.
**Expected Result:** Seed flow is protected and completes only after confirmation; backup-complete state is reflected in UI indicators.  
**Post-conditions:** Seed flow completed.  
**Dependencies/Notes:** Validate no seed persistence in non-secure views.

#### GW-MAN-SECX-003
**Module:** Security Settings  
**Title:** Unban pubkeys operation (success, empty, error)  
**Priority/Severity/Type:** P1 / S2 / Functional, Recovery  
**Platform(s):** All  
**Preconditions:** Wallet with banned pubkey scenario in test environment.  
**Test Data:** Pubkeys with mixed statuses  
**Steps:**
1. Trigger `Unban Pubkeys`.
2. Observe progress state.
3. Verify results dialog and snackbar messaging.
4. Repeat for no-op/empty and simulated error cases.
**Expected Result:** Operation reports counts and details accurately; errors are surfaced without app instability.  
**Post-conditions:** Pubkey state updated or unchanged with clear reason.  
**Dependencies/Notes:** High value for wallet recovery workflows.

#### GW-MAN-SECX-004
**Module:** Security Settings  
**Title:** Change password flow and re-authentication behavior  
**Priority/Severity/Type:** P0 / S1 / Security, Regression  
**Platform(s):** All  
**Preconditions:** Logged in with known current password.  
**Test Data:** Valid and invalid new password combinations  
**Steps:**
1. Open Change Password.
2. Enter wrong current password and validate rejection.
3. Enter valid current password and valid new password.
4. Log out and log in with old password (expect fail).
5. Log in with new password (expect success).
**Expected Result:** Password update requires valid current password and takes effect immediately after update.  
**Post-conditions:** Session authenticated with new password.  
**Dependencies/Notes:** Include weak-password policy interaction with `SETX-001`.

#### GW-MAN-SETX-001
**Module:** Settings Advanced  
**Title:** Weak-password toggle enforcement in wallet create/import  
**Priority/Severity/Type:** P1 / S2 / Functional, Security  
**Platform(s):** All  
**Preconditions:** Access to settings and wallet create/import dialogs.  
**Test Data:** Weak and strong passwords  
**Steps:**
1. Disable `Allow Weak Password`.
2. Attempt wallet create/import with weak password.
3. Enable `Allow Weak Password`.
4. Retry with weak password.
**Expected Result:** Policy is enforced when disabled and relaxed when enabled, with clear validation messages.  
**Post-conditions:** Password policy state persisted as configured.  
**Dependencies/Notes:** Security policy must be explicit to user.

#### GW-MAN-SETX-002
**Module:** Settings Advanced  
**Title:** Trading bot master toggles and stop-on-disable behavior  
**Priority/Severity/Type:** P1 / S2 / Functional, Recovery  
**Platform(s):** All  
**Preconditions:** Trading bot feature enabled; active bot available.  
**Test Data:** Existing bot config  
**Steps:**
1. Open expert/trading-bot settings.
2. Toggle `Enable Trading Bot` off.
3. Verify active bot stops.
4. Toggle on and verify feature availability returns.
5. Toggle `Save Orders` and relaunch app.
**Expected Result:** Disabling bot stops running bots; save-orders preference persists and affects restart behavior.  
**Post-conditions:** Bot feature state matches configured toggles.  
**Dependencies/Notes:** Coordinate with BOT module tests.

#### GW-MAN-SETX-003
**Module:** Settings Advanced  
**Title:** Export/import maker orders JSON (valid, malformed, empty)  
**Priority/Severity/Type:** P1 / S2 / Functional, Recovery  
**Platform(s):** All  
**Preconditions:** Maker orders exist for export.  
**Test Data:** Valid export file, malformed JSON, empty file  
**Steps:**
1. Export maker orders and verify file created.
2. Import exported file and verify success count.
3. Import malformed JSON and verify error.
4. Import empty/invalid structure and verify error.
**Expected Result:** Valid files import successfully; invalid files fail gracefully with actionable messages.  
**Post-conditions:** Stored maker-order config remains consistent.  
**Dependencies/Notes:** No duplicate/corrupted configs after import.

#### GW-MAN-SETX-004
**Module:** Settings Advanced  
**Title:** Show swap data and export swap data  
**Priority/Severity/Type:** P2 / S3 / Functional  
**Platform(s):** All  
**Preconditions:** Swap history exists in test profile.  
**Test Data:** Existing swaps  
**Steps:**
1. Open `Show Swap Data`.
2. Expand and verify raw swap payload appears.
3. Use copy action.
4. Trigger `Export Swap Data` and verify file output.
**Expected Result:** Swap raw data is viewable/copyable/exportable without UI lockup.  
**Post-conditions:** Exported file available.  
**Dependencies/Notes:** For debugging/support workflows.

#### GW-MAN-SETX-005
**Module:** Settings Advanced  
**Title:** Import swaps from JSON payload  
**Priority/Severity/Type:** P2 / S3 / Functional, Negative  
**Platform(s):** All  
**Preconditions:** Import swaps panel accessible.  
**Test Data:** Valid swaps JSON list, malformed JSON, empty list  
**Steps:**
1. Open `Import Swaps`.
2. Paste valid swaps JSON and import.
3. Repeat with malformed payload.
4. Repeat with empty list.
**Expected Result:** Valid payload imports; malformed/empty payloads display specific errors and do not crash app.  
**Post-conditions:** Import status reflected correctly.  
**Dependencies/Notes:** Useful for support-led recovery.

#### GW-MAN-SETX-006
**Module:** Settings Advanced  
**Title:** Download logs and debug flood logs control  
**Priority/Severity/Type:** P2 / S3 / Functional, Recovery  
**Platform(s):** All (flood logs on debug/profile builds)  
**Preconditions:** Logged-in software wallet; diagnostics available.  
**Test Data:** N/A  
**Steps:**
1. Trigger `Download Logs`.
2. Verify file generation.
3. On debug/profile build, run `Flood Logs`.
4. Download logs again and verify updated content size.
**Expected Result:** Logs are downloadable; debug flood operation completes and app remains responsive.  
**Post-conditions:** Diagnostic artifacts available.  
**Dependencies/Notes:** Do not run flood logs in performance-critical sessions.

#### GW-MAN-SETX-007
**Module:** Settings Advanced  
**Title:** Reset activated coins for selected wallet  
**Priority/Severity/Type:** P2 / S3 / Recovery  
**Platform(s):** All  
**Preconditions:** Multiple wallets with activated assets.  
**Test Data:** Wallet A and Wallet B  
**Steps:**
1. Open reset activated coins tool.
2. Select wallet A and cancel at confirmation.
3. Repeat and confirm reset.
4. Verify only selected wallet activation state resets.
**Expected Result:** Reset operation is wallet-specific, confirmation-protected, and displays completion message.  
**Post-conditions:** Selected wallet coin activations reset; others unchanged.  
**Dependencies/Notes:** Validate no unintended cross-wallet impact.

#### GW-MAN-WALX-001
**Module:** Wallet Dashboard Advanced  
**Title:** Wallet overview cards and privacy toggle behavior  
**Priority/Severity/Type:** P1 / S2 / Functional, Security  
**Platform(s):** All  
**Preconditions:** Wallet with balances and portfolio data loaded.  
**Test Data:** Non-zero and near-zero portfolio values  
**Steps:**
1. Open wallet overview cards.
2. Verify current balance, all-time investment, and all-time profit cards.
3. Toggle privacy icon.
4. Long-press card values to copy (when visible).
**Expected Result:** Overview metrics render consistently; privacy masking applies; copy behavior only available when unmasked.  
**Post-conditions:** Privacy state persists per settings behavior.  
**Dependencies/Notes:** Include mobile carousel and desktop card layouts.

#### GW-MAN-WALX-002
**Module:** Wallet Dashboard Advanced  
**Title:** Assets/Growth/Profit-Loss tab behavior for logged-in vs logged-out  
**Priority/Severity/Type:** P1 / S2 / Functional, Compatibility  
**Platform(s):** All  
**Preconditions:** Ability to test both authenticated and unauthenticated states.  
**Test Data:** Wallet with historical data  
**Steps:**
1. Logged in: switch between Assets, Portfolio Growth, and Profit/Loss tabs.
2. Verify chart rendering and tab changes.
3. Log out and reopen wallet page.
4. Verify logged-out tab set and statistics fallback behavior.
**Expected Result:** Tab availability and content adapt to auth state without errors or stale data.  
**Post-conditions:** UI state stable after auth changes.  
**Dependencies/Notes:** Ensure no ghost data leakage after logout.

#### GW-MAN-WADDR-001
**Module:** Coin Addresses  
**Title:** Multi-address display controls, QR/copy/faucet per address  
**Priority/Severity/Type:** P1 / S2 / Functional, Regression  
**Platform(s):** All  
**Preconditions:** Coin with multiple addresses available.  
**Test Data:** Addresses with zero and non-zero balances; faucet-capable coin  
**Steps:**
1. Open coin addresses section.
2. Toggle hide-zero-balance addresses.
3. Expand/collapse all addresses list.
4. Use copy and QR actions for an address.
5. Trigger faucet on a faucet-supported address.
**Expected Result:** Address list controls work; copy/QR/faucet actions apply to selected address correctly.  
**Post-conditions:** Address state remains synchronized with balance updates.  
**Dependencies/Notes:** Must use in-app faucet action from address card.

#### GW-MAN-WADDR-002
**Module:** Coin Addresses  
**Title:** Create new address flow with confirmation/cancel/error paths  
**Priority/Severity/Type:** P1 / S2 / Functional, Recovery  
**Platform(s):** All (hardware-specific confirmation where applicable)  
**Preconditions:** Coin supports new address generation and creation reasons permit action.  
**Test Data:** Software wallet and hardware wallet profiles  
**Steps:**
1. Press `Create New Address`.
2. For hardware wallet flow, confirm on device when prompted.
3. Validate new address appears in list after completion.
4. Repeat and cancel confirmation.
5. Trigger an error scenario (e.g., disconnected hardware) and observe result.
**Expected Result:** Creation succeeds with confirmation; cancellation/error handled with clear state and messaging.  
**Post-conditions:** Address list accurately reflects only completed creations.  
**Dependencies/Notes:** Includes derivation-path generation reliability.

#### GW-MAN-CTOK-001
**Module:** Custom Token Import  
**Title:** Import custom token happy path  
**Priority/Severity/Type:** P1 / S2 / Functional  
**Platform(s):** All  
**Preconditions:** Supported EVM network active; valid token contract.  
**Test Data:** Valid EVM token contract address  
**Steps:**
1. Open Coins Manager and start custom token import.
2. Select network and enter valid contract address.
3. Fetch token details and review preview.
4. Confirm import.
5. Verify token appears in wallet coin list.
**Expected Result:** Token metadata loads and token is imported/activatable successfully.  
**Post-conditions:** Imported token visible in wallet list/details.  
**Dependencies/Notes:** Use non-production contract in test environment.

#### GW-MAN-CTOK-002
**Module:** Custom Token Import  
**Title:** Custom token fetch failure and not-found handling  
**Priority/Severity/Type:** P1 / S2 / Negative  
**Platform(s):** All  
**Preconditions:** Custom token dialog open.  
**Test Data:** Invalid contract, unsupported network-contract combo  
**Steps:**
1. Enter invalid contract and fetch.
2. Enter valid-format but non-existent contract and fetch.
3. Switch network and retry mismatched contract.
**Expected Result:** Not-found/error states are shown without app crash; import remains blocked.  
**Post-conditions:** No token imported from invalid attempts.  
**Dependencies/Notes:** Error text should be actionable.

#### GW-MAN-CTOK-003
**Module:** Custom Token Import  
**Title:** Back/cancel behavior and state reset across pages  
**Priority/Severity/Type:** P2 / S3 / Recovery  
**Platform(s):** All  
**Preconditions:** Import dialog in result page after a fetch attempt.  
**Test Data:** Fetched token result and failed result  
**Steps:**
1. Navigate to submit/result page.
2. Press back to form page.
3. Verify state reset behavior.
4. Close dialog and reopen import flow.
**Expected Result:** Back/close operations reset state appropriately with no stale data from prior attempts.  
**Post-conditions:** Clean form on reopen.  
**Dependencies/Notes:** Prevents accidental import from stale context.

#### GW-MAN-RWD-001
**Module:** Rewards  
**Title:** KMD rewards info refresh and claim lifecycle  
**Priority/Severity/Type:** P1 / S2 / Functional, Recovery  
**Platform(s):** All  
**Preconditions:** KMD asset present; rewards test profile available.  
**Test Data:** Reward-available and reward-empty profiles  
**Steps:**
1. Open KMD coin details and `Get Rewards`.
2. Verify reward list loads and total reward shown.
3. Claim rewards when available.
4. Verify success screen and updated state.
5. Validate no-reward and claim-failure behavior.
**Expected Result:** Rewards lifecycle is accurate; claim actions reflect real status and errors safely.  
**Post-conditions:** Rewards state synchronized after claim attempt.  
**Dependencies/Notes:** Use test wallet where rewards flow is reproducible.

#### GW-MAN-GATE-001
**Module:** Feature Gating  
**Title:** Trading-disabled mode behavior and tooltips  
**Priority/Severity/Type:** P0 / S1 / Functional, Compatibility  
**Platform(s):** All  
**Preconditions:** Environment with trading disallowed status.  
**Test Data:** Trading disabled state from backend policy  
**Steps:**
1. Open main menu with trading disabled.
2. Hover/tap disabled trading entries.
3. Verify tooltip/messages.
4. Attempt route navigation to restricted features.
**Expected Result:** Trading-restricted features are consistently disabled and clearly explained; route bypass is prevented or safely handled.  
**Post-conditions:** App remains navigable for permitted modules.  
**Dependencies/Notes:** Covers compliance/risk-based gating.

#### GW-MAN-GATE-002
**Module:** Feature Gating  
**Title:** Hardware-wallet restrictions for fiat/trading modules  
**Priority/Severity/Type:** P0 / S1 / Security, Compatibility  
**Platform(s):** Web, macOS, Linux, Windows  
**Preconditions:** Trezor wallet logged in.  
**Test Data:** WP-04  
**Steps:**
1. Log in with hardware wallet.
2. Inspect Fiat/DEX/Bridge/Trading Bot menu items.
3. Attempt to open restricted modules.
4. Verify tooltip/wallet-only messaging.
**Expected Result:** Restricted modules remain unavailable for hardware wallet where policy requires; user messaging is clear.  
**Post-conditions:** Hardware wallet session remains stable.  
**Dependencies/Notes:** Must align with product security policy.

#### GW-MAN-GATE-003
**Module:** Feature Gating  
**Title:** NFT menu disabled state and direct-route safety  
**Priority/Severity/Type:** P1 / S2 / Functional, Security  
**Platform(s):** All  
**Preconditions:** App build where NFT menu is intentionally disabled.  
**Test Data:** N/A  
**Steps:**
1. Inspect NFT menu item state.
2. Verify disabled tooltip.
3. Attempt direct route/deep link to NFT pages.
4. Validate resulting behavior (blocked/fallback/safe rendering).
**Expected Result:** Disabled menu is consistent and direct route attempts do not expose unsafe or broken state.  
**Post-conditions:** Navigation remains stable.  
**Dependencies/Notes:** If NFTs enabled in future build, execute full NFT suite instead.

#### GW-MAN-QLOG-001
**Module:** Quick Login  
**Title:** Remembered wallet prompt and remember-me persistence  
**Priority/Severity/Type:** P1 / S2 / Functional, Regression  
**Platform(s):** All  
**Preconditions:** At least one prior successful login with remember-me enabled.  
**Test Data:** Wallet with remember-me on/off toggles  
**Steps:**
1. Enable remember-me during login.
2. Relaunch app from logged-out state.
3. Verify remembered-wallet prompt appears.
4. Complete quick login and verify target wallet.
5. Disable remember-me and confirm prompt no longer appears.
**Expected Result:** Remembered-wallet prompt appears only when expected and logs into correct wallet; disable path clears behavior.  
**Post-conditions:** Remember-me state matches selection.  
**Dependencies/Notes:** Ensure no wrong-wallet auto-selection.

#### GW-MAN-BREF-001
**Module:** Bitrefill (Conditional)  
**Title:** Bitrefill integration visibility and payment-intent lifecycle  
**Priority/Severity/Type:** P3 / S4 / Compatibility, Functional  
**Platform(s):** All  
**Preconditions:** Coin details page; run once with feature flag off and once with flag on (if available).  
**Test Data:** Supported and unsupported coin scenarios  
**Steps:**
1. Verify Bitrefill button is hidden when integration flag is off.
2. With integration enabled build, verify supported coin visibility.
3. Launch Bitrefill widget and handle payment-intent event.
4. Verify unsupported/suspended/zero-balance disable states and tooltips.
**Expected Result:** Feature flag and eligibility logic are respected; widget launch and event handling work only when eligible.  
**Post-conditions:** No stuck Bitrefill state.  
**Dependencies/Notes:** Optional integration; execute only when enabled in build.

#### GW-MAN-ZHTL-001
**Module:** ZHTLC Configuration (Conditional)  
**Title:** ZHTLC configuration dialog and activation state handling  
**Priority/Severity/Type:** P2 / S3 / Recovery, Functional  
**Platform(s):** All  
**Preconditions:** ZHTLC subclass asset available in test environment.  
**Test Data:** Valid/invalid ZHTLC sync parameters  
**Steps:**
1. Trigger ZHTLC configuration request (auto/manual path).
2. Validate required fields and advanced settings expansion.
3. Save valid configuration and start activation.
4. Repeat and cancel configuration.
5. Trigger logout during pending configuration/activation.
**Expected Result:** Dialog validates inputs, handles cancel/save, and cleans up pending requests safely on auth changes.  
**Post-conditions:** Activation state and dialogs close cleanly.  
**Dependencies/Notes:** Execute only where ZHTLC assets are supported.

#### GW-MAN-WARN-001
**Module:** System Health  
**Title:** Clock warning banner under invalid system-time condition  
**Priority/Severity/Type:** P2 / S3 / Compatibility, Recovery  
**Platform(s):** All  
**Preconditions:** Ability to simulate invalid system-time check with trading enabled.  
**Test Data:** Normal vs invalid local clock state  
**Steps:**
1. Open DEX/Bridge pages with valid clock.
2. Simulate invalid system-time state.
3. Verify warning banner appears.
4. Restore normal clock and verify banner clears.
**Expected Result:** Clock warning appears only when required and does not block core navigation unexpectedly.  
**Post-conditions:** Banner state reconciles after recovery.  
**Dependencies/Notes:** Compliance-critical for transaction timing.


## 6. End-to-End User Journey Suites

### E2E-001: New User Onboarding to First Funded Transaction (DOC/MARTY)

**Mapped Core IDs:** AUTH-001, COIN-001, SEND-001, SEND-003, CDET-002
**Steps:**

1. Create new wallet and complete seed backup confirmation.
2. Enable test coins and activate DOC/MARTY.
3. Copy DOC and MARTY receive addresses.
4. Request faucet funds for both coins using in-app faucet actions on each coin page.
5. Refresh until incoming tx appears and confirms.
6. Send DOC to valid recipient.
7. Verify pending -> confirmed in history and explorer.
   **Expected Outcome:** First-time user can safely create wallet, fund via faucet, and complete first send successfully.

### E2E-002: Restore/Import Wallet to Active Trading

**Mapped Core IDs:** AUTH-003, COIN-001, DEX-001, DEX-002, DEX-005
**Steps:**

1. Import wallet from valid seed.
2. Enable DOC/MARTY and verify balances/history sync.
3. Open DEX and place maker order.
4. Execute taker order from orderbook.
5. Validate order/swap history and export.
   **Expected Outcome:** Returning user can restore wallet and trade without reconfiguration issues.

### E2E-003: Faucet Funding to Withdraw/Send Verification with Recovery

**Mapped Core IDs:** SEND-001, SEND-002, SEND-004, SEND-005, SEND-006, ERR-003
**Steps:**

1. Fund wallet via in-app faucet success path on faucet-coin pages.
2. Trigger cooldown/denied faucet path and verify handling.
3. Attempt invalid address/memo send and validate blocking.
4. Submit valid send.
5. Interrupt network/app during pending state.
6. Reopen and verify reconciliation to final status.
   **Expected Outcome:** Money flow is robust across happy, negative, boundary, and recovery scenarios.

### E2E-004: DEX Order Placement to Completion/Cancel Verification

**Mapped Core IDs:** DEX-001, DEX-003, DEX-004, DEX-006
**Steps:**

1. Place valid maker order.
2. Validate invalid order inputs are blocked.
3. Observe partial fill and cancel remainder.
4. Simulate restart/offline and reconcile order status.
5. Verify balances and locked funds are correct.
   **Expected Outcome:** DEX lifecycle and data integrity remain correct under normal and interrupted conditions.

### E2E-005: Settings Persistence Across Logout/Restart

**Mapped Core IDs:** SET-001, SET-002, SET-003, SET-004, DASH-003
**Steps:**

1. Change theme, locale, privacy toggles, and test coin setting.
2. Log out and log back in.
3. Restart app.
4. Verify all settings and dashboard behavior persist per design.
   **Expected Outcome:** User preferences persist consistently and predictably.

---

## 7. Non-Functional Manual Test Suite

| NF ID   | Category                     | Manual Procedure                                                        | Pass Criteria                                               | Related Core IDs            |
| ------- | ---------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------- | --------------------------- |
| NFM-001 | Performance (Perceived)      | Measure cold launch to interactive dashboard on each platform (3 runs). | Median launch within product target; no freeze/stutter >2s. | XPLAT-001, DASH-002         |
| NFM-002 | Performance (Transaction UX) | Time from send confirm tap to pending state visible.                    | Pending feedback appears quickly and consistently.          | SEND-003                    |
| NFM-003 | Reliability                  | Run 2-hour exploratory session switching modules repeatedly.            | No crash, no unrecoverable stale state.                     | NAV-001, ERR-002            |
| NFM-004 | Recovery                     | Toggle network on/off during active send/DEX/bridge tasks.              | Clear recovery path; final state reconciles correctly.      | SEND-006, DEX-006, BRDG-004 |
| NFM-005 | Accessibility                | Keyboard-only pass across auth/send/settings dialogs.                   | No keyboard traps; logical focus order.                     | A11Y-001                    |
| NFM-006 | Accessibility                | Screen reader pass for critical transaction routes.                     | Controls announced with correct labels/states.              | A11Y-002                    |
| NFM-007 | Accessibility                | Large text + narrow width visual audit.                                 | No critical truncation/overlap blocking actions.            | A11Y-003, L10N-002          |
| NFM-008 | Security/Privacy             | Validate seed/session/clipboard controls across lifecycle.              | Sensitive data protected per policy.                        | SEC-001..003                |
| NFM-009 | Compatibility                | Browser/device matrix sanity run for core journey.                      | No platform-specific blocker in P0 path.                    | XPLAT-001..002              |
| NFM-010 | Compatibility                | Background/foreground and interruption behavior (calls, tab refresh).   | State resumes safely or prompts user clearly.               | RESP-002, ERR-003           |

---

## 8. Regression Pack Definition

| Pack                     | Purpose                                       | Test IDs |
| ------------------------ | --------------------------------------------- | -------- |
| Smoke Pack               | Fast release gate for core viability          | GW-MAN-AUTH-001, GW-MAN-AUTH-002, GW-MAN-COIN-001, GW-MAN-DASH-001, GW-MAN-CDET-001, GW-MAN-SEND-001, GW-MAN-SEND-003, GW-MAN-DEX-001, GW-MAN-BRDG-001, GW-MAN-NFT-001, GW-MAN-SET-003, GW-MAN-NAV-001, GW-MAN-RESP-001, GW-MAN-A11Y-001, GW-MAN-SEC-001, GW-MAN-ERR-001, GW-MAN-FIAT-001, GW-MAN-FIAT-002, GW-MAN-SECX-001, GW-MAN-WADDR-001, GW-MAN-CTOK-001, GW-MAN-GATE-001 |
| Critical Regression Pack | Money movement + auth + data integrity        | GW-MAN-AUTH-001..005, GW-MAN-WAL-001..003, GW-MAN-SEND-001..006, GW-MAN-DEX-001..004 + GW-MAN-DEX-006, GW-MAN-BRDG-001..004, GW-MAN-SEC-001..003, GW-MAN-ERR-001..003, GW-MAN-XPLAT-001, GW-MAN-FIAT-001..004, GW-MAN-SECX-001..004, GW-MAN-CTOK-001..002, GW-MAN-WADDR-001..002, GW-MAN-GATE-001..002, GW-MAN-QLOG-001 |
| Full Regression Pack     | Complete functional + non-functional coverage | GW-MAN-AUTH-001..005, GW-MAN-WAL-001..003, GW-MAN-COIN-001..003, GW-MAN-DASH-001..003, GW-MAN-CDET-001..003, GW-MAN-SEND-001..006, GW-MAN-DEX-001..006, GW-MAN-BRDG-001..004, GW-MAN-NFT-001..003, GW-MAN-SET-001..004, GW-MAN-BOT-001..003, GW-MAN-NAV-001..003, GW-MAN-RESP-001..002, GW-MAN-XPLAT-001..002, GW-MAN-A11Y-001..003, GW-MAN-SEC-001..003, GW-MAN-ERR-001..003, GW-MAN-L10N-001..003, GW-MAN-FIAT-001..005, GW-MAN-SUP-001, GW-MAN-FEED-001, GW-MAN-SECX-001..004, GW-MAN-SETX-001..007, GW-MAN-WALX-001..002, GW-MAN-WADDR-001..002, GW-MAN-CTOK-001..003, GW-MAN-RWD-001, GW-MAN-GATE-001..003, GW-MAN-QLOG-001, GW-MAN-BREF-001, GW-MAN-ZHTL-001, GW-MAN-WARN-001 |

---

## 9. Defect Classification Model

### Severity (S1-S4)

- **S1 Critical:** Security breach, fund loss risk, auth bypass, transaction integrity failure, app crash on core flow.
- **S2 Major:** Core feature unavailable or incorrect (send/DEX/bridge/NFT/settings persistence), strong user impact, no easy workaround.
- **S3 Moderate:** Non-core functional issue, visual/accessibility/localization issue with workaround.
- **S4 Minor:** Cosmetic issue, low-impact copy/layout mismatch with no functional impact.

### Priority (P0-P3)

- **P0 Immediate:** Must fix before release (auth, wallet access, seed/security, faucet/send/DEX/bridge correctness).
- **P1 High:** Should fix in current release cycle (coin visibility, histories, NFT send/history, persistence).
- **P2 Medium:** Fix soon; low immediate release risk (secondary controls, localization polish).
- **P3 Low:** Nice-to-have or cosmetic improvements.

### Reproducibility Labels

- **Always (100%)**
- **Frequent (>50%)**
- **Intermittent (<50%)**
- **Rare/Environment-specific**
- **Unable to Reproduce**

### Required Bug Report Fields

- Defect ID
- Title
- Build version/commit
- Platform + OS + device/browser
- Module/screen
- Preconditions
- Exact steps to reproduce
- Expected result
- Actual result
- Severity + Priority
- Reproducibility label
- Screenshots/video/logs/tx hash/order ID
- Network condition during failure
- Notes on workaround (if any)

---

## 10. Execution Order and Time Estimate

### Recommended Risk-Based Execution Sequence

1. `P0 Security/Auth/Gating`: AUTH, SEC, SECX, GATE, QLOG
2. `P0 Money Movement`: SEND, DEX, BRDG, FIAT
3. `P0/P1 Integrity and Asset Controls`: ERR, CTOK, WADDR, XPLAT-001
4. `P1 Core Usability`: WAL, WALX, COIN, DASH, CDET, NFT, SET, SETX, NAV, SUP/FEED, RWD
5. `P2/P3 Platform and Conditional Integrations`: BOT, RESP, A11Y, L10N, WARN, BREF, ZHTL, XPLAT-002

### Estimated Time Per Module (Manual)

| Module                         | Estimated Time |
| ------------------------------ | -------------- |
| AUTH                           | 2.5h           |
| WAL                            | 1.5h           |
| WALX/WADDR                     | 2.4h           |
| COIN                           | 1.2h           |
| CTOK                           | 1.8h           |
| DASH                           | 1.0h           |
| CDET                           | 1.2h           |
| SEND                           | 3.5h           |
| DEX                            | 4.5h           |
| BRDG                           | 3.0h           |
| FIAT                           | 2.8h           |
| NFT                            | 1.8h           |
| SET                            | 1.8h           |
| SETX                           | 3.2h           |
| BOT                            | 1.8h           |
| NAV                            | 1.2h           |
| SUP/FEED                       | 1.0h           |
| RWD                            | 1.0h           |
| RESP                           | 1.0h           |
| XPLAT                          | 3.0h           |
| A11Y                           | 2.0h           |
| SEC                            | 2.0h           |
| SECX                           | 2.5h           |
| ERR                            | 1.8h           |
| GATE/QLOG/WARN                 | 1.6h           |
| L10N                           | 1.5h           |
| Optional BREF/ZHTL             | 1.8h           |
| **Total excl. optional modules** | **~52.6h**   |
| **Total incl. optional modules** | **~54.4h**   |

### Suggested Parallel Tester Allocation

1. **Tester A (Critical Core):** AUTH, SEC, SECX, SEND, ERR, GATE/QLOG
2. **Tester B (Trading/Payments):** DEX, BRDG, FIAT, BOT, RWD
3. **Tester C (Wallet and Settings UX):** WAL, WALX/WADDR, COIN, CTOK, DASH, CDET, NAV, SET, SETX, SUP/FEED
4. **Tester D (Quality/Cross-platform):** NFT, RESP, XPLAT, A11Y, L10N, WARN, optional BREF/ZHTL

---

## 11. Test Completion Checklist

- [ ] QA build validated on all target platforms.
- [ ] Test coins enabled and DOC/MARTY visibility confirmed.
- [ ] Faucet success/cooldown/error scenarios executed.
- [ ] All `P0` test cases executed.
- [ ] All money-movement integrity checks passed (send/DEX/bridge).
- [ ] Fiat on-ramp validation and provider success/failure handling completed.
- [ ] Custom token import and multi-address create/manage flows completed.
- [ ] Seed/session/privacy tests executed and evidence captured.
- [ ] Advanced security controls completed (seed/private key export/password change/unban pubkeys).
- [ ] Advanced settings operational tooling checks completed (swap data, swap import, logs, reset assets).
- [ ] Recovery tests executed (offline, restart, interrupted flows).
- [ ] Feature-gating and remembered-wallet quick-login behavior validated.
- [ ] Accessibility checks completed (keyboard, SR, contrast, scaling).
- [ ] Localization/readability checks completed.
- [ ] Cross-platform parity run completed.
- [ ] Smoke, Critical, and Full regression pack statuses recorded.
- [ ] Conditional integrations assessed and marked executed/not-applicable (Bitrefill, ZHTLC, NFT-disabled, trading-disabled).
- [ ] All `S1`/`S2` defects triaged with release decision.
- [ ] Final QA sign-off recorded with known-risk list (if any).

---

## 12. Final Coverage Statement

This document provides complete manual QA coverage for the full Gleec Wallet app scope and implemented feature surface, including authentication/lifecycle, wallet/coin management, dashboard, coin details, send/withdraw, DEX, bridge, NFT, settings, market maker bot, routing/navigation, responsive behavior, cross-platform compatibility, accessibility, security/privacy, error recovery, localization/readability, Fiat on-ramp, support/feedback, advanced security/settings operations, custom token import, rewards, feature-gating, quick-login remembered-wallet flow, and conditional Bitrefill/ZHTLC/system-time warning behavior.
All blockchain-dependent scenarios are explicitly designed for testnet/faucet-only execution using DOC/MARTY with in-app faucet action coverage for success, cooldown/denied, and network/error handling.
Assumptions applied: test services are available; at least one memo/tag-required test asset and one NFT test asset exist; DEX/bridge/Fiat provider QA routes are provisioned; and conditional integrations/features are executed when enabled in the build/environment.

---
