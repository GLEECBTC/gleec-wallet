# Gleec Wallet v0.9.3 Release Notes

This release delivers significant performance improvements, enhanced analytics capabilities, and a comprehensive overhaul of authentication and wallet management. Key highlights include real-time portfolio streaming, a dual analytics pipeline with persistent queueing, one-click sign-in, Z-HTLC support, and extensive optimisations that reduce RPC usage while improving responsiveness across all platforms.

## 🚀 New Features

- **Realtime Portfolio Streaming** ([@CharlVS], #3253) - Live balance updates throughout the app via `CoinsBloc` streaming, eliminating the need for manual refreshes
- **One-Click "Remember Me" Sign-In** ([@CharlVS], #3041) - Securely cache wallet metadata for instant access with improved post-login routing
- **Dual Analytics Pipeline** ([@CharlVS], #2932) - Firebase and Matomo integration with persistent event queueing, CI toggles, and comprehensive event tracking
- **Z-HTLC Support** ([@Francois], #3158) - Full support for privacy-preserving Hash Time Locked Contracts with configurable activation toggles and optional sync parameters
- **Enhanced Feedback System** ([@CharlVS], #3017) - Comprehensive feedback portal overhaul with provider plugins, opt-out contact handling, screenshot scrubbing, and analytics integration
- **Geo-blocking Bouncer** ([@CharlVS], #3150) - Privacy coin restrictions with regulated build overrides for compliance
- **Transaction Broadcast Details** ([@smk762], #3308) - View transaction details immediately after broadcasting withdrawals
- **Market Maker Mobile Improvements** ([@Francois], #3220) - Status indicators and start/stop controls now available in mobile view
- **Swap Data Export** ([@Kadan], #3220) - Copy and export swap data for reference and debugging
- **Tendermint Faucet Support** ([@Francois], #3206) - Request test coins for Tendermint-based assets with activation guardrails
- **Optional Verbose Logging** ([@Kadan], #3332) - Configurable logging levels for development and troubleshooting
- **SDK Log Integration** ([@CharlVS], #3159) - SDK logs now route through the app logger for unified log management

### SDK Updates (komodo-defi-sdk-flutter)

This release integrates [komodo-defi-sdk v1.0.0-pre.1](https://github.com/GLEECBTC/komodo-defi-sdk-flutter) with 82 commits bringing substantial improvements:

- **Flutter Web WASM Support** ([SDK#176](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/176)) - WASM support with OPFS integration and unified storage
- **Enhanced RPC Coverage** ([SDK#179](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/179), [#188](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/188), [#191](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/191)) - Trading, orderbook, and Lightning RPC support
- **Streaming Infrastructure** ([SDK#178](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/178), [#232](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/232), [#269](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/269)) - Pubkey and balance watch streams with comprehensive caching
- **Multi-Provider Market Data** ([SDK#145](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/145), [#224](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/224)) - CoinPaprika fallback and refined Binance quotes
- **Custom Token Storage** ([SDK#225](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/225), [#190](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/190)) - Runtime coin updates integration
- **Platform Support** ([SDK#237](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/237), [#247](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/247)) - macOS universal binary and packaging updates

See the [full SDK changelog](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/releases) for complete details.

## 🎨 UI/UX Improvements

- **Fiat Value Display** ([@Francois], #3049) - Coin detail pages now show fiat balance for individual addresses
- **Withdraw Form Enhancements** ([@Francois], #3274) - Vertical responsive layout, fiat value previews for amount and fee, and alignment improvements
- **Loading State Placeholders** ([@Francois], #3134) - Hide asset lists and show placeholders until fiat prices are available for better UX
- **Transaction History Ordering** ([@CharlVS], #9900372) - Unconfirmed transactions now appear first in the list
- **Token Parent Labelling** ([@dragonhound], #2988) - Parent coins now tagged as "native" for clearer asset hierarchy
- **Trezor Visibility Toggles** ([@smk762], #3214) - Password and PIN visibility controls for Trezor authentication
- **Market Maker Value Display** ([@smk762], #3215) - Fixed bot maker order values display
- **Activation Filter Compatibility** ([@smk762], #3249) - Only show compatible activation filter options to prevent errors
- **Buy Coin List Sorting** ([@smk762], #3328) - Market maker buy coin list now sorted with price filters and "add assets" footer
- **Keyboard Dismissal** ([@Francois], #3225) - Dismiss keyboard on scroll for fiat and swap inputs
- **Mobile Seed Backup Banner** ([@Francois], #3225) - Seed backup banner now visible in mobile view
- **Post-Login Navigation** ([@smk762], #3262) - Consistent routing to wallet page after login or logout with delayed navigation for Trezor PIN/passphrase entry
- **Custom Seed Toggle** ([@smk762], #3260) - Hide custom seed toggle unless BIP39 validation fails
- **NFT Withdraw QR Scanning** ([@smk762], #3243) - QR code scan button added to NFT withdrawal address input
- **Consistent Pill Styling** ([@dragonhound], #2974) - Applied uniform "swap address" pill style throughout the app
- **Thoughtful Scrollbar Disposal** ([@dragonhound], #3008) - Improved scrollbar lifecycle management

## ⚡ Performance Enhancements

- **RPC Spam Reduction** ([@CharlVS], #3253) - Comprehensive SDK-side caching and streaming support drastically reduces redundant RPC calls
- **Fiat On-Ramp Debouncing** ([@Francois], #3125) - Reduced API calls on user input changes for smoother fiat amount entry
- **Balance Watch Streams** (SDK, #178) - Realtime balance updates from SDK eliminate polling
- **Pubkey Caching** ([@CharlVS], #3251) - Prefer cached pubkeys before RPC across the app with post-swap fetch delays
- **Best Orders Optimization** ([@smk762], #3328) - Avoid best_orders calls unless on DEX/bridge; fail gracefully and retry
- **Activation Patience** ([@smk762], #3272) - Await initial activations and avoid duplicated activation tasks with proper parent/child coin sync

## 🐛 Bug Fixes

- **Transaction History Cross-Asset Bleed** ([@CharlVS], #3289) - Isolated `TransactionHistoryBloc` per-coin to prevent history mixing
- **Balance Update State Preservation** ([@CharlVS], #3253) - Realtime balance updates now preserve coin activation state to avoid turning off the Send button
- **Transaction Sorting** ([@CharlVS], #3253) - Fixed transaction history list sorting logic
- **Dropdown Null Safety** ([@Cursor Agent], #3050) - Fixed null safety issues in `UiDropdown` widget, preventing app freeze on logout
- **Legacy Wallet Migration** ([@CharlVS], #3207) - Preserve legacy flag, sanitise wallet names, ensure uniqueness, and avoid duplicate imports during migration
- **Wallet Coin Restoration** ([@Francois], #3126) - Restore wallet coins for legacy wallet migrations and seed file imports
- **Password Length Validation** ([@CharlVS], #3141, #3149) - Consistent 128-character password handling across all flows with hardened validation
- **Custom Token Import** ([@Francois], #3129) - Check platform in deduplication and correctly update fields; refresh asset list on import
- **Precision Loss in Wallet** ([@CharlVS], #3123) - Resolved DEX precision regression with comprehensive tests
- **Withdraw Form Fixes** ([@Francois], #3274) - Fixed fiat alignment, max value detection, and use signed hex from preview for broadcast
- **ZHTLC Activation Toggle** ([@smk762], #3283) - Revert toggle on ZHTLC activation config cancel
- **Coin Variant Sum** ([@smk762], #3317) - Fixed coin variant sum display in dropdowns
- **Decimals Precision** ([@Kadan], #3297) - Added unit tests and fixed decimal handling with proper fiat amount input refactoring
- **Trading Bot Improvements** ([@Francois], #3223, #3328) - Remove price URL parameter to default to KDF URL list; add guard against swap button spamming; use `max_maker_vol` for spendable balance
- **Market Maker Dropdown** ([@Francois], #3187) - Fixed sell coin dropdown reverting to previous coin with occasional flickering
- **ARRR Reactivation** ([@Francois], #3184) - Fixed ARRR not reappearing in coins list after deactivation and reactivation
- **Pubkey Clearing** ([@CharlVS], #3144) - Clear pubkeys on wallet change or logout to prevent cross-wallet contamination
- **Unban Pubkeys Null Check** ([@smk762], #3276) - Avoid null check error on unban_pubkey button press
- **Timer Leaks** ([@Kadan], #3305) - Fixed timer leaks preventing proper cleanup
- **SSE Lifecycle** ([@Kadan], #3313, #3318) - Tie SSE to the auth state lifecycle and remove the SSE package for better stability
- **iOS/macOS KDF Reinitialization** ([@Kadan], #3286) - Proper KDF health check and reinitialisation on iOS/macOS
- **Withdrawal Form** ([@Kadan], #3288) - Fixed withdrawal regression
- **KDF Disposal Crash** ([@DeckerSU], #3117) - Fixed crash when `KomodoDefiSdk` is disposed during periodic fetch
- **Fiat On-Ramp CSP** ([@Francois], #3225) - Disable overly restrictive CSP with limited platform support; add Komodo and sandbox domains to allowlist
- **NFT IPFS Loading** ([@Francois], #3020) - Add IPFS gateway resolution, retry, and fallback to improve NFT image loading
- **macOS File Picker** ([@CharlVS], #3111) - Show file picker by adding user-selected read-only entitlement
- **Settings Version Isolation** ([@smk762], #3324) - Isolate version settings in shared_preferences.json for backwards compatibility
- **Unconfirmed Transaction Detection** ([@Francois], #3328) - Only consider empty timestamps and confirmations as unconfirmed

## 🔒 Security & Compliance

- **128-Character Password Support** ([@CharlVS], #3141, #3149) - Increased password length limit to 128 characters with consistent validation across all auth flows
- **Pubkey Hygiene** ([@CharlVS], #3144, #3251) - Purge cached pubkeys on wallet change, prefer cached pubkeys before RPC, and add post-swap delays
- **Geo-blocking Bouncer** ([@CharlVS], #3150) - Privacy coin restrictions with FD monitoring and regulated build overrides
- **Legacy Wallet Sanitisation** ([@CharlVS], #3207) - Sanitise names, preserve flags, and prevent duplicate imports during legacy wallet migration

## 💻 Platform-Specific Changes

### All Platforms

- **Flutter 3.35.1 Upgrade** ([@CharlVS], #3108) - Updated Flutter SDK with dependency roll and improved roll script
- **SDK Submodule Integration** ([@Francois], #3110) - SDK adopted as a git submodule with path overrides and deterministic roll script

### macOS

- **Production Scheme & Signing** ([@DeckerSU], #3185) - Added macOS production scheme and Developer ID Application signing support for standalone distribution
- **Universal Binary Support** (SDK, #237) - macOS universal binary (Intel + Apple Silicon) support
- **Development Team Update** ([@DeckerSU], #3177, [@DeckerSU] SDK #239) - Changed development team to production identifier (WDS9WYN969→8HPBYKKKQP)
- **KDF Binary Placement** (SDK, #247) - Streamlined KDF binary placement and updated signing flow

### Linux

- **GLib Compatibility** ([@DeckerSU], #3105) - Guard `G_APPLICATION_DEFAULT_FLAGS` behind GLib ≥ 2.74 with fallback for older versions
- **Single-Instance Enforcement** ([@CharlVS], #3063) - Enforce single-instance; focus existing window; prevent zombie processes
- **Build Script Validation** ([@DeckerSU], #3106) - Added GitHub Actions workflow to validate Linux build script

### Windows

- **Single-Instance Enforcement** ([@CharlVS], #3063) - Prevent multiple instances and zombie processes

### iOS

- **FD Monitoring** ([@Kadan], #3259) - File descriptor monitoring for release mode
- **Health Check Integration** ([@Kadan], #3257) - Added KDF health check with reinitialization support
- **Xcode Configuration** ([@DeckerSU], #3324) - Added FdMonitor.swift to Xcode project configuration and updated DEVELOPMENT_TEAM identifier
- **Build Artifact Cleanup** ([@DeckerSU], #3058) - Removed .dgph build artifacts from iOS project
- **Ruby Installation Guide** ([@Francois], #3128) - Added Ruby installation step for iOS builds

### Web

- **WASM Support** (SDK, #176) - Flutter Web WASM support with OPFS integration and unified storage implementation
- **CDN Disable** ([@DeckerSU], #3055) - Add `--no-web-resources-cdn` to web build in build.sh

### Docker & DevOps

- **DevContainer Modernization** ([@CharlVS], #3114) - Switched to .docker images and Linux-only devcontainer
- **Environment Variable Passing** ([@DeckerSU], #3037) - Correct env vars passing to Docker and Dart via --dart-define
- **Matomo Validation** ([@DeckerSU], #3165) - Added Matomo tracking params validation in build script
- **CI Improvements** ([@CharlVS], #3167, #3336) - Fix missing secrets, remove duplicate steps; fix CI issues
- **Artifact Naming** ([@dragonhound], #3181) - Append short commit hash to upload-artifact filenames
- **Submodule Updates** ([@DeckerSU], #3139) - Clean submodules before update to fix build errors

## 🔧 Technical Improvements

### SDK Integration (komodo-defi-sdk v1.0.0-pre.1)

- **RPC Coverage Expansion** ([SDK#179](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/179), [#188](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/188), [#191](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/191)) - Implemented missing RPCs, including trading-related endpoints and Lightning support
- **Message Signing** ([SDK#198](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/198), [#231](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/231)) - HD wallet support for message signing with derivation path; added AddressPath type and refactored to use Asset/PubkeyInfo
- **Multi-Provider Market Data** ([SDK#145](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/145), [#215](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/215)) - Support for multiple market data providers with CoinPaprika fallback option
- **Custom Token Integration** ([SDK#225](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/225), [#190](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/190)) - Custom token support in coin config manager; integrate komodo_coin_updates into komodo_coins
- **Balance & Pubkey Streaming** ([SDK#178](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/178), [#232](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/232), [#262](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/262), [#269](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/269)) - Add pubkey watch function similar to balance watch; comprehensive caching and streaming support
- **ETH-BASE Support** ([SDK#254](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/254)) - Add support for ETH-BASE and derived assets
- **Asset Tagging Fixes** ([SDK#244](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/244)) - Correct UTXO coins incorrectly tagged as Smart Chain
- **ZHTLC Fixes** ([SDK#227](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/227), [#264](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/264)) - ZHTLC activation fixes with optional sync params and sign-out cleanup
- **Binance Quote Fixes** ([SDK#224](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/224)) - Use per-coin supported quote currency list instead of global cache
- **Market Metrics Logging** ([SDK#223](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/223)) - Reduce market metrics log verbosity and duplication
- **Etherscan URLs** ([SDK#217](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/217)) - Fix Etherscan URL formatting
- **Sparkline Configuration** ([SDK#248](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/248)) - Add configurable sparkline baseline
- **Dragon Charts Migration** ([SDK#164](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/164)) - Migrate dragon_charts_flutter to monorepo packages
- **Trezor Polling** ([SDK#126](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/126)) - Poll Trezor connection status and sign out when disconnected
- **KDF Version Updates** ([SDK#218](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/218), [#237](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/237), [#249](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/249), [#241](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/241), [#247](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/247)) - Roll KDF to latest releases with checksum updates
- **Runtime Fetch Libraries** ([SDK#280](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/280)) - Use runtime fetch libraries with updated checksums

### Analytics & Monitoring

- **Persistent Event Queue** ([@CharlVS], #2932) - Analytics events persist across sessions with a standardised event structure
- **CI Analytics Toggles** ([@CharlVS], #2932, #3165) - Disable analytics in CI builds with Matomo validation
- **NFT Analytics Integration** ([@dragonhound], #3202) - Use AnalyticsRepo to enqueue NFT analytics events
- **Updated Events** ([@CharlVS], #3194) - Update completed events and remove scroll attempt tracking
- **Settings Logging** ([@Francois], #3324) - Add logging and avoid silent skipping in settings

### Developer Experience

- **PR Body Template** ([@CharlVS], #3207) - Add PR_BODY.md helper file for CLI editing
- **SDK Submodule Management** ([@Francois], #3110) - Deterministic SDK roll script with path overrides
- **API Commit Hash Display** ([@DeckerSU], #3115) - Fix logging of apiCommitHash to output actual value instead of closure
- **Dependency Documentation** ([@Francois], #3128) - Ruby installation guide for iOS/macOS builds
- **Optional Verbose Logging** ([@Kadan], #3332, SDK #278) - Configurable logging levels for debugging

### Code Quality

- **Null Safety Improvements** ([@Cursor Agent], #3050) - Fixed null safety issues in UiDropdown widget
- **Type Safety** ([@Kadan], #3279, #3280) - Bound checking, non-nullable type tweaks, explicit enum mapping, defensive array access guards, cast num to int
- **Error Propagation** ([@smk762], #3328) - Propagate best_orders failures, avoid masking as no liquidity
- **Unused Code Cleanup** ([@Francois], #3225) - Remove unused widgets and update enum docs
- **Code Formatting** ([@CharlVS], #3251) - Run dart format on pubkey cache call-sites and taker delay
- **Logging Improvements** ([@Francois], #3328) - Add logging for errors not propagated to UI layer

## 📚 Documentation

- **SDK Changelog Cross-Linking** ([@CharlVS], #3172) - Link SDK PRs with short labels and mark SDK items in wallet changelog
- **Ruby Installation Guide** ([@Francois], #3128) - Added Ruby installation step for iOS and macOS builds
- **SDK Documentation** ([SDK#201](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/201)) - Document project and packages for pub.dev release

## ⚠️ Known Issues

- Full automated test suite remains triaged; manual QA recommended per `docs/MANUAL_TESTING_DEBUGGING.md`
- Some analytics events may require additional validation on specific platforms
- Large portfolios (>100 assets) may experience slower initial loading times during first activation

## 🙏 Contributors

This release includes contributions from 11 developers:

- @CharlVS
- @takenagain
- @ca333
- @smk762
- @DeckerSU
- @gcharang
- @TazzyMeister
- @naezith
- Cursor Agent (automated refactoring)

**Full Changelog**: [0.9.2...0.9.3](https://github.com/GLEECBTC/gleec-wallet/compare/0.9.2...0.9.3)

---

_For developers building with Komodo DeFi SDK: This release includes [komodo-defi-sdk v1.0.0-pre.1](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/releases) with breaking changes related to streaming APIs and caching behaviour. Review the [SDK changelog](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/blob/main/CHANGELOG.md) for migration guidance._

# Gleec Wallet v0.9.2 Release Notes

This release brings numerous improvements to wallet functionality, enhanced user experience, and critical bug fixes. Key highlights include HD wallet private key export, improved Trezor support, enhanced UI/UX throughout the application, and platform-specific optimizations.

## 🚀 New Features

- **HD & Offline Private Key Export** ([@CharlVS], #2982) - Export private keys from HD wallets for backup or use in other wallets, with pubkey unban functionality
- **Autofill Hints for Wallet Fields** ([@CharlVS], #3012) - Improved form filling experience with proper autofill support for wallet-related fields
- **Wallet-Enabled Coins in Add Assets** ([@takenagain], #2976) - View which coins are already enabled in your wallet directly from the "Add Assets" page
- **Copy Swap Order UUIDs** ([@smk762], #3002) - Easily copy swap order identifiers for reference and support
- **Hide Zero Balance Assets Persistence** ([@CharlVS], #2949) - Your preference to hide zero balance assets is now saved across sessions
- **Trading Duration Analytics** ([@CharlVS], #2931) - Track and analyze trading event durations for better insights
- **Missing Coins Support Link** ([@CharlVS], #2930) - Quick access to help for coins not yet supported in the wallet
- **Contact Details for Support** ([@CharlVS], #2807) - Improved support experience by requiring contact information for better follow-up
- **Geo Blocker API Integration** ([@CharlVS], #2893) - Enhanced compliance with region-based trading restrictions
- **Wallet Deletion** ([@CharlVS], #2843) - Safely remove wallets you no longer need
- **Cross-Platform Close Confirmation** ([@CharlVS], #2853) - Prevent accidental closure with confirmation dialog and proper KDF shutdown
- **Trezor SDK Migration** ([@takenagain], #2836) - Updated Trezor integration with latest SDK and RPC methods
- **User Address Prioritization** ([@takenagain], #2787) - Your addresses appear first in transaction history recipient lists
- **Git Commit Hash Display** ([@DeckerSU], #2796) - View the exact version commit hash in Settings › General
- **Copy Address Functionality** ([@smk762], #2690) - Easily copy addresses throughout the application

## 🎨 UI/UX Improvements

- **Show Full Pubkeys Where Copyable** ([@CharlVS], #2955) - Display complete public keys in areas where they can be copied
- **"Seed" to "Seed Phrase" Terminology** ([@smk762], #2972) - Consistent terminology update throughout login and import forms
- **Hide Log Export When Logged Out** ([@CharlVS], #2967) - Cleaner settings interface when not authenticated
- **Skeleton Loading for Address Lists** ([@CharlVS], #2990) - Better visual feedback while addresses are loading
- **EULA Formatting Improvements** ([@smk762], #2993) - Enhanced readability of End User License Agreement
- **Vertical Space Optimization** ([@CharlVS], #2988) - Reduced unnecessary vertical spacing for better content density
- **My Trades Tab Rename** ([@smk762], #2969) - Renamed "My Trades" tab to "Successful" for clarity
- **Trading History Filtering** ([@takenagain], #2856) - Combined search and filter functionality for better trading history navigation
- **Loading Messages for Wallets Page** ([@smk762], #2932) - Informative loading messages while wallet data loads
- **Trezor Login Loading Screen** ([@CharlVS], #2936) - Clear visual feedback during Trezor authentication
- **Portfolio Value Fix** ([@takenagain], #2883) - Corrected portfolio value display calculations
- **Custom Image Alignment** ([@smk762], #2873) - Improved alignment of custom images throughout the app
- **Multiple Asset Activation View** ([@CharlVS], #2860) - Enhanced interface for activating multiple assets simultaneously
- **Dropdown UI Consistency** ([@takenagain], #2849) - Standardized dropdown appearance and behavior
- **Close Dialog Button Accessibility** ([@smk762], #2852) - Improved accessibility for dialog close buttons
- **Swap Confirmation View Updates** ([@takenagain], #2847) - Clearer swap confirmation interface

## 🐛 Bug Fixes

- **ARRR Activation Crash** ([@takenagain], #3025) - Fixed application crashes when activating ARRR coin
- **ETH/AVX Transactions Visibility** ([@takenagain], #3033) - Restored missing ETH and AVX transactions in history
- **ETH Token Balance Display** ([@takenagain], #3033) - Fixed incorrect balance display for Ethereum tokens
- **Trezor Login Error Propagation** ([@CharlVS], #3019) - Proper error messages for Trezor authentication failures
- **HTTPS Asset URL Handling** ([@CharlVS], #2997) - Fixed loading of assets served over HTTPS
- **Coin Details Fiat Display** ([@smk762], #2995) - Corrected fiat value calculations on coin detail pages
- **HD Wallet Balance Calculation** ([@CharlVS], #3014) - Fixed balance aggregation for HD wallets
- **Mobile Hardware PIN Input** ([@CharlVS], #3011) - Resolved PIN entry issues on mobile devices
- **Transaction Fee Estimation** ([@takenagain], #3001) - Improved accuracy of fee calculations
- **App Name in Metadata** ([@CharlVS], #2981) - Consistent app naming across platforms
- **Notification Overlay Issues** ([@takenagain], #2975) - Fixed notification display problems
- **Wallet Name Update Persistence** ([@takenagain], #2963) - Wallet name changes now save correctly
- **Address Case Sensitivity** ([@CharlVS], #2959) - Proper handling of case-insensitive addresses
- **Send/Receive Tab Names** ([@smk762], #2935) - Fixed inconsistent tab labeling
- **P2P Price Issues** ([@takenagain], #2918) - Resolved peer-to-peer pricing discrepancies
- **HD Address Import Edge Cases** ([@takenagain], #2916) - Fixed issues with importing specific HD addresses
- **Receive Address Validation** ([@takenagain], #2914) - Improved address validation in receive flow
- **View-Only Hardware Wallet Login** ([@takenagain], #2910) - Fixed login issues for view-only hardware wallets
- **Multi-Path HD Address Display** ([@CharlVS], #2904) - Corrected display of addresses across multiple derivation paths
- **KDF Exit Shutdown** ([@takenagain], #2899) - Proper cleanup when closing the application
- **Address Comparison Logic** ([@CharlVS], #2898) - Fixed address matching for cross-chain comparisons
- **HD Address Visibility in Coin Details** ([@takenagain], #2906) - All HD addresses now visible in coin detail view
- **Web Pinch Zoom on Mobile** ([@smk762], #2880) - Disabled unwanted pinch zoom on mobile web
- **Selected Address Consistency** ([@takenagain], #2857) - Fixed issues with selected address persistence
- **Empty Wallet Creation** ([@takenagain], #2846) - Resolved problems creating wallets without initial coins
- **Hardware Wallet PIN Recovery** ([@CharlVS], #2845) - Fixed PIN entry after failed attempts
- **DEX Order Form Validation** ([@takenagain], #2844) - Improved order form field validation
- **Non-Hardware Wallet Login** ([@CharlVS], #2839) - Fixed standard wallet login regression
- **Orderbook Volume Display** ([@takenagain], #2827) - Corrected volume calculations in orderbook
- **Address Label Display** ([@takenagain], #2804) - Fixed missing address labels in various views
- **Protected Order Confirmation** ([@takenagain], #2790) - Fixed confirmation flow for protected orders

## 💻 Platform-Specific Changes

### Android

- **APK Build Fix** ([@CharlVS], #2798) - Resolved Android build issues for APK generation
- **Icon Corrections** ([@smk762], #2784) - Fixed incorrect app icons on Android devices

### Web

- **Bonsai Table Performance** ([@CharlVS], #2894) - Optimized table rendering for better web performance
- **Mobile Pinch Zoom Control** ([@smk762], #2880) - Better touch control on mobile browsers

### Desktop

- **Window Close Confirmation** ([@CharlVS], #2853) - Added confirmation dialog before closing application

## 🔧 Technical Improvements

- **Dependency Updates** ([@CharlVS], #3034) - Updated flutter_secure_storage to version 11.1.0
- **SDK Integration Updates** ([@CharlVS], #3036) - Critical KMD API pricing fix in SDK
- **CI Pipeline Improvements** ([@CharlVS]) - Enhanced continuous integration reliability
- **Test Coverage Expansion** ([@takenagain]) - Increased unit and integration test coverage

## ⚠️ Known Issues

- Some hardware wallet models may experience intermittent connection issues
- Large portfolios (>100 assets) may experience slower loading times
- Certain ERC-20 tokens may not display proper decimal precision

**Full Changelog**: [0.9.1...0.9.2](https://github.com/GLEECBTC/gleec-wallet/compare/0.9.1...0.9.2)

---

# Gleec Wallet v0.9.1 Release Notes

This is a hotfix release that addresses critical issues with Trezor hardware wallet login functionality.

## 🐛 Bug Fixes

- **Trezor Login Issues** - Fixed critical bugs in the Trezor hardware wallet login flow that were preventing users from accessing their wallets.

**Full Changelog**: [0.9.0...0.9.1](https://github.com/GLEECBTC/gleec-wallet/compare/0.9.0...0.9.1)

---

# Gleec Wallet v0.9.0 Release Notes

We are excited to announce Gleec Wallet v0.9.0. This release introduces HD wallet functionality, cross-platform fiat on-ramp improvements, a new feedback provider, and numerous bug fixes and dependency upgrades.

Under the hood, the app has undergone a major rewrite to migrate to our new KDF Flutter SDK. This also allows developers to quickly and easily build their own DeFi applications in a matter of hours instead of months. See the [SDK package](https://github.com/GLEECBTC/komodo-defi-sdk-flutter) for more information.

The codebase is now unified across all platforms, including web, desktop, and mobile. This change allows for more consistent development and easier maintenance.

## 🚀 New Features

- **HD Address Management & Seed Import** ([@naezith], #2510) - Support for hierarchical deterministic wallets, allowing users to manage multiple addresses from a single seed phrase.
- **HD Withdrawals + Breaking SDK Changes** ([@CharlVS], #2520) - Send funds from HD wallets with updated SDK requirements for enhanced security and features.
- **HD Withdrawals & Portfolio Overview** ([@CharlVS], #2530) - Integrated HD wallet withdrawals with portfolio tracking for better fund management.
- **Cross-platform Fiat On-Ramp** ([@takenagain], #170) - Purchase cryptocurrency with fiat currency across all supported platforms with an improved user experience.
- **Private Key Export** ([@naezith], #183) - Safely export your private keys for backup or use in other compatible wallets.
- **KDF SDK Integration Part 1** ([@takenagain], #177 (and many more)) - Enhanced security with new key derivation functions in the SDK for better wallet protection.
- **System Time Check with World Time APIs** ([@takenagain], #182) - Prevents transaction issues by ensuring your device clock is properly synchronized with global time standards.
- **Custom Token Import** ([@takenagain], #2515) - Import custom tokens with an improved user interface and business logic implementation.
- **Multi-address Faucet Support** ([@TazzyMeister], #2533) - Request test coins to multiple addresses from supported faucets for development and testing.
- **Reworked Unauthenticated Assets List** ([@CharlVS], #2579) - View available assets without logging in for better first-time user experience.
- **HD Wallet Address Selection for Fiat Onramp** ([@takenagain], #2570) - Choose specific HD wallet addresses when purchasing crypto with fiat.
- **Internal Feedback Provider** ([@CharlVS], #2586) - Submit feedback directly from within the app for improved user support and issue reporting.
- **SDK Password Update Migration** ([@CharlVS], #2580) - Seamless migration to updated password handling in the SDK for better security.

## 🎨 UI/UX Improvements

- **Aligned Column Headers** ([@TazzyMeister], #2577) - Consistent table layouts throughout the application for better readability.
- **Localization of Hardcoded Strings** ([@TazzyMeister], #2587) - More text is now translatable, improving experience for international users.
- **Add Assets Coin List Loading Speed** ([@takenagain], #2522) - Faster coin list loading when adding new assets to your portfolio.
- **Wallet Only Logout Confirmation** ([@naezith]) - Additional confirmation step when logging out to prevent accidental data loss.
- **Updated Segwit Badges** ([@takenagain], #2545) - Clearer visual indicators for SegWit-compatible addresses and transactions.
- **Hide Incorrect Time Banner in Wallet-only Mode** ([@CharlVS]) - Removes unnecessary time warnings when operating in wallet-only mode.
- **Wallet-only Mode Fixes** ([@CharlVS]) - Various improvements to the wallet-only experience for users who prefer simplified functionality.

## ⚡ Performance Enhancements

- **Coin List Loading Speed** ([@takenagain], #2522) - Significantly faster loading of coin lists throughout the application.
- **System Health Check Time Providers** ([@takenagain], #2611) - Optimized time synchronization checks for better performance and reliability.

## 🐛 Bug Fixes

- **Fiat Onramp Banxa Flow** ([@takenagain], #2608) - Resolved issues with Banxa integration for smoother fiat-to-crypto purchases.
- **DEX Buy Coin Dropdown Crash** ([@takenagain], #2624) - Fixed application crashes when using the coin selection dropdown in DEX buy interface.
- **NFT v2 HD Wallet Support** ([@takenagain], #2566) - Added compatibility for NFTs with hierarchical deterministic wallets.
- **Withdraw Form Validation and UI Updates** ([@takenagain], #2583) - Improved form validation and user interface in the withdrawal process.
- **Coins Bloc Disabled Coins Reactivation** ([@takenagain], #2584) - Fixed issues with reactivating previously disabled coins in the portfolio.
- **Transaction History Switching** ([@takenagain], #2525) - Corrected problems when viewing transaction history across different coins.
- **Router Frozen Layout** ([@takenagain], #2521) - Fixed navigation issues that caused the UI to freeze in certain scenarios.
- **Receive Button UI Fix** ([@CharlVS]) - Resolved display issues with the receive payment button.
- **Coin Balance Calculation** ([@takenagain]) - Fixed incorrect balance calculations for certain coins and tokens.
- **Electrum Activation Limit** ([@takenagain], #195) - Addressed limitations with activating multiple Electrum-based coins.
- **Trezor HD Wallet Balance Status** ([@takenagain], #194) - Fixed balance display issues for Trezor hardware wallets using HD addresses.
- **Zero Balance for Tokens Without Parent Coin Gas** ([@naezith], #186) - Corrected balance display for tokens when parent chain coins are unavailable for gas.
- **LP Tools UX** ([@takenagain], #184) - Improved user experience for liquidity provider tools and functions.
- **Log Export Cross Platform** ([@takenagain], #174) - Fixed log exporting functionality across all supported platforms.
- **OnPopPage Deprecated** ([@naezith], #172) - Updated code to remove usage of deprecated navigation methods.
- **DEX Swap URL Parameter Handling** ([@naezith], #162) - Fixed issues with DEX swap links and URL parameter processing.
- many more minor fixes across the codebase.

## 🔒 Security Updates

- **Dependency Upgrades for Security Review** ([@CharlVS], #2589) - Updated libraries and dependencies to mitigate potential security vulnerabilities.

## 💻 Platform-specific Changes

### iOS & macOS

- **Pod File Lock Updates** ([@takenagain], #2594) - Updated dependency management for iOS and macOS builds to ensure compatibility.

### Web/Desktop/Mobile

- **Build Workflow Upgrades** ([@takenagain], #2528, #2531) - Improved build processes for all platforms for more reliable releases.
- **Docker and Dev Container Build Fixes** ([@takenagain], #2542) - Fixed issues with Docker and development container environments.

## ⚠️ Breaking Changes

- **HD Withdrawals** require the latest SDK version (#2520, #2530) - Users must update to the latest SDK to use HD wallet withdrawal functionality.
- **Custom Token Import asset constructor** changed (#2598) - Developers using the API for custom token imports need to update their implementation.
- **Unified Codebase** for all platforms. This means that the codebase is now shared across all platforms, including web, desktop, and mobile. This change allows for more consistent development and easier maintenance. NB: Non-web users should back up their wallets before updating to this version, as wallet data is not migrated automatically. Users can restore their wallets using the seed phrase.

**Full Changelog**: [0.8.3...0.9.0](https://github.com/GLEECBTC/gleec-wallet/compare/0.8.3...0.9.0)
