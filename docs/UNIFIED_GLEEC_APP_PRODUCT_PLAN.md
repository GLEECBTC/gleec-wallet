# Gleec Unified App: Product Vision & Design Plan

## Combining DEX, CEX, Pay, and Card into One Seamless Experience

**Version:** 1.0 — Draft
**Date:** February 2026
**Reference Benchmark:** Exodus Wallet

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Vision & Strategic Goals](#2-vision--strategic-goals)
3. [Competitive Landscape & Exodus Deep-Dive](#3-competitive-landscape--exodus-deep-dive)
4. [Current State Assessment — Gleec Ecosystem](#4-current-state-assessment--gleec-ecosystem)
5. [Target User Personas](#5-target-user-personas)
6. [Information Architecture & Navigation](#6-information-architecture--navigation)
7. [Screen-by-Screen Design Specifications](#7-screen-by-screen-design-specifications)
8. [Onboarding & Authentication](#8-onboarding--authentication)
9. [Unified Trading Experience (DEX + CEX)](#9-unified-trading-experience-dex--cex)
10. [Banking & Card Integration (Gleec Pay + Card)](#10-banking--card-integration-gleec-pay--card)
11. [Design System & Visual Language](#11-design-system--visual-language)
12. [Technical Architecture](#12-technical-architecture)
13. [Phased Delivery Roadmap](#13-phased-delivery-roadmap)
14. [Success Metrics & KPIs](#14-success-metrics--kpis)
15. [Risks & Mitigations](#15-risks--mitigations)
16. [Appendix](#16-appendix)

---

## 1. Executive Summary

Gleec currently operates several independent products — a self-custody DEX wallet, a centralized exchange (CEX), a crypto-friendly banking service (Gleec Pay), and a Visa debit card (Gleec Card). Each serves a distinct purpose, but the fragmentation forces users to context-switch between apps, manage separate accounts, and mentally reconcile balances across platforms.

This document proposes **Gleec One** — a single, unified application that merges all Gleec services into one cohesive experience modelled after the design excellence of Exodus, enhanced with CEX trading, fiat banking, and card management capabilities that Exodus lacks.

**The core thesis:** Users should never have to leave the app. Whether they want to hold, swap, trade on an order book, spend with a card, or receive a bank transfer — it all happens in one place, with one identity, and one portfolio view.

### Build Strategy: New App, Reuse SDK

Gleec One is a **new Flutter application**, not a refactor of the existing wallet. The Komodo DeFi SDK and its associated packages are imported as dependencies into a fresh project. This gives us:

- A clean architecture from day one with no inherited tech debt in the UI or state layers
- Freedom to adopt the new navigation, design system, and feature structure without migration friction
- Parallel development — the existing wallet stays in maintenance mode while Gleec One is built
- A clear boundary: the SDK handles crypto (swaps, activation, balances), the app handles everything else (CEX, Card, Pay, UX)

The existing wallet codebase serves as a **reference implementation** — its BLoC logic for withdraw flows, swap progress tracking, and market maker bot state machines is ported into the new feature modules, cleaned up along the way.

### Key Outcomes

| Outcome | Description |
|---|---|
| **Single portfolio** | One unified view of all assets across self-custody, exchange, and banking |
| **Frictionless trading** | Swap via DEX or trade on CEX order books from the same screen |
| **Spend anywhere** | Top up and manage the Gleec Visa Card without leaving the wallet |
| **Bank-grade fiat** | IBAN, SEPA, and fiat on/off ramps built in |
| **Exodus-level UX** | Beautiful, intuitive, beginner-friendly — with power-user depth |

---

## 2. Vision & Strategic Goals

### Product Vision

> **Gleec One is the everything-app for crypto.** One download. One login. Hold, trade, swap, spend, and bank — all in a single interface that feels as polished as Exodus and as powerful as a professional trading platform.

### Strategic Goals

#### 2.1 Consolidation over Fragmentation

The current Gleec ecosystem asks users to install and manage multiple apps: the DEX wallet, the CEX web/mobile app, the Gleec Pay portal, and the Card app. Each has its own authentication, its own UI language, and its own mental model. This fragmentation:

- Increases onboarding friction (multiple sign-ups, multiple KYC flows)
- Splits user attention and creates confusion about "where my money is"
- Prevents cross-selling (a DEX user may never discover Gleec Pay)
- Dilutes brand identity across inconsistent interfaces

**Goal:** Reduce the number of Gleec-branded apps from 4+ to 1 unified application.

#### 2.2 Exodus as the UX North Star

Exodus consistently ranks among the top crypto wallets for design and usability. Key attributes to adopt:

| Exodus Attribute | Gleec One Adaptation |
|---|---|
| Zero-friction onboarding (no KYC for basic wallet) | Tiered onboarding: instant wallet, progressive KYC for CEX/Pay |
| Left-sidebar navigation (desktop) / bottom tab bar (mobile) | Adopt identical pattern with expanded sections |
| Portfolio-first home screen | Unified portfolio aggregating all balances |
| Integrated swap with no external redirects | DEX swaps + CEX order routing in one flow |
| Dark/light mode with premium visual polish | Custom design system with Gleec brand identity |
| Hardware wallet support (Trezor/Ledger) | Maintain and extend Trezor support, add Ledger |

#### 2.3 Competitive Differentiation

What makes Gleec One unique versus Exodus, Trust Wallet, or Coin98:

1. **True CEX + DEX convergence.** No other major wallet seamlessly offers both atomic-swap DEX trading AND centralized order-book trading in one interface. Users choose their trade execution venue per transaction.

2. **Built-in banking.** Gleec Pay's IBAN and Gleec Card's Visa debit are first-class citizens, not afterthoughts. Users can receive salary, pay bills, and spend at merchants — all from the same app.

3. **Self-custody by default, custodial by choice.** The wallet is non-custodial at its core. CEX balances and Pay balances are clearly separated and labelled, giving users full transparency about custody.

4. **Institutional-grade market making.** The existing market maker bot becomes an advanced feature for power users and liquidity providers.

#### 2.4 Design Principles

These principles guide every design decision in Gleec One:

| # | Principle | Description |
|---|---|---|
| 1 | **Progressive disclosure** | Show beginners a simple interface; reveal complexity on demand |
| 2 | **Single source of truth** | One portfolio, one balance view, one transaction history |
| 3 | **Custody transparency** | Always make it clear whether funds are self-custody, on exchange, or in Pay |
| 4 | **Speed over ceremony** | Minimize taps/clicks to complete any action |
| 5 | **Trust through clarity** | No jargon, no ambiguity — every state and error is human-readable |
| 6 | **Platform parity** | Desktop, mobile, and web should feel like the same app |
| 7 | **Accessible by default** | WCAG AA compliance, scalable text, screen reader support |

---

## 3. Competitive Landscape & Exodus Deep-Dive

### 3.1 Market Overview

The crypto wallet market in 2025-2026 is converging on a "super-app" model. Key trends:

- **Built-in exchange is table stakes.** Wallets without integrated swaps are losing market share.
- **Embedded wallets grow 3x faster** than traditional external wallets (Dune Wallet Report v2).
- **Fiat on/off ramps are expected,** not optional. MoonPay, Ramp, Banxa integration is standard.
- **Chain abstraction is the future.** Users should not need to think about which chain their assets are on.
- **Account abstraction and passkeys** are replacing seed phrases for mainstream users.
- **KYC is becoming tiered.** Basic wallet = no KYC; trading/banking = progressive verification.

### 3.2 Exodus Wallet — Design Audit

Exodus is the primary design benchmark. Here is a detailed analysis of what they do well and where Gleec One can surpass them.

#### What Exodus Does Exceptionally Well

**1. Portfolio Home Screen**
- Opens directly to a portfolio view showing total balance in fiat
- Pie chart or bar showing asset allocation
- Each asset shows: icon, name, amount, fiat value, 24h change
- Clean hierarchy: total balance (hero) → asset list (scrollable)
- Clicking an asset drills into that asset's detail page

**2. Left Sidebar Navigation (Desktop)**
- Persistent sidebar with icon + label for each section
- Sections: Portfolio, Wallet (Assets), Exchange, Staking, Apps
- Active state is clearly indicated
- Collapses gracefully on narrow screens
- Feels like a native macOS/Windows app

**3. Bottom Tab Bar (Mobile)**
- Standard iOS/Android tab bar pattern: Portfolio, Assets, Exchange, Browser, Settings
- Familiar to every smartphone user
- Badge indicators for pending transactions

**4. Exchange / Swap Flow**
- Two-token selector (From → To) with amount input
- Real-time rate display with estimated output
- One-tap swap execution
- No registration, no external redirect
- Progress tracking with clear status states

**5. Onboarding**
- Download → Open → Wallet is ready (zero config)
- Seed phrase backup is encouraged but not forced upfront
- Password/biometric lock added after first use
- No email, no account creation for basic wallet

**6. Visual Design**
- Dark mode by default with excellent contrast
- Subtle gradients and glassmorphism elements
- Asset icons are high-quality and consistently styled
- Typography is clear with strong hierarchy (Manrope-style sans-serif)
- Animations are smooth and purposeful (not gratuitous)

**7. Send/Receive**
- Clean form: recipient address, amount, fee tier
- QR code scanner and address book
- Transaction preview before broadcast
- Clear success/failure states with explorer links

#### Where Exodus Falls Short (Gleec One Opportunities)

| Exodus Limitation | Gleec One Opportunity |
|---|---|
| No order-book trading | Full CEX order-book with limit/market/stop orders |
| No fiat banking / IBAN | Gleec Pay IBAN integration as first-class feature |
| No debit card | Gleec Card management built into the app |
| Swap-only exchange (no limit orders on DEX) | Maker/taker orders on DEX + CEX limit orders |
| No margin/futures | Gleec CEX futures and margin trading (for verified users) |
| Partial open source | Fully open-source DEX layer (Komodo SDK) |
| No market-making tools | Built-in market maker bot for advanced users |
| Limited staking options | Expandable staking with both on-chain and exchange staking |
| No multi-wallet / account management | Multiple wallet profiles + exchange accounts |
| No 2FA | Full 2FA for exchange/banking features |
| Browser extension only for Web3 | Integrated dApp browser in mobile app |

### 3.3 Other Competitors — Quick Comparison

| Feature | Exodus | Trust Wallet | Coin98 | Gleec One (Proposed) |
|---|---|---|---|---|
| Self-custody wallet | Yes | Yes | Yes | Yes |
| Built-in DEX swaps | Yes | Yes | Yes | Yes |
| CEX order-book trading | No | No | No | **Yes** |
| Fiat banking (IBAN) | No | No | No | **Yes** |
| Debit card | No | Via partner | No | **Yes (Gleec Card)** |
| Market maker bot | No | No | No | **Yes** |
| Hardware wallet support | Trezor + Ledger | Ledger | No | Trezor (+ Ledger planned) |
| NFT support | Yes | Yes | Yes | Yes (planned) |
| Staking | Yes | Yes | Yes | Yes |
| Fiat on-ramp | MoonPay/Ramp | MoonPay | Via partners | Banxa + Gleec Pay |
| Cross-chain bridge | Limited | Via partners | Yes | Yes |
| Futures / Margin | No | No | No | **Yes (via CEX)** |
| Open source | Partial | Yes | Partial | Yes (DEX/SDK layer) |

---

## 4. Current State Assessment — Gleec Ecosystem

### 4.1 Product Inventory

Gleec currently operates the following products independently:

#### Gleec DEX Wallet (This Codebase)
- **Platform:** Flutter — Web, Desktop (Win/macOS/Linux), Mobile (iOS/Android)
- **Architecture:** BLoC pattern, Komodo DeFi SDK, MM2 protocol
- **Core features:** Self-custody wallet, atomic-swap DEX, cross-chain bridge, fiat on-ramp (Banxa), market maker bot, portfolio charts, NFTs (disabled), Trezor support
- **Strengths:** Mature codebase, multi-platform, real atomic swaps, HD wallet support
- **Weaknesses:** Complex onboarding (HD vs Iguana modes exposed to users), dated visual design, no CEX integration, no banking, navigation is functional but not elegant

#### Gleec CEX (exchange.gleec.com)
- **Platform:** Web + mobile app (Google Play)
- **Core features:** Spot trading with order book, ~100 trading pairs, futures/margin, 0.25% flat fees, 2FA, cold storage
- **Strengths:** Professional trading interface, fiat pairs (EUR), high liquidity
- **Weaknesses:** Separate account from wallet, no self-custody option, separate KYC flow

#### Gleec Pay
- **Platform:** Web portal
- **Core features:** Crypto-friendly IBAN, SEPA transfers, worldwide payments, virtual account numbers
- **Strengths:** Licensed by FINTRAC, bridges crypto and traditional banking
- **Weaknesses:** Completely separate from wallet and exchange, limited discoverability

#### Gleec Card
- **Platform:** Physical Visa + virtual card, managed via separate app
- **Core features:** Spend crypto at 50M+ merchants, instant top-up from exchange, plastic and virtual options
- **Strengths:** Real-world spending utility, Visa network reach
- **Weaknesses:** Requires separate app, manual top-up from exchange

### 4.2 Technical Assets — SDK Reuse & Reference Code

Gleec One is a new Flutter project. The SDK packages are imported as dependencies. The app-level code (BLoCs, views, routing) is written fresh but uses the existing codebase as a reference for proven business logic.

#### SDK Packages (Direct Dependencies)

These are imported into the new project's `pubspec.yaml` via path or git reference:

| Package | Role | Import Strategy |
|---|---|---|
| `komodo_defi_sdk` | Core DEX engine — activation, swaps, balances, HD wallets | **Git submodule dependency** |
| `komodo_defi_rpc_methods` | RPC request/response models and methods | **Git submodule dependency** |
| `komodo_defi_types` | Shared type definitions | **Git submodule dependency** |
| `komodo_defi_local_auth` | Local wallet auth, Trezor initialization | **Git submodule dependency** |
| `komodo_cex_market_data` | Price feeds from Binance, CoinGecko, CoinPaprika | **Git submodule dependency** |

#### Reference Code (Port & Rewrite)

The following logic from the existing wallet is valuable but lives in the app layer, not the SDK. It should be studied, then reimplemented cleanly in the new feature modules:

| Existing Code | Value | Action |
|---|---|---|
| `WithdrawFormBloc` (state machine) | Multi-step send flow with validation, fee estimation, confirmation | Port logic into new `SendBloc`, simplify states |
| `TakerBloc` / `MakerFormBloc` | DEX swap execution and order placement | Port into `features/trade/swap/bloc/` |
| `MarketMakerBotBloc` | Automated market-making state machine | Port into `features/trade/bot/bloc/` |
| `BridgeBloc` / `BridgeRepository` | Cross-chain bridge orchestration | Port into `features/trade/bridge/bloc/` |
| `TransactionHistoryBloc` | Transaction fetching and caching | Port into `features/assets/bloc/` |
| `CoinAddressesBloc` | HD wallet address management | Port into `features/assets/bloc/` |
| `TrezorAuthMixin` | Trezor hardware wallet flow | Port into `core/auth/` |
| Platform abstractions | Web vs native platform detection and behavior | Port into `core/platform/` |
| Error message mapping | KDF error → human-readable text (WIP in current codebase) | Port into `core/error/` |
| Translation strings | `assets/translations/en.json` and others | Copy and extend |

#### Not Carried Forward

The following are replaced entirely in the new app:

| Current Code | Reason Not Carried Forward |
|---|---|
| `MainMenuBar` / navigation system | Replaced by new sidebar + tab bar architecture |
| `MainLayoutRouterDelegate` | New routing system (go_router or auto_route) |
| `AuthBloc` (wallet auth) | Rewritten as `WalletAuthBloc` with cleaner states, HD-only default |
| All view widgets (`lib/views/`) | Every screen is redesigned from scratch |
| `komodo_ui_kit` components | New design system built fresh (may share some base components) |
| `app_bloc_root.dart` | New DI and BLoC provider tree |
| Settings architecture | Restructured with grouped categories |

### 4.3 Pain Points to Solve

Based on analysis of the current codebase and user-facing issues:

| # | Pain Point | Impact | Solution in Gleec One |
|---|---|---|---|
| 1 | HD vs Iguana wallet mode exposed to users | Confuses beginners, creates support load | Abstract away — HD by default, Iguana as hidden legacy option |
| 2 | Separate apps for DEX, CEX, Pay, Card | User drop-off, split identity | Single unified app |
| 3 | Complex coin activation flow | Users must manually activate each coin | Auto-activate popular coins, lazy-activate on first receive |
| 4 | No unified portfolio across services | Users cannot see total wealth | Aggregate portfolio across wallet + exchange + Pay |
| 5 | Trading is DEX-only with no limit orders UX | Limits trading appeal | Add CEX order book + improve DEX maker/taker UX |
| 6 | NFT feature disabled | Missing trending feature | Re-enable with polished UI |
| 7 | Fiat on-ramp is external redirect (Banxa) | Breaks immersion | Embed Banxa flow or use Gleec Pay direct fiat |
| 8 | No spending capability | Crypto stays in wallet | Gleec Card integration for real-world spending |
| 9 | Settings page is flat and overwhelming | Hard to find what you need | Grouped settings with search |
| 10 | Error messages are technical | Intimidates non-technical users | Human-readable error system (already in progress in codebase) |

---

## 5. Target User Personas

### Persona 1: "Alex" — The Crypto Curious Beginner

- **Age:** 22-35
- **Experience:** Has used Venmo/PayPal, bought crypto once on Coinbase, wants more control
- **Goals:** Hold Bitcoin and a few altcoins safely, maybe swap sometimes, wants a card to spend crypto
- **Frustrations:** Seed phrases are scary, gas fees are confusing, too many apps to manage
- **Gleec One must:** Be as easy as Exodus to set up, show portfolio in fiat, make swapping one-tap, hide technical complexity

### Persona 2: "Maria" — The Active Trader

- **Age:** 28-45
- **Experience:** Uses Binance or Kraken daily, understands order books, has a hardware wallet
- **Goals:** Trade actively on CEX, use DEX for privacy/low-cap tokens, wants limit/stop orders
- **Frustrations:** Moving funds between exchange and wallet is slow, wants everything in one place
- **Gleec One must:** Offer professional order-book trading, fast deposits/withdrawals to self-custody, advanced charting, and the market maker bot

### Persona 3: "James" — The Crypto-Native Freelancer

- **Age:** 25-40
- **Experience:** Gets paid in crypto, uses DeFi regularly, wants to spend crypto for daily expenses
- **Goals:** Receive USDT/USDC payments, convert to fiat, pay rent, buy groceries with card
- **Frustrations:** Converting crypto to spendable fiat takes 3 apps and 2 days
- **Gleec One must:** Provide IBAN for receiving fiat, instant card top-up from any crypto balance, seamless fiat off-ramp

### Persona 4: "Priya" — The DeFi Power User

- **Age:** 30-50
- **Experience:** Runs a market-making operation, uses multiple DEXs, provides liquidity
- **Goals:** Run automated trading strategies, bridge assets across chains, maximize yield
- **Frustrations:** Fragmented tools, no single dashboard for all positions
- **Gleec One must:** Offer the market maker bot with advanced config, multi-chain bridge, portfolio analytics, and API access

### Persona Priority Matrix

| Feature Area | Alex (Beginner) | Maria (Trader) | James (Freelancer) | Priya (Power User) |
|---|---|---|---|---|
| Simple onboarding | **Critical** | Nice-to-have | Important | Nice-to-have |
| Portfolio view | **Critical** | **Critical** | **Critical** | **Critical** |
| DEX swaps | Important | **Critical** | Important | **Critical** |
| CEX order book | Not needed | **Critical** | Nice-to-have | Important |
| Gleec Card | Important | Nice-to-have | **Critical** | Nice-to-have |
| Gleec Pay / IBAN | Nice-to-have | Nice-to-have | **Critical** | Nice-to-have |
| Market maker bot | Not needed | Important | Not needed | **Critical** |
| Hardware wallet | Not needed | **Critical** | Nice-to-have | **Critical** |
| NFTs | Nice-to-have | Nice-to-have | Not needed | Important |
| Bridge | Not needed | Important | Nice-to-have | **Critical** |

---

## 6. Information Architecture & Navigation

### 6.1 Navigation Philosophy

Following Exodus's proven pattern, adapted for Gleec One's expanded feature set:

- **Desktop:** Persistent left sidebar with icon + label, collapsible to icons-only
- **Mobile:** Bottom tab bar (5 primary tabs) with a "More" overflow for secondary features
- **Web:** Same as desktop, responsive to mobile layout at breakpoints

### 6.2 Primary Navigation Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    GLEEC ONE — NAVIGATION                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  PRIMARY TABS (always visible)                               │
│  ─────────────────────────────                               │
│  1. 🏠 Home / Portfolio                                      │
│  2. 💰 Assets                                                │
│  3. 🔄 Trade                                                 │
│  4. 💳 Card & Pay                                            │
│  5. ⚙️ Settings & More                                       │
│                                                              │
│  DESKTOP SIDEBAR (expanded)                                  │
│  ──────────────────────────                                  │
│  1. Portfolio          (home/dashboard)                      │
│  2. Assets             (coin list & management)              │
│  3. Trade                                                    │
│     ├─ Swap            (quick DEX swaps)                     │
│     ├─ Exchange         (CEX order book)                     │
│     ├─ Bridge           (cross-chain)                        │
│     └─ Bot              (market maker)                       │
│  4. Card & Pay                                               │
│     ├─ Card             (Gleec Card management)              │
│     └─ Banking          (Gleec Pay / IBAN)                   │
│  5. Earn               (staking & rewards)                   │
│  6. NFTs               (gallery & marketplace)               │
│  ──────────────────────────                                  │
│  7. Settings                                                 │
│  8. Support                                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 6.3 Screen Hierarchy Map

```
Root
├── Onboarding
│   ├── Welcome / Value Prop
│   ├── Create Wallet (seed generation)
│   ├── Import Wallet (seed / file / hardware)
│   ├── Set Password / Biometrics
│   └── KYC Flow (optional, for CEX/Pay features)
│
├── Portfolio (Home)
│   ├── Total Balance (hero)
│   ├── Balance Breakdown (Wallet / Exchange / Pay)
│   ├── Asset Allocation Chart
│   ├── Top Movers / Watchlist
│   ├── Recent Transactions (unified)
│   └── Quick Actions (Send / Receive / Swap / Buy)
│
├── Assets
│   ├── Asset List (search, filter, sort)
│   │   └── Asset Detail
│   │       ├── Balance & Price Chart
│   │       ├── Send
│   │       ├── Receive (address + QR)
│   │       ├── Swap (pre-filled)
│   │       ├── Transaction History
│   │       └── Manage Addresses (HD)
│   ├── Add/Remove Assets
│   └── Hidden Small Balances Toggle
│
├── Trade
│   ├── Swap (DEX)
│   │   ├── Simple Swap (From → To)
│   │   ├── Advanced (maker/taker orders)
│   │   ├── Active Swaps
│   │   └── Swap History
│   ├── Exchange (CEX)
│   │   ├── Trading Pair Selector
│   │   ├── Order Book
│   │   ├── Price Chart (TradingView-style)
│   │   ├── Order Entry (Market / Limit / Stop)
│   │   ├── Open Orders
│   │   ├── Order History
│   │   └── Deposit/Withdraw to Self-Custody
│   ├── Bridge
│   │   ├── Bridge Swap Form
│   │   └── Bridge History
│   └── Market Maker Bot
│       ├── Bot Dashboard (status, P&L)
│       ├── Configure Pairs
│       └── Bot History
│
├── Card & Pay
│   ├── Card Overview
│   │   ├── Card Balance
│   │   ├── Top Up (from wallet or exchange)
│   │   ├── Transaction History
│   │   ├── Card Settings (freeze, limits)
│   │   └── Order Physical Card
│   ├── Banking (Gleec Pay)
│   │   ├── IBAN Details
│   │   ├── Send Bank Transfer
│   │   ├── Receive (share IBAN)
│   │   ├── Transaction History
│   │   └── Account Settings
│   └── Buy Crypto (Fiat On-Ramp)
│       ├── Amount & Currency Selection
│       ├── Payment Method
│       └── Order Tracking
│
├── Earn
│   ├── Staking Overview
│   ├── Available Staking Options
│   ├── Active Stakes
│   └── Rewards History
│
├── NFTs
│   ├── Gallery (by chain)
│   ├── NFT Detail
│   ├── Send NFT
│   └── NFT Transaction History
│
└── Settings
    ├── Profile & Identity
    │   ├── KYC Status
    │   ├── Account Verification
    │   └── Connected Devices
    ├── Security
    │   ├── Password / Biometrics
    │   ├── 2FA (for CEX/Pay)
    │   ├── Backup Seed Phrase
    │   ├── Hardware Wallet
    │   └── Session Management
    ├── Preferences
    │   ├── Theme (Light / Dark / System)
    │   ├── Currency (fiat display)
    │   ├── Language
    │   ├── Notifications
    │   └── Privacy (hide balances)
    ├── Advanced
    │   ├── Network Settings
    │   ├── Export Data (tax reports)
    │   ├── Diagnostic Logs
    │   └── Developer Options
    └── About & Legal
        ├── Version Info
        ├── Licenses
        └── Terms / Privacy Policy
```

### 6.4 Mobile Tab Bar Mapping

The 5-tab mobile layout maps as follows:

| Tab | Icon | Label | Contains |
|---|---|---|---|
| 1 | Home icon | Portfolio | Dashboard, balances, quick actions |
| 2 | Wallet icon | Assets | Asset list, coin details, send/receive |
| 3 | Swap arrows icon | Trade | Swap, Exchange, Bridge (sub-tabs) |
| 4 | Card icon | Card | Gleec Card, Pay, Buy Crypto |
| 5 | Gear icon | More | Settings, Earn, NFTs, Support, Bot |

### 6.5 Desktop Sidebar Behavior

| State | Behavior |
|---|---|
| **Expanded (default)** | Icon + label, ~220px wide |
| **Collapsed** | Icon only, ~64px wide, labels as tooltips |
| **Hover on collapsed** | Temporarily expand that item's label |
| **Active indicator** | Highlighted background + left accent bar |
| **Sub-navigation** | Trade and Card sections expand/collapse inline |
| **User avatar/name** | Bottom of sidebar with wallet name and quick-switch |

---

## 7. Screen-by-Screen Design Specifications

### 7.1 Portfolio (Home) Screen

This is the first screen users see after login. It must immediately answer: "How much is my crypto worth?"

#### Layout (Desktop)

```
┌──────────┬───────────────────────────────────────────────────┐
│          │  PORTFOLIO                                    🔔  │
│  Sidebar │  ┌─────────────────────────────────────────────┐  │
│          │  │         $12,847.32 USD                      │  │
│          │  │  ▲ +2.4% today    Wallet | Exchange | Pay   │  │
│          │  └─────────────────────────────────────────────┘  │
│          │                                                    │
│          │  ┌──────────────────┐  ┌────────────────────────┐ │
│          │  │  Asset Allocation │  │  Quick Actions         │ │
│          │  │  [Donut Chart]    │  │  [Send] [Receive]      │ │
│          │  │                   │  │  [Swap] [Buy]          │ │
│          │  └──────────────────┘  └────────────────────────┘ │
│          │                                                    │
│          │  RECENT ACTIVITY                      [View All]  │
│          │  ┌─────────────────────────────────────────────┐  │
│          │  │  ↑ Sent 0.05 BTC          -$2,341    2m ago │  │
│          │  │  ↓ Received 500 USDT      +$500      1h ago │  │
│          │  │  ⇄ Swapped ETH → USDT     ...       3h ago  │  │
│          │  │  💳 Card purchase           -$42     today   │  │
│          │  └─────────────────────────────────────────────┘  │
│          │                                                    │
│          │  TOP ASSETS                                        │
│          │  ┌─────────────────────────────────────────────┐  │
│          │  │  BTC    0.15      $7,023    ▲ 3.1%          │  │
│          │  │  ETH    2.4       $4,102    ▼ 1.2%          │  │
│          │  │  USDT   1,722     $1,722    — 0.0%          │  │
│          │  └─────────────────────────────────────────────┘  │
└──────────┴───────────────────────────────────────────────────┘
```

#### Key Design Decisions

1. **Balance breakdown tabs:** "Wallet | Exchange | Pay" lets users see where their funds are. Default view shows total across all. Each tab filters the asset list to that venue.

2. **Quick Actions:** Four prominent buttons for the most common tasks. Each is context-aware — "Buy" only shows if KYC is complete for fiat on-ramp.

3. **Unified activity feed:** Merges transactions from wallet sends, DEX swaps, CEX trades, card purchases, and Pay transfers into one chronological list with clear iconography distinguishing each type.

4. **Asset allocation donut chart:** Mirrors Exodus's visual representation. Interactive — tapping a segment highlights that asset.

5. **Portfolio value chart:** Accessible via tap/swipe on the hero balance area. Shows 1D/1W/1M/3M/1Y/ALL time periods identical to Exodus.

### 7.2 Assets Screen

#### Layout Principles

- **Search bar at top** with instant filtering
- **Filter chips:** All, Crypto, Tokens, Stablecoins, NFTs
- **Sort options:** By value (default), alphabetical, 24h change, custom
- **Each row:** Coin icon, name/ticker, balance (crypto), balance (fiat), 24h sparkline, 24h change %
- **Zero-balance assets:** Hidden by default, toggle to show
- **Add Asset button:** Prominent at top or as FAB on mobile

#### Asset Detail Page

When tapping an asset, the detail page shows:

```
┌─────────────────────────────────────────────────┐
│  ← Back                                    ⋮    │
│                                                  │
│       [BTC Icon]  Bitcoin                        │
│       0.15 BTC ≈ $7,023.00                      │
│       ▲ 3.1% today                              │
│                                                  │
│  ┌─────────────────────────────────────────┐    │
│  │         [Price Chart]                    │    │
│  │    1D  1W  1M  3M  1Y  ALL              │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  [Send]  [Receive]  [Swap]  [Trade]  [Stake]    │
│                                                  │
│  BALANCE DETAILS                                 │
│  ┌─────────────────────────────────────────┐    │
│  │  Wallet (self-custody)     0.10 BTC     │    │
│  │  Exchange                  0.04 BTC     │    │
│  │  Gleec Card                0.01 BTC     │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  TRANSACTIONS                        [View All] │
│  ┌─────────────────────────────────────────┐    │
│  │  ↑ Sent 0.05 BTC     Feb 26    -$2,341 │    │
│  │  ↓ Received 0.20 BTC Feb 24    +$9,100 │    │
│  │  ⇄ Swap to ETH       Feb 22    0.03BTC │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  ADDRESSES (HD Wallet)                           │
│  ┌─────────────────────────────────────────┐    │
│  │  m/44'/0'/0'/0/0  bc1q...xyz   0.10 BTC│    │
│  │  + Generate New Address                  │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

#### Key Enhancements over Current Gleec Wallet

1. **Balance split by venue** — shows where the asset is held (wallet vs exchange vs card)
2. **"Trade" action** — opens CEX trading pair for this asset (in addition to "Swap" for DEX)
3. **"Stake" action** — shows if staking is available for this asset
4. **Price chart** — interactive with time period selector (mirrors Exodus)
5. **Unified transaction history** — all transactions for this asset regardless of venue

### 7.3 Trade Screen — Swap (DEX)

The swap interface follows Exodus's proven design but adds maker/taker order support.

#### Simple Swap Mode (Default)

```
┌─────────────────────────────────────────────────┐
│  SWAP                           [Simple|Advanced]│
│                                                  │
│  From                                            │
│  ┌─────────────────────────────────────────┐    │
│  │  [BTC ▼]              0.05             │    │
│  │  Bitcoin               ≈ $2,341         │    │
│  │                        Balance: 0.15    │    │
│  │                              [MAX]      │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│                    [⇅ Switch]                    │
│                                                  │
│  To                                              │
│  ┌─────────────────────────────────────────┐    │
│  │  [ETH ▼]              ~0.82            │    │
│  │  Ethereum              ≈ $2,318         │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  Rate: 1 BTC = 16.4 ETH                        │
│  Route: DEX Atomic Swap                          │
│  Est. time: ~15 min                              │
│  Network fee: ~$3.20                             │
│                                                  │
│       ┌──────────────────────────────┐          │
│       │        SWAP NOW              │          │
│       └──────────────────────────────┘          │
│                                                  │
│  ─── or trade on Exchange ───                    │
│  [Open BTC/ETH on Exchange →]                    │
│                                                  │
└─────────────────────────────────────────────────┘
```

#### Advanced Swap Mode

Shows the existing maker/taker order functionality but with a cleaner interface:
- Order book visualization
- Place maker order with spread setting
- Active orders list
- History with filtering and export

#### Cross-Sell to CEX

The "or trade on Exchange" link at the bottom is a key design decision. It introduces CEX trading to DEX users organically, without forcing it. If the CEX offers better rates or faster execution for that pair, the app can show a subtle indicator.

### 7.4 Trade Screen — Exchange (CEX)

A professional trading interface for users who want order-book trading.

#### Layout (Desktop)

```
┌──────────┬─────────────────────────────────────────────────┐
│          │  EXCHANGE        [BTC/USDT ▼]    📊 Chart  📋  │
│          │                                                  │
│  Sidebar │  ┌──────────────────────┬──────────────────────┐│
│          │  │                      │   ORDER BOOK         ││
│          │  │   PRICE CHART        │   ──────────         ││
│          │  │   (TradingView)      │   Ask  47,234  0.12  ││
│          │  │                      │   Ask  47,230  0.45  ││
│          │  │                      │   ─── Spread ───     ││
│          │  │                      │   Bid  47,225  0.30  ││
│          │  │                      │   Bid  47,220  1.20  ││
│          │  └──────────────────────┴──────────────────────┘│
│          │                                                  │
│          │  ┌──────────────────────┬──────────────────────┐│
│          │  │  BUY BTC             │   SELL BTC           ││
│          │  │  [Market|Limit|Stop] │   [Market|Limit|Stop]││
│          │  │  Price: [47,225    ] │   Price: [47,234   ] ││
│          │  │  Amount: [         ] │   Amount: [         ]││
│          │  │  Total:  $0.00       │   Total:  $0.00      ││
│          │  │  [25%][50%][75%][MAX]│   [25%][50%][75%][MAX││
│          │  │  ┌──────────────┐   │   ┌──────────────┐   ││
│          │  │  │  BUY BTC     │   │   │  SELL BTC    │   ││
│          │  │  └──────────────┘   │   └──────────────┘   ││
│          │  │  CEX Bal: 0.04 BTC  │   CEX Bal: 1,722 USDT││
│          │  │  [Deposit from       │   [Deposit from      ││
│          │  │   Wallet →]          │    Wallet →]         ││
│          │  └──────────────────────┴──────────────────────┘│
│          │                                                  │
│          │  OPEN ORDERS (3)                                 │
│          │  ┌──────────────────────────────────────────────┐│
│          │  │  Limit Buy  0.1 BTC @ 46,500   [Cancel]     ││
│          │  │  Limit Sell 0.05 BTC @ 48,000  [Cancel]     ││
│          │  └──────────────────────────────────────────────┘│
└──────────┴─────────────────────────────────────────────────┘
```

#### Key Design Decisions

1. **Deposit from Wallet prompt:** Below each order form, show the self-custody wallet balance with a one-tap deposit option. This bridges the gap between DEX wallet and CEX without forcing users to navigate away.

2. **Order types:** Market, Limit, and Stop orders. Futures/Margin available as a toggle for verified users (progressive disclosure).

3. **Trading pair selector:** Searchable dropdown with favorites/recent pairs. Shows both price and 24h volume.

4. **Mobile adaptation:** On mobile, the exchange screen uses a vertical stack: Chart (collapsible) → Order entry (tabbed Buy/Sell) → Open orders. Order book available as a slide-up sheet.

### 7.5 Card & Pay Screen

#### Card Tab

```
┌─────────────────────────────────────────────────┐
│  GLEEC CARD                                      │
│                                                  │
│  ┌─────────────────────────────────────────┐    │
│  │  ╔═══════════════════════════════════╗  │    │
│  │  ║  GLEEC                    VISA    ║  │    │
│  │  ║                                   ║  │    │
│  │  ║  •••• •••• •••• 4827             ║  │    │
│  │  ║  JAMES WILSON     09/28          ║  │    │
│  │  ╚═══════════════════════════════════╝  │    │
│  │                                         │    │
│  │  Balance: $1,247.00                     │    │
│  │                                         │    │
│  │  [Top Up]  [Freeze]  [Details]          │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  SPENDING THIS MONTH                             │
│  ┌─────────────────────────────────────────┐    │
│  │  $847 of $2,000 limit                   │    │
│  │  ████████████░░░░░░░  42%               │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  RECENT TRANSACTIONS                             │
│  ┌─────────────────────────────────────────┐    │
│  │  🛒 Amazon            -$42.00   Today   │    │
│  │  ☕ Starbucks          -$5.50    Today   │    │
│  │  ⬆ Top-up from BTC   +$200    Yesterday │    │
│  └─────────────────────────────────────────┘    │
│                                                  │
│  [Order Physical Card]                           │
│  [Manage Virtual Cards]                          │
└─────────────────────────────────────────────────┘
```

#### Top-Up Flow

The card top-up flow is critical for "James" (the freelancer persona). It must be fast:

1. Tap "Top Up"
2. Choose source: Wallet balance, Exchange balance, or Bank (Gleec Pay)
3. Choose asset (if crypto) — shows current rate to card currency
4. Enter amount
5. Confirm — funds appear on card instantly (or within seconds)

#### Banking Tab (Gleec Pay)

```
┌─────────────────────────────────────────────────┐
│  GLEEC PAY                                       │
│                                                  │
│  Account Balance: €3,450.00                      │
│                                                  │
│  IBAN: DE89 3704 0044 0532 0130 00               │
│  [Copy]  [Share]  [QR Code]                      │
│                                                  │
│  [Send Transfer]  [Convert to Crypto]            │
│                                                  │
│  RECENT TRANSFERS                                │
│  ┌─────────────────────────────────────────┐    │
│  │  ↓ Salary deposit     +€2,500  Feb 25  │    │
│  │  ↑ Rent payment       -€800    Feb 1   │    │
│  │  ⇄ Convert to BTC     -€500   Jan 28   │    │
│  └─────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

---

## 8. Onboarding & Authentication

### 8.1 Design Philosophy

Exodus's biggest UX win is frictionless onboarding: download, open, wallet is ready. No email, no account, no KYC for the basic wallet. Gleec One must match this for the self-custody wallet layer while progressively introducing KYC for CEX and Pay features.

### 8.2 Tiered Identity Model

```
TIER 0 — Anonymous Wallet (No KYC)
├── Self-custody wallet (HD, BIP39)
├── DEX swaps (atomic swaps, no custodial risk)
├── Bridge transfers
├── NFT management
├── Market maker bot (on DEX)
└── Full portfolio tracking

TIER 1 — Basic Verification (Email + Phone)
├── Everything in Tier 0
├── CEX spot trading (limited volume)
├── Fiat on-ramp via Banxa (limited)
└── Push notifications and account recovery

TIER 2 — Full KYC (ID Verification)
├── Everything in Tier 1
├── CEX trading (unlimited)
├── Futures and margin trading
├── Gleec Pay (IBAN account)
├── Gleec Card (virtual + physical)
├── Higher fiat on-ramp limits
└── Fiat off-ramp (sell crypto to bank)
```

### 8.3 First-Time Onboarding Flow

```
Step 1: Welcome Screen
  "Welcome to Gleec One"
  "Your wallet, exchange, and card — all in one."
  [Create New Wallet]  [Import Existing Wallet]

     ↓ Create New Wallet

Step 2: Wallet Creation (< 5 seconds)
  - Generate BIP39 mnemonic in background
  - Show animated "Creating your wallet..." (1-2s for perceived quality)
  - HD wallet by default (never expose HD vs Iguana choice to users)

     ↓

Step 3: Secure Your Wallet
  - Set password (required) OR set up biometrics (mobile)
  - Password strength meter with real-time feedback
  - Minimum 8 characters, no "weak password" toggle in production

     ↓

Step 4: Backup Seed Phrase (Strongly Encouraged, Not Forced)
  - "Your wallet is ready! Before you start, let's secure your backup."
  - [Back Up Now] (recommended, highlighted)
  - [Skip for Now] (subtle, with a warning badge that persists)
  - If "Back Up Now": show 12/24 words → confirm by selecting in order → done
  - If "Skip": persistent reminder in Settings and on Portfolio screen

     ↓

Step 5: Portfolio Screen (Home)
  - Wallet is ready with $0 balance
  - Prominent "Deposit" and "Buy Crypto" CTAs
  - Optional: show popular coins to activate (BTC, ETH, USDT pre-selected)

     ↓ (Optional, triggered by accessing CEX or Pay features)

Step 6: Progressive KYC
  - When user first taps "Exchange" or "Card & Pay":
    "To trade on the exchange / use banking features, we need to verify your identity."
    [Verify Now] — starts in-app KYC flow
    [Not Now] — returns to wallet features
  - KYC flow: Email → Phone → ID upload → Selfie → Processing (async)
  - Status shown in Settings: "Verification: Pending / Approved / Action Needed"
```

### 8.4 Import Wallet Flow

```
Import Options:
├── From Seed Phrase
│   ├── 12-word or 24-word input
│   ├── BIP39 validation in real-time
│   ├── Set password
│   └── Auto-detect supported coins and balances
│
├── From File (Legacy Gleec Wallet backup)
│   ├── File picker
│   ├── Decrypt with password
│   └── Migrate to new format
│
├── From Hardware Wallet
│   ├── Connect Trezor (USB or Bluetooth)
│   ├── Device confirmation
│   ├── Read accounts from device
│   └── Hardware wallet mode (restricted: no CEX, no Card — these require custodial actions)
│
└── From QR Code (Device Sync)
    ├── Scan QR from another Gleec One instance
    ├── Encrypted sync of wallet config (NOT seed phrase)
    └── Cross-device portfolio sync
```

### 8.5 Login Flow

```
Returning User:
├── Password Entry
│   ├── Quick login: auto-submit when paste detected (password manager)
│   ├── Biometric unlock (Face ID / Touch ID / Fingerprint)
│   └── "Forgot password?" → re-import from seed phrase
│
├── Multi-Wallet Support
│   ├── If multiple wallets exist, show wallet selector first
│   ├── Last-used wallet is pre-selected
│   ├── "Remember wallet" checkbox to skip selector
│   └── Wallet avatar/icon for visual differentiation
│
└── Session Management
    ├── Auto-lock after configurable timeout (5m / 15m / 30m / 1h / Never)
    ├── Lock on app background (mobile, optional)
    └── CEX/Pay session may have separate timeout (stricter)
```

### 8.6 Key UX Decisions vs. Current Gleec Wallet

| Current Behavior | Gleec One Behavior | Rationale |
|---|---|---|
| Exposes HD vs Iguana wallet choice | HD only, Iguana hidden as legacy import | Beginners don't understand derivation paths |
| Allows weak passwords (dev toggle) | Enforce strong passwords in production | Security non-negotiable for financial app |
| Coin activation is manual per-coin | Top coins pre-activated, others lazy-activate | Reduce friction for new users |
| Seed backup is a separate settings action | Prompted during onboarding, persistent reminder | Critical security UX from Exodus |
| No biometric option | Biometric primary on mobile | Standard for modern financial apps |
| No progressive KYC | Tiered KYC (anonymous → basic → full) | Unlocks CEX/Pay without blocking wallet use |

---

## 9. Unified Trading Experience (DEX + CEX)

### 9.1 The Core Innovation

No major wallet app today seamlessly combines DEX and CEX trading in one interface. This is Gleec One's flagship differentiator. The design philosophy:

> **The user chooses WHAT to trade. The app suggests WHERE to trade it.**

### 9.2 Trade Routing Architecture

When a user initiates a trade, the app evaluates both DEX and CEX execution options:

```
User wants to swap 1 BTC → ETH

┌──────────────────────────────────────────────────┐
│  TRADE OPTIONS                                    │
│                                                   │
│  ┌─────────────────────────────────────────────┐ │
│  │  ⚡ EXCHANGE (CEX)               BEST RATE  │ │
│  │  Rate: 1 BTC = 16.42 ETH                    │ │
│  │  Fee: 0.25% ($5.85)                          │ │
│  │  Speed: Instant                               │ │
│  │  Custody: Exchange holds funds during trade   │ │
│  │  [Trade on Exchange →]                        │ │
│  └─────────────────────────────────────────────┘ │
│                                                   │
│  ┌─────────────────────────────────────────────┐ │
│  │  🔒 DEX (Atomic Swap)            NON-CUSTODIAL│
│  │  Rate: 1 BTC = 16.38 ETH                    │ │
│  │  Fee: Network fees only (~$3.20)             │ │
│  │  Speed: ~15 minutes                           │ │
│  │  Custody: Your keys, your crypto             │ │
│  │  [Swap on DEX →]                              │ │
│  └─────────────────────────────────────────────┘ │
│                                                   │
│  ℹ️ DEX swaps are non-custodial but slower.       │
│     Exchange trades are instant but custodial.    │
└──────────────────────────────────────────────────┘
```

### 9.3 Smart Defaults

The app uses smart defaults to minimize decision fatigue:

| User Scenario | Default Route | Reason |
|---|---|---|
| Small swap (< $100) | DEX | Fees are lower, no KYC needed |
| Large trade (> $1,000) | CEX | Better liquidity, instant execution |
| Pair available on both | Show comparison | Let user choose with clear trade-offs |
| Pair only on DEX | DEX (auto) | No choice needed, show explanation |
| Pair only on CEX | CEX (auto) | No choice needed, show explanation |
| User has no CEX account | DEX (with "Unlock faster trades" prompt) | Don't block, just upsell |
| User has funds on CEX only | CEX (with "Or deposit to wallet for DEX") | Meet user where their funds are |

### 9.4 Unified Order Management

All orders — DEX maker/taker and CEX limit/market/stop — appear in a single "Orders" view:

```
MY ORDERS                                    [Filter ▼]

Active (3)
┌────────────────────────────────────────────────────┐
│  🔒 DEX Maker   Sell 0.5 ETH @ 0.034 BTC   Active │
│  ⚡ CEX Limit   Buy 1000 USDT @ 0.99        Open   │
│  🔒 DEX Swap    0.1 BTC → LTC   Step 3/5    In Progress │
└────────────────────────────────────────────────────┘

History                                      [Export ▼]
┌────────────────────────────────────────────────────┐
│  ⚡ CEX Market  Sold 0.2 BTC    $9,400   Feb 25   │
│  🔒 DEX Swap   0.5 ETH → USDT  $1,200   Feb 24   │
│  ⚡ CEX Limit   Bought 2 ETH    $3,800   Feb 23   │
└────────────────────────────────────────────────────┘
```

Labels (🔒 DEX / ⚡ CEX) make venue immediately clear. The filter allows showing DEX-only, CEX-only, or both.

### 9.5 Internal Transfer Between Wallet and Exchange

Moving funds between self-custody wallet and CEX should be as easy as transferring between bank accounts:

```
TRANSFER                              [Wallet ⇄ Exchange]

From: [Wallet (self-custody) ▼]      Balance: 0.15 BTC
To:   [Exchange ▼]                    Balance: 0.04 BTC

Amount: [0.05        ] BTC           [MAX]
        ≈ $2,341.00

Fee: Network fee ~$1.50

[Transfer to Exchange →]

ℹ️ This sends BTC from your wallet to your exchange
   account. It requires an on-chain transaction.
```

For supported coins, internal transfers can use the exchange's deposit address. The app pre-fills this address and handles the flow transparently — the user just picks "Wallet" and "Exchange" as source and destination.

### 9.6 Market Maker Bot (Advanced)

The existing market maker bot is preserved as a power-user feature, accessible from Trade → Bot:

```
MARKET MAKER BOT                          [On/Off Toggle]

Status: Running (3 pairs active)
Uptime: 14h 32m
Total P&L: +$142.50

Active Pairs:
┌────────────────────────────────────────────────────┐
│  BTC/USDT   Spread: 0.5%   Volume: 0.1 BTC   +$82│
│  ETH/USDT   Spread: 0.3%   Volume: 2 ETH     +$45│
│  LTC/BTC    Spread: 0.8%   Volume: 5 LTC     +$15│
│                                                    │
│  [Edit] [Pause] [Remove]  per row                  │
└────────────────────────────────────────────────────┘

[+ Add Trading Pair]
[View Bot Orders in Exchange →]
[Download Performance Report]
```

### 9.7 Bridge Integration

Cross-chain bridge is accessible from Trade → Bridge, following the same From → To pattern as swaps but with explicit chain selection:

```
BRIDGE

From Chain: [Ethereum ▼]     Asset: [USDT ▼]
To Chain:   [Polygon ▼]      Asset: [USDT (auto)]

Amount: [500         ] USDT
Fee: ~$2.40 (bridge + gas)
Est. time: ~5 minutes

[Bridge Now →]
```

---

## 10. Banking & Card Integration (Gleec Pay + Card)

### 10.1 Why This Matters

The "last mile" problem in crypto is spending. Users accumulate crypto but face a multi-step, multi-app process to actually use it for daily expenses. Gleec One solves this by making the Gleec Card and Gleec Pay first-class features alongside the wallet and exchange.

### 10.2 Card Management

#### Card Lifecycle

```
1. Discovery
   └── User sees "Card & Pay" tab in navigation
       └── Landing page: "Spend your crypto anywhere Visa is accepted"
       └── [Get Your Card] CTA

2. Application (Requires Tier 2 KYC)
   ├── If KYC complete: order card instantly
   ├── If KYC incomplete: "Verify identity to get your card" → KYC flow
   └── Card types: Virtual (instant) + Physical (ships in 5-7 days)

3. Activation
   ├── Virtual: ready immediately after approval
   └── Physical: enter card number + CVV to activate

4. Daily Use
   ├── View balance and transactions in app
   ├── Top up from any source (wallet, exchange, Pay)
   ├── Set spending limits
   ├── Freeze/unfreeze card
   └── View card details (number, CVV, expiry)

5. Management
   ├── Replace lost/stolen card
   ├── Change PIN
   ├── Close card
   └── Dispute transactions
```

#### Top-Up Intelligence

The top-up flow should be smart about where funds come from:

```
TOP UP GLEEC CARD                        Amount: $200

Recommended source:
┌────────────────────────────────────────────────────┐
│  💰 USDT (Wallet)           Balance: $1,722       │
│  Stablecoins avoid price slippage.  [Select →]    │
└────────────────────────────────────────────────────┘

Other sources:
┌────────────────────────────────────────────────────┐
│  📊 Exchange Balance         Balance: $340         │
│  No conversion needed.       [Select →]            │
├────────────────────────────────────────────────────┤
│  ₿  BTC (Wallet)            Balance: $7,023       │
│  Will sell BTC at market rate. [Select →]          │
├────────────────────────────────────────────────────┤
│  🏦 Gleec Pay (EUR)          Balance: €3,450      │
│  Convert EUR at current rate. [Select →]           │
└────────────────────────────────────────────────────┘
```

The app recommends stablecoins first (no slippage), then exchange fiat, then volatile crypto — with clear warnings about price impact.

### 10.3 Gleec Pay Banking Integration

#### Account Features

| Feature | Description |
|---|---|
| **IBAN** | Personal IBAN for receiving bank transfers (SEPA, SWIFT) |
| **Send transfers** | Send EUR/USD to any bank account |
| **Receive transfers** | Share IBAN for salary, payments, invoices |
| **Convert to crypto** | Buy crypto directly from Pay balance |
| **Convert from crypto** | Sell crypto to Pay balance (fiat off-ramp) |
| **Card funding** | Top up Gleec Card from Pay balance |
| **Transaction history** | Full banking transaction history |
| **Statements** | Monthly statements for accounting |

#### The Crypto-to-Fiat Loop

This is the killer feature for "James" (the freelancer):

```
Receive crypto payment (USDT, BTC, ETH)
     ↓
View in Gleec One portfolio
     ↓
Option A: Top up Card directly from crypto balance
          → Spend at any Visa merchant
     ↓
Option B: Convert crypto → Gleec Pay (EUR/USD)
          → Use IBAN to pay bills, rent, etc.
     ↓
Option C: Hold in wallet (self-custody)
          → Trade/swap when ready
```

All three options are accessible from the same app, the same portfolio view, with 2-3 taps maximum.

### 10.4 Buy Crypto (Fiat On-Ramp)

Currently using Banxa as an external redirect. Gleec One improves this:

#### Short-term: Embedded Banxa

Embed the Banxa flow inside the app using a webview/iframe instead of redirecting to an external browser. The user stays in-app throughout.

#### Medium-term: Direct Purchase via Gleec Pay

If the user has a Gleec Pay account with EUR/USD balance:

```
BUY CRYPTO

Pay with: [Gleec Pay (EUR) ▼]    Balance: €3,450
Buy:      [Bitcoin (BTC) ▼]
Amount:   [€500            ]      ≈ 0.0107 BTC
Fee:      €1.25 (0.25%)

Receive to: [Wallet (self-custody) ▼]

[Buy Bitcoin →]
```

This eliminates third-party fees and completes the loop: fiat in (Pay) → crypto (Wallet) → trade (DEX/CEX) → spend (Card).

### 10.5 Custody Transparency

Throughout the Card & Pay section, the app must clearly communicate custody status:

```
CUSTODY INDICATORS

🔒 Self-Custody Wallet
   "Only you control these funds. Not even Gleec can access them."

🏦 Gleec Exchange
   "These funds are held on the Gleec exchange. Protected by 2FA and cold storage."

💳 Gleec Card
   "Card balance is held by Gleec's card issuer. Spend anywhere Visa is accepted."

🏛️ Gleec Pay
   "Banking funds are held in a regulated e-money account (FINTRAC licensed)."
```

These indicators appear:
- In the portfolio balance breakdown
- On the asset detail page (balance split section)
- When transferring between venues
- In tooltips throughout the app

---

## 11. Design System & Visual Language

### 11.1 Brand Identity

Gleec One should feel premium, trustworthy, and modern. The visual language draws inspiration from Exodus's polish while establishing Gleec's own identity.

#### Design Tokens

| Token | Value | Notes |
|---|---|---|
| **Primary font** | Inter or Manrope | Clean, modern sans-serif with excellent number rendering |
| **Mono font** | JetBrains Mono or SF Mono | For addresses, amounts, code |
| **Corner radius** | 12px (cards), 8px (buttons), 4px (inputs) | Rounded but not bubbly |
| **Spacing scale** | 4px base (4, 8, 12, 16, 24, 32, 48, 64) | Consistent rhythm |
| **Shadow system** | 3 levels (subtle, medium, elevated) | Depth without heaviness |
| **Animation duration** | 200ms (micro), 350ms (transition), 500ms (page) | Snappy, not sluggish |
| **Animation easing** | Cubic-bezier(0.4, 0, 0.2, 1) | Material standard ease |

### 11.2 Color System

#### Dark Theme (Primary)

| Role | Color | Usage |
|---|---|---|
| **Background** | #0D0F14 | Main app background |
| **Surface** | #161923 | Cards, panels, sidebar |
| **Surface elevated** | #1E2230 | Dropdowns, modals, tooltips |
| **Border** | #2A2E3D | Subtle dividers and card borders |
| **Text primary** | #FFFFFF | Headings, primary content |
| **Text secondary** | #8B8FA3 | Labels, descriptions, metadata |
| **Text tertiary** | #555970 | Disabled, placeholder |
| **Accent primary** | #4F8FFF | CTAs, links, active states |
| **Accent secondary** | #7C5CFC | Secondary actions, charts |
| **Success** | #34D399 | Positive values, confirmations |
| **Warning** | #FBBF24 | Caution states, pending |
| **Error** | #F87171 | Errors, negative values, declines |
| **Positive change** | #34D399 | Price up, profit |
| **Negative change** | #F87171 | Price down, loss |

#### Light Theme

| Role | Color |
|---|---|
| **Background** | #F8F9FC |
| **Surface** | #FFFFFF |
| **Surface elevated** | #FFFFFF (with shadow) |
| **Border** | #E2E4EC |
| **Text primary** | #0D0F14 |
| **Text secondary** | #6B7084 |
| **Accent primary** | #3B7AE8 |

### 11.3 Component Library (Evolved from Komodo UI Kit)

The existing `komodo_ui_kit` package is the foundation, but it needs significant expansion for Gleec One.

#### New / Redesigned Components

| Component | Description | Priority |
|---|---|---|
| **AppSidebar** | Persistent left sidebar with collapse, active states, sub-nav | P0 |
| **MobileTabBar** | 5-tab bottom bar with badges | P0 |
| **PortfolioHeroCard** | Total balance with breakdown tabs and chart | P0 |
| **AssetListItem** | Coin icon, name, balance, sparkline, change % | P0 |
| **TradeRouteCard** | DEX vs CEX comparison card for smart routing | P0 |
| **OrderBookWidget** | Real-time order book with depth visualization | P1 |
| **CandlestickChart** | TradingView-style price chart with time periods | P1 |
| **CardVisual** | Gleec Card representation with flip animation | P1 |
| **CustodyBadge** | 🔒/🏦/💳/🏛️ indicators with tooltip | P0 |
| **ProgressStepper** | Multi-step flow indicator (swap progress, KYC) | P0 |
| **AmountInput** | Crypto/fiat amount input with MAX and conversion | P0 |
| **CoinSelector** | Searchable coin picker with chain grouping | P0 |
| **TransactionListItem** | Unified item for sends, swaps, trades, card purchases | P0 |
| **EmptyState** | Friendly illustration + CTA for empty screens | P1 |
| **NotificationToast** | Non-blocking success/error/info notifications | P0 |
| **KYCStatusBanner** | Verification status with action prompt | P1 |
| **BalanceBreakdown** | Venue-split balance display (wallet/exchange/pay) | P0 |

#### Retained Components (from existing UI Kit)

| Component | Status |
|---|---|
| `UiPrimaryButton` | Keep, update styling |
| `UiSecondaryButton` | Keep, update styling |
| `UiTextFormField` | Keep, add new variants |
| `UiDropdown` | Keep, improve search |
| `UiSwitcher` | Keep as-is |
| `UiCheckbox` | Keep as-is |
| `StatisticCard` | Keep, update layout |
| `UiSpinner` | Replace with Lottie animation |
| `UiScrollbar` | Keep as-is |
| `Gap` | Keep as-is |

### 11.4 Iconography

| Category | Style | Source |
|---|---|---|
| **Navigation icons** | Outlined, 24px, 1.5px stroke | Custom or Phosphor Icons |
| **Action icons** | Filled, 20px | Custom or Phosphor Icons |
| **Coin icons** | Full color, 32px (list) / 48px (detail) | CoinGecko API or local SVGs |
| **Status icons** | Colored filled, 16px | Custom |
| **Illustrations** | Flat, limited palette, branded | Custom (for empty states, onboarding) |

### 11.5 Motion & Animation Principles

| Context | Type | Duration | Easing |
|---|---|---|---|
| Page transition | Slide + fade | 350ms | Ease-in-out |
| Modal open | Scale up + fade | 250ms | Ease-out |
| List item appear | Staggered fade-in | 150ms per item | Ease-out |
| Button press | Scale down 0.97x | 100ms | Linear |
| Success state | Checkmark draw + confetti (optional) | 500ms | Spring |
| Loading | Skeleton shimmer | Continuous | Linear |
| Balance update | Number count-up | 300ms | Ease-out |
| Swap progress | Step-by-step with pulsing active step | Continuous | — |

### 11.6 Responsive Breakpoints

| Breakpoint | Width | Layout |
|---|---|---|
| **Mobile** | < 600px | Bottom tab bar, single column, stacked |
| **Tablet** | 600-1024px | Bottom tab bar, two-column where useful |
| **Desktop** | 1024-1440px | Left sidebar (collapsed by default), multi-column |
| **Wide desktop** | > 1440px | Left sidebar (expanded), multi-column with max-width |

---

## 12. Technical Architecture

### 12.1 Architecture Overview

Gleec One is a **new Flutter project** that imports the Komodo DeFi SDK as a dependency. The app layer is built from scratch with a clean, modular architecture. The key principle is **feature-first organization** with clear boundaries between the self-custody layer (Komodo DeFi SDK), the CEX integration layer, and the banking/card layer.

```
┌─────────────────────────────────────────────────────────────┐
│                     GLEEC ONE APP (Flutter)                   │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  PRESENTATION LAYER                    │   │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────────┐  │   │
│  │  │Portfo│ │Assets│ │Trade │ │Card& │ │Settings  │  │   │
│  │  │lio   │ │      │ │      │ │Pay   │ │          │  │   │
│  │  └──┬───┘ └──┬───┘ └──┬───┘ └──┬───┘ └────┬─────┘  │   │
│  └─────┼────────┼────────┼────────┼───────────┼─────────┘   │
│        │        │        │        │           │              │
│  ┌─────┴────────┴────────┴────────┴───────────┴─────────┐   │
│  │                  BLOC / STATE LAYER                    │   │
│  │  PortfolioBloc, AssetsBloc, TradeBloc, CardBloc,      │   │
│  │  PayBloc, SettingsBloc, AuthBloc, KycBloc             │   │
│  └────────────────────────┬──────────────────────────────┘   │
│                           │                                   │
│  ┌────────────────────────┴──────────────────────────────┐   │
│  │                  REPOSITORY LAYER                      │   │
│  │  ┌──────────┐  ┌──────────┐  ┌───────────────────┐   │   │
│  │  │ Wallet   │  │ Exchange │  │ Banking / Card    │   │   │
│  │  │ Repo     │  │ Repo     │  │ Repo              │   │   │
│  │  └────┬─────┘  └────┬─────┘  └─────┬─────────────┘   │   │
│  └───────┼──────────────┼──────────────┼─────────────────┘   │
│          │              │              │                      │
│  ┌───────┴──────┐ ┌────┴──────┐ ┌─────┴──────────────────┐  │
│  │ Komodo DeFi  │ │ Gleec CEX │ │ Gleec Pay + Card       │  │
│  │ SDK          │ │ API Client│ │ API Client              │  │
│  │ (MM2/KDF)    │ │           │ │                         │  │
│  └──────────────┘ └───────────┘ └─────────────────────────┘  │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│                     SHARED LAYER                             │
│  Design System (UI Kit), Auth, Analytics, Storage, i18n,     │
│  Error Handling, Networking, Feature Flags                    │
└─────────────────────────────────────────────────────────────┘
```

### 12.2 Project Bootstrap

The new project is created with:

```bash
flutter create --org com.gleec --project-name gleec_one gleec-one
```

Then the SDK is added as a git submodule:

```bash
git submodule add <komodo-defi-sdk-flutter-repo-url> sdk
```

And referenced in `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter

  # Komodo DeFi SDK packages (git submodule)
  komodo_defi_sdk:
    path: sdk/packages/komodo_defi_sdk
  komodo_defi_rpc_methods:
    path: sdk/packages/komodo_defi_rpc_methods
  komodo_defi_types:
    path: sdk/packages/komodo_defi_types
  komodo_defi_local_auth:
    path: sdk/packages/komodo_defi_local_auth
  komodo_cex_market_data:
    path: sdk/packages/komodo_cex_market_data

  # New Gleec service clients (local packages)
  gleec_cex_client:
    path: packages/gleec_cex_client
  gleec_pay_client:
    path: packages/gleec_pay_client

  # Core dependencies
  flutter_bloc: ^9.0.0
  get_it: ^8.0.0
  go_router: ^14.0.0
  dio: ^5.0.0
  flutter_secure_storage: ^9.0.0
  easy_localization: ^3.0.0
  # ... etc
```

### 12.3 Feature Module Structure

The new project uses a feature-first folder structure from day one:

```
lib/
├── app/                          # App shell, routing, DI
│   ├── router/
│   ├── di/                       # GetIt dependency injection setup
│   ├── app.dart
│   └── theme/
│
├── core/                         # Shared infrastructure
│   ├── auth/                     # Authentication (local + CEX session)
│   ├── error/                    # Error handling, human-readable messages
│   ├── network/                  # HTTP clients, interceptors
│   ├── storage/                  # Local storage, secure storage
│   ├── analytics/                # Event tracking
│   ├── feature_flags/            # Feature gating (NFTs, Futures, etc.)
│   └── constants/
│
├── features/                     # Feature modules (self-contained)
│   ├── portfolio/
│   │   ├── bloc/
│   │   ├── data/                 # Repository + data sources
│   │   ├── domain/               # Models, entities
│   │   └── presentation/         # Widgets, pages
│   │
│   ├── assets/
│   │   ├── bloc/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── trade/
│   │   ├── swap/                 # DEX swap feature
│   │   │   ├── bloc/
│   │   │   ├── data/
│   │   │   └── presentation/
│   │   ├── exchange/             # CEX order-book trading
│   │   │   ├── bloc/
│   │   │   ├── data/
│   │   │   └── presentation/
│   │   ├── bridge/
│   │   ├── bot/                  # Market maker bot
│   │   └── shared/               # Shared trade components
│   │
│   ├── card/                     # Gleec Card management
│   │   ├── bloc/
│   │   ├── data/
│   │   └── presentation/
│   │
│   ├── pay/                      # Gleec Pay banking
│   │   ├── bloc/
│   │   ├── data/
│   │   └── presentation/
│   │
│   ├── earn/                     # Staking & rewards
│   ├── nfts/                     # NFT gallery
│   ├── onboarding/               # Welcome, wallet creation, KYC
│   └── settings/
│
├── shared/                       # Shared UI components
│   ├── widgets/
│   ├── utils/
│   └── extensions/
│
└── main.dart

sdk/                                  # Git submodule (Komodo DeFi SDK)
└── packages/
    ├── komodo_defi_sdk/
    ├── komodo_defi_rpc_methods/
    ├── komodo_defi_types/
    ├── komodo_defi_local_auth/
    └── komodo_cex_market_data/

packages/                             # New local packages (part of this repo)
├── gleec_cex_client/                 # Gleec CEX API client
├── gleec_pay_client/                 # Gleec Pay + Card API client
└── gleec_ui_kit/                     # New design system (built fresh)
```

### 12.4 New API Integration Layer

#### Gleec CEX API Client

A new package or module wrapping the Gleec CEX REST/WebSocket API:

```
packages/gleec_cex_client/
├── lib/
│   ├── gleec_cex_client.dart     # Public API
│   ├── src/
│   │   ├── api/
│   │   │   ├── auth_api.dart     # Login, 2FA, session management
│   │   │   ├── trading_api.dart  # Orders, trades, order book
│   │   │   ├── account_api.dart  # Balances, deposits, withdrawals
│   │   │   └── market_api.dart   # Ticker, OHLC, trading pairs
│   │   ├── models/               # Response/request models
│   │   ├── websocket/            # Real-time data (order book, ticker)
│   │   └── interceptors/         # Auth, rate limiting, error mapping
│   └── gleec_cex_client.dart
└── test/
```

#### Gleec Pay + Card API Client

```
packages/gleec_pay_client/
├── lib/
│   ├── src/
│   │   ├── api/
│   │   │   ├── account_api.dart  # IBAN, balance, transfers
│   │   │   ├── card_api.dart     # Card management, top-up, freeze
│   │   │   └── kyc_api.dart      # KYC status, document upload
│   │   ├── models/
│   │   └── interceptors/
│   └── gleec_pay_client.dart
└── test/
```

### 12.5 State Management Architecture

BLoC is the primary state management pattern, following conventions from the BLoC library documentation:

#### BLoC Naming Conventions (following BLoC docs)

| Convention | Example |
|---|---|
| Events: past-tense verbs | `SwapRequested`, `OrderPlaced`, `CardTopUpInitiated` |
| States: descriptive nouns | `PortfolioLoaded`, `SwapInProgress`, `CardFrozen` |
| BLoC names: feature + Bloc | `PortfolioBloc`, `SwapBloc`, `ExchangeBloc` |
| Cubits for simple state | `ThemeCubit`, `BalanceVisibilityCubit` |

#### Key New BLoCs

| BLoC | Responsibility |
|---|---|
| `PortfolioBloc` | Aggregates balances from Wallet + CEX + Pay into unified view |
| `ExchangeBloc` | CEX order management, order book, trading state |
| `ExchangeAuthBloc` | CEX session, 2FA, separate from wallet auth |
| `CardBloc` | Card balance, transactions, top-up, freeze/unfreeze |
| `PayBloc` | Gleec Pay balance, transfers, IBAN management |
| `KycBloc` | KYC status, document upload, verification progress |
| `TradeRouterBloc` | Smart routing — compares DEX vs CEX rates for a trade |
| `NotificationBloc` | Unified notifications from all services |

#### Mapping from Old Wallet BLoCs (Reference)

When porting logic from the existing wallet, use this mapping to understand where old BLoC concerns land in the new architecture:

| Old Wallet BLoC | New Gleec One BLoC(s) | Notes |
|---|---|---|
| `AuthBloc` | `WalletAuthBloc` + `ExchangeAuthBloc` | Split local wallet auth from CEX session |
| `CoinsBloc` | `AssetsBloc` | Add CEX balance aggregation |
| `TakerBloc` / `MakerFormBloc` | `SwapBloc` | Simplified, cleaner states |
| `TradingEntitiesBloc` | `OrdersBloc` | Unified DEX + CEX orders |
| `WithdrawFormBloc` | `SendBloc` | Port state machine, simplify events |
| `MarketMakerBotBloc` | `BotBloc` | Port state machine as-is, update UI bindings |
| `BridgeBloc` | `BridgeBloc` | Port largely as-is |
| `TransactionHistoryBloc` | `TransactionBloc` | Add CEX/Pay/Card transaction sources |
| `SettingsBloc` | `SettingsBloc` | New from scratch, expanded preferences |
| `OrderbookBloc` | `DexOrderbookBloc` + `CexOrderbookBloc` | Separate DEX and CEX order books |

### 12.6 Data Flow — Unified Portfolio Example

```
                    PortfolioBloc
                         │
            ┌────────────┼────────────┐
            │            │            │
      WalletRepo    ExchangeRepo   PayRepo
            │            │            │
      KomodoSDK    GleecCEXAPI   GleecPayAPI
      (MM2/KDF)                  (+ CardAPI)
            │            │            │
            ▼            ▼            ▼
     Self-custody    Exchange      Banking
      balances       balances      balances
            │            │            │
            └────────────┼────────────┘
                         │
                  PortfolioState
                  {
                    totalBalance: $12,847,
                    walletBalance: $9,023,
                    exchangeBalance: $2,577,
                    payBalance: $1,247,
                    assets: [
                      { coin: BTC, wallet: 0.10, exchange: 0.04, card: 0.01 },
                      { coin: ETH, wallet: 2.4, exchange: 0, card: 0 },
                      ...
                    ]
                  }
```

### 12.7 Offline & Caching Strategy

| Data | Cache Duration | Source |
|---|---|---|
| Wallet balances | Real-time (from KDF) | Komodo DeFi SDK |
| CEX balances | 10-second polling + WebSocket | Gleec CEX API |
| Pay/Card balances | 30-second polling | Gleec Pay API |
| Price data | 30-second cache | CEX market data package |
| Order book | Real-time WebSocket | Gleec CEX API |
| Transaction history | Cache with pull-to-refresh | All sources |
| Coin metadata | 24-hour cache | Local + API |
| User preferences | Persistent local storage | SharedPreferences / Hive |

### 12.8 Security Architecture

| Layer | Mechanism |
|---|---|
| **Wallet keys** | Local-only, AES-256 encrypted, never leaves device |
| **CEX session** | JWT tokens, stored in secure storage, auto-refresh |
| **Pay session** | Separate JWT, stricter timeout (15 min inactivity) |
| **2FA** | TOTP for CEX and Pay (Google Authenticator / Authy compatible) |
| **Biometrics** | Device-level biometric gate for app unlock + sensitive actions |
| **Pin protection** | Optional app PIN as fallback for no-biometric devices |
| **Screenshot protection** | Prevent screenshots on sensitive screens (seed, private key, card CVV) |
| **Certificate pinning** | Pin CEX and Pay API certificates |
| **Secure storage** | flutter_secure_storage for tokens, passwords, sensitive data |

---

## 13. Phased Delivery Roadmap

The unified app is delivered in four phases, each shippable as an independent release. Each phase adds a layer of functionality while maintaining a polished, complete-feeling product.

### Phase 0: Foundation (Weeks 1-8)

**Goal:** Bootstrap the new Flutter project, implement the design system, wire up the Komodo DeFi SDK, and ship a wallet that matches Exodus quality for core wallet features (hold, send, receive, view portfolio).

#### Deliverables

| # | Item | Description | Effort |
|---|---|---|---|
| 0.1 | Project bootstrap | Create new Flutter project, add SDK submodule, configure CI | M |
| 0.2 | Design system (gleec_ui_kit) | New color tokens, typography, core components from spec | L |
| 0.3 | App shell & navigation | Left sidebar (desktop) + bottom tab bar (mobile) + go_router | L |
| 0.4 | Core infrastructure | DI (GetIt), error handling, secure storage, analytics, i18n | L |
| 0.5 | Wallet auth | Wallet creation, import (seed), password, biometrics — HD only | L |
| 0.6 | Portfolio home screen | Hero balance card, donut chart, activity feed, quick actions | L |
| 0.7 | Asset list & management | Asset list with sparklines, search, sort/filter, add/remove coins | L |
| 0.8 | Asset detail page | Price chart, send/receive actions, transaction history, addresses | L |
| 0.9 | Send flow | Port withdraw state machine into new `SendBloc`, new UI | L |
| 0.10 | Receive flow | Address display, QR code, copy, share | M |
| 0.11 | Theme system | Dark/light themes per spec, system theme detection | M |
| 0.12 | Settings (basic) | Theme, language, hide balances, backup seed, security | M |
| 0.13 | Error message system | Human-readable error mapping (port from existing WIP) | M |
| 0.14 | Old wallet maintenance plan | Bug-fix-only branch for existing wallet during transition | S |

**Exit criteria:** A standalone app that can create/import a wallet, display portfolio, manage assets, send/receive crypto, and looks like a modern Exodus-quality product. DEX swaps and trading are NOT in scope yet — this phase proves the new app shell works end-to-end with the SDK.

**Key difference from an in-place refactor:** Every line of code in the new project is intentional. There's no dead code, no half-migrated screens, no legacy navigation. The SDK handles crypto operations; the app only contains presentation, state management, and the new service clients.

### Phase 1: DEX Swaps + CEX Trading (Weeks 9-18)

**Goal:** Add DEX swap functionality (ported from existing wallet logic) and introduce CEX order-book trading. This is the first "unified trading" milestone.

#### Deliverables

| # | Item | Description | Effort |
|---|---|---|---|
| 1.1 | DEX swap feature | Port swap logic from old wallet, build new from/to UI, progress tracker | L |
| 1.2 | Gleec CEX API client | New package wrapping CEX REST + WebSocket API | XL |
| 1.3 | CEX authentication | Login, 2FA, session management within app | L |
| 1.4 | Exchange screen | Order book, price chart, order entry (market/limit) | XL |
| 1.5 | Unified order management | Single view for DEX + CEX orders/history | L |
| 1.6 | Internal transfers | Wallet ⇄ Exchange transfer flow | M |
| 1.7 | Trade routing | Smart DEX vs CEX comparison for swap initiation | L |
| 1.8 | KYC flow (basic) | Email + phone verification for CEX access | M |
| 1.9 | Bridge feature | Port bridge logic from old wallet, build new UI | M |
| 1.10 | Market maker bot | Port bot state machine from old wallet, build new UI | M |

**Exit criteria:** Users can trade on both DEX and CEX from one app. The smart routing suggests the best venue. CEX users can deposit/withdraw to self-custody wallet seamlessly.

### Phase 2: Banking & Card (Weeks 19-26)

**Goal:** Integrate Gleec Pay and Gleec Card, completing the "earn, hold, trade, spend" cycle.

#### Deliverables

| # | Item | Description | Effort |
|---|---|---|---|
| 2.1 | Gleec Pay API client | New package for Pay REST API | L |
| 2.2 | Gleec Card API client | Card management API integration | L |
| 2.3 | Card & Pay tab | Navigation section with card and banking views | M |
| 2.4 | Card management UI | Card visual, balance, freeze, transactions | L |
| 2.5 | Card top-up flow | Smart top-up from wallet/exchange/pay | L |
| 2.6 | Banking dashboard | IBAN display, transfer history | M |
| 2.7 | Send bank transfer | SEPA/SWIFT transfer form | M |
| 2.8 | Buy crypto via Pay | Direct purchase from Pay balance | L |
| 2.9 | Full KYC flow | ID verification for Pay/Card access | L |
| 2.10 | Unified portfolio v2 | Add Pay and Card balances to portfolio | M |
| 2.11 | Custody indicators | Visual indicators throughout app | S |

**Exit criteria:** Users can manage their Gleec Card, view banking details, top up card from crypto, and see all balances (wallet + exchange + pay + card) in one portfolio.

### Phase 3: Polish & Power Features (Weeks 27-34)

**Goal:** Add staking, NFTs, advanced features, and polish every interaction to ship-ready quality.

#### Deliverables

| # | Item | Description | Effort |
|---|---|---|---|
| 3.1 | Staking / Earn | Staking interface for supported coins | L |
| 3.2 | NFT gallery v2 | Re-enable and polish NFT feature | L |
| 3.3 | Push notifications | Transaction alerts, price alerts, card activity | M |
| 3.4 | Tax export | Transaction export for tax reporting | M |
| 3.5 | Futures / margin | Advanced CEX trading (gated by KYC tier) | XL |
| 3.6 | dApp browser | In-app browser for Web3 interactions (mobile) | L |
| 3.7 | Multi-wallet switcher | Polish account switching UX | M |
| 3.8 | Ledger support | Add Ledger hardware wallet support | L |
| 3.9 | Accessibility audit | WCAG AA compliance, screen reader testing | M |
| 3.10 | Performance optimization | Startup time, memory, animation perf | M |
| 3.11 | Localization expansion | Add 5+ languages beyond English | M |
| 3.12 | QR device sync | Sync wallet config between devices | L |

**Exit criteria:** Feature-complete Gleec One app ready for public launch.

### Effort Legend

| Size | Estimated Effort |
|---|---|
| S | 1-3 days (1 developer) |
| M | 3-7 days (1-2 developers) |
| L | 1-3 weeks (2-3 developers) |
| XL | 3-6 weeks (2-4 developers) |

### Release Strategy

| Release | Codename | Audience | Content |
|---|---|---|---|
| **Alpha** (end of Phase 0, ~Week 8) | "Canvas" | Internal team | Core wallet (hold, send, receive, portfolio) |
| **Beta 1** (end of Phase 1, ~Week 18) | "Bridge" | Invited testers | + DEX swaps + CEX trading |
| **Beta 2** (end of Phase 2, ~Week 26) | "Wallet" | Expanded beta | + Card & Pay integration |
| **RC** (mid Phase 3, ~Week 30) | "One" | Open beta | Feature complete |
| **1.0** (end of Phase 3, ~Week 34) | "Gleec One" | Public | Full launch |

**Note on timeline:** The new-app approach adds ~4 weeks to the overall roadmap compared to an in-place refactor (Phase 0 is 8 weeks instead of 6) because the app shell, authentication, and core wallet features must be built from scratch. However, this is recouped in later phases through faster iteration on a clean codebase with no migration surprises.

---

## 14. Success Metrics & KPIs

### 14.1 North Star Metric

**Monthly Active Wallets (MAW)** — The number of unique wallets that perform at least one meaningful action (send, receive, swap, trade, or card purchase) per month.

### 14.2 Funnel Metrics

| Stage | Metric | Target (6 months post-launch) |
|---|---|---|
| **Acquisition** | App downloads / installs | 50,000+ |
| **Activation** | Wallets created (completed onboarding) | 60% of installs |
| **First value** | First deposit or buy | 40% of activations |
| **Engagement** | Weekly active users | 30% of activated users |
| **Retention** | 30-day retention | 25% |
| **Revenue** | CEX trading volume | Baseline + 30% |
| **Revenue** | Card transaction volume | Baseline + 50% |

### 14.3 Feature-Specific KPIs

| Feature | KPI | Target |
|---|---|---|
| **Unified Portfolio** | % users who check portfolio daily | > 40% of MAW |
| **DEX Swaps** | Swap completion rate | > 85% (up from current baseline) |
| **CEX Trading** | % wallet users who also trade on CEX | > 15% (cross-sell) |
| **Smart Routing** | % of trades that use recommended route | > 60% |
| **Gleec Card** | % verified users who activate card | > 25% |
| **Card Top-Up** | Avg. monthly top-ups per card user | > 3 |
| **Gleec Pay** | % verified users who use IBAN | > 20% |
| **KYC Completion** | % of users who start KYC and complete it | > 70% |
| **Market Maker Bot** | Number of active bot users | 2x current baseline |

### 14.4 Experience Quality Metrics

| Metric | Target |
|---|---|
| App startup time (cold) | < 3 seconds |
| Time to first swap (new user) | < 5 minutes from install |
| Crash-free sessions | > 99.5% |
| App Store rating | > 4.5 stars |
| NPS (Net Promoter Score) | > 40 |
| Support ticket volume per MAW | < 5% |
| Average session duration | > 3 minutes |

---

## 15. Risks & Mitigations

### 15.1 Technical Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| CEX API instability or breaking changes | Medium | High | Versioned API client with retry/fallback, mock server for testing |
| Pay/Card API integration complexity | Medium | High | Early API exploration in Phase 0, close collaboration with Pay/Card team |
| Performance degradation from added features | Medium | Medium | Performance budget per phase, lazy loading, profiling in CI |
| Platform-specific issues (web, iOS, Android) | High | Medium | Platform-specific testing matrix, CI on all targets |
| SDK breaking changes (Komodo DeFi) | Low | High | Pin SDK versions, integration tests, maintain fork if needed |

### 15.2 Product Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Feature bloat overwhelming users | Medium | High | Progressive disclosure, feature flags, user testing each phase |
| KYC friction causing drop-off | High | High | Tiered KYC (wallet works without it), streamlined ID verification |
| Users confused by custody model | Medium | High | Consistent custody badges, educational tooltips, onboarding education |
| CEX+DEX cannibalization | Low | Medium | Position as complementary — DEX for privacy, CEX for speed/liquidity |
| Card/Pay regulatory issues in certain jurisdictions | Medium | High | Geo-fencing, feature flags per region, legal review per market |

### 15.3 Design Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Ported BLoC logic introduces subtle regressions | Medium | Medium | Side-by-side testing against old wallet, integration tests for ported flows |
| Navigation complexity with expanded features | Medium | High | User testing with card sorting, A/B test navigation patterns |
| Mobile tab bar limited to 5 items | Low | Low | "More" tab with smart promotion of frequent features |
| Dark mode contrast issues | Low | Medium | WCAG AA audit, contrast checker in design review |

### 15.4 Business Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Competitor launches similar unified app | Medium | Medium | Speed to market, Gleec ecosystem lock-in (Pay/Card unique) |
| Low adoption of banking features | Medium | Medium | Card incentives (cashback, no fees), banking benefits marketing |
| Regulatory landscape changes | Medium | High | Modular architecture allows disabling features per jurisdiction |
| Team capacity for 30-week roadmap | Medium | High | Phase 0 and 1 are most critical — staff accordingly, cut Phase 3 scope if needed |

---

## 16. Appendix

### A. Glossary

| Term | Definition |
|---|---|
| **CEX** | Centralized Exchange — Gleec's order-book exchange (exchange.gleec.com) |
| **DEX** | Decentralized Exchange — atomic-swap based, non-custodial trading via Komodo SDK |
| **KDF** | Komodo DeFi Framework — the underlying protocol engine (MM2) |
| **Atomic Swap** | Trustless exchange of assets between two parties without an intermediary |
| **HD Wallet** | Hierarchical Deterministic wallet — BIP39/BIP44 standard |
| **KYC** | Know Your Customer — identity verification required for regulated services |
| **IBAN** | International Bank Account Number — used for bank transfers |
| **SEPA** | Single Euro Payments Area — EU bank transfer system |
| **FINTRAC** | Financial Transactions and Reports Analysis Centre of Canada |
| **MAW** | Monthly Active Wallets — Gleec One's north star metric |

### B. Reference Apps Studied

| App | Key Takeaway for Gleec One |
|---|---|
| **Exodus** | UX benchmark — portfolio-first design, sidebar nav, premium visual polish |
| **Trust Wallet** | Multi-chain simplicity, dApp browser, clean asset management |
| **Coin98** | Super-app architecture, multi-zone navigation, DeFi integration |
| **goodcryptoX** | CEX+DEX+Bot in one app, proves the unified model works |
| **Revolut** | Fintech UX for card management, instant transfers, clean banking UI |
| **Binance** | CEX trading UI patterns, order types, futures interface |

### C. Exodus Feature Comparison Matrix

| Feature | Exodus | Gleec (Current) | Gleec One (Proposed) |
|---|---|---|---|
| Portfolio dashboard | Excellent | Basic | Excellent+ |
| Asset management | Excellent | Good | Excellent |
| DEX swaps | Good (via partners) | Excellent (atomic) | Excellent |
| CEX trading | None | Separate app | Integrated |
| Fiat on-ramp | MoonPay/Ramp | Banxa (redirect) | Banxa + Gleec Pay |
| Fiat off-ramp | Limited | None | Gleec Pay |
| Banking / IBAN | None | Separate service | Integrated |
| Debit card | None | Separate app | Integrated |
| Staking | Good | None | Good |
| NFTs | Good | Disabled | Good |
| Hardware wallet | Trezor + Ledger | Trezor | Trezor + Ledger |
| Market maker bot | None | Good | Excellent |
| Bridge | Limited | Good | Good |
| Mobile UX | Excellent | Good | Excellent |
| Desktop UX | Excellent | Good | Excellent |
| Onboarding | Excellent | Complex | Excellent |
| Dark mode | Yes | Yes | Yes (improved) |
| Multi-language | Yes | Yes | Yes (expanded) |

### D. Open Questions for Stakeholders

1. **CEX API access:** Does the Gleec CEX team provide a documented API? What authentication model does it use? Is there a sandbox/testnet?

2. **Pay/Card API access:** Is there an API for Gleec Pay and Gleec Card, or does integration require building one? What's the current tech stack?

3. **KYC provider:** Should Gleec One use the CEX's existing KYC flow (redirect), or build a native in-app KYC flow? If native, which provider (Jumio, Onfido, Sumsub)?

4. **Regulatory scope:** Which jurisdictions are targeted for launch? Card and Pay features may need to be geo-fenced.

5. **Brand alignment:** Is "Gleec One" the final name? Should the app replace the existing Gleec Wallet brand or coexist during transition?

6. **Team capacity:** What's the available Flutter development team size? The roadmap assumes 3-5 Flutter developers + 1 designer + 1 PM.

7. **CEX feature scope:** Should the initial CEX integration include futures/margin, or is spot-only sufficient for Phase 1?

8. **Hardware wallet scope for CEX:** Should Trezor users be able to trade on CEX (requires custodial deposit), or remain wallet-only?

9. **Existing user migration:** How do we migrate existing Gleec Wallet users to Gleec One? Can seed phrases be re-imported seamlessly? Should the old app prompt users to download Gleec One?

10. **SDK ownership:** Should the Komodo DeFi SDK remain as a git submodule, or should Gleec fork and own it for faster iteration?

11. **Old wallet end-of-life:** What is the maintenance window for the existing Gleec Wallet after Gleec One launches? When does it get sunset?

12. **App store listing:** New listing for Gleec One, or update the existing Gleec Wallet listing? New listing means rebuilding download numbers but avoids confusing existing users with a radically different app.

13. **Repository hosting:** Should the new Gleec One repo live in the same GitHub org? Should the SDK submodule reference be public or use deploy keys?

14. **Shared accounts:** Can a single Gleec identity (email/phone) work across CEX, Pay, and Card, or do they currently have separate account systems that need unification on the backend?

---

*This document is a living plan. It should be reviewed and updated as stakeholder feedback is incorporated, technical discoveries are made, and market conditions evolve.*
