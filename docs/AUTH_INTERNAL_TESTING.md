# Instant wallet onboarding — internal testing

The PR's pinned handoff records the exact preview URL, source commit, CI run and
artifact links. Use that handoff for invitations; previews expire after seven
days. A new build must pass its checks and publish matching identity before the
handoff is moved.

## What the team should test

Use a fresh browser profile and disposable, unfunded wallets. Create from the
opening screen without typing a name or password. Check the displayed protection
status, inline optional passkey/device setup, the provider’s save prompt, cold
return, cancel/retry, wallet switch,
rename, persistent sign-out, recovery-phrase confirmation and encrypted export.
Confirm 29-second/31-second background returns and immediate locking. Normal
transactions retain their ordinary review and confirmation flow.

Only enter recovery words that belong to the empty test wallet into the app.
Never include words, passwords, PINs, private keys or secret-screen images in an
issue, chat or recording. A passkey or saved password alone is not recovery on a
clean browser/device.

## Access and build identity

The app PR is stacked on the reviewed Solana branch to give an authentication-only
diff while exercising the combined SDK. The immutable SDK pin is
`34faf005b2e092419d0cb12b84f21b02a6c7f0d6`. Its authentication package source is the
reviewed `cf69f461` prerequisite now opened in [SDK #445](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/445).
The SDK merge safeguard remains enforced for production promotion.

The preview publishes `/auth-test-build.json`, containing the source head,
actual PR merge, SDK and bundle hashes, CI run, source-cleanliness result and an
explicit `production_approved=false` marker. CI retains the same public records
in `onboarding-browser-identity`, so the served bundle can be checked against
the tested build independently. Tester reports should name the
preview URL, source head, device/OS/browser/provider and pass/fail.

## Engineering validation and exact candidate

The pinned PR handoff is the authoritative record of this candidate’s exact
source, full app/SDK results, preview identity, rollback evidence and installer
checks. Do not carry counts from an older candidate into a new invitation.
CI runs the complete production-GasFree unit aggregator, browser protocol tests,
compiled unfunded browser journeys and native builds. It also retains public
light/dark phone/wide setup-state renders in `onboarding-ui-states`.

The UX follow-up removes the application Save action and recommends optional
passkey setup directly in the wallet. The provider handles saving confirmation;
automatic saving may be unavailable and autofill requests do not confirm saving.
Test cancellation separately from declined enrollment. Passkey setup creates one
passkey and uses it once to verify unlock. A second unlock request after that
verification is a regression. Providers control their own sheets and consent
steps. A returning enrolled wallet gets at most one automatic challenge.
No personal password is required after phrase backup. The
[journey review](AUTH_PASSKEY_UX_REVIEW.md) records the duplicate-prompt root cause,
competitor research and acceptance criteria.

Engineering evidence includes fail/restart provisioning, password rotation,
wallet-bound action invalidation, suspended-clock lock timing, full-process
browser return, cross-tab protection, missing/corrupt data and independent
phrase/file restoration. Virtual authenticators and emulators establish those
software paths; they do not certify hardware protection or actual providers.
See [the state reference](design/authentication/README.md) and
[the research record](design/authentication/UX_RESEARCH.md).

## Android installation

The `Installable onboarding Android test build` workflow publishes
`gleec-onboarding-internal-android` with an APK and a public provenance JSON.
It is a release-mode Flutter build, explicitly signed for development, labelled
**Gleec Wallet Internal**, with application ID
`com.gleec.gleecdex.onboardinginternal`. It has its own app data and cannot replace
the production application's package. CI checks that application ID and scans
the actual APK before upload. Normal release builds retain their signing rules.

Install only the artifact linked from the accepted PR run. Start with an empty
test wallet; build-to-build development signing may require a fresh install.
Recovery/signing continuity for the actual production identity remains a separate
acceptance check. Never import a funded personal wallet into this internal app.

## Desktop installation

The desktop CI archives use the regular application namespace. Open them only
in a disposable OS account or virtual machine with no personal wallet data.
Use the exact archive linked in the pinned handoff. A successful build or
ad-hoc signature does not certify Keychain, Touch ID or Windows Hello behavior;
trusted signing and real provider checks remain part of the device round.
The unsigned iOS archive is a build check, not an installable team distribution.

## Device round owned by internal testers

- Mac/iPhone/iPad: install a trusted signed build, then check actual Keychain,
  Touch ID/Face ID/passcode fallback, app-switcher privacy and password managers.
  Mac signing team/profile availability remains a hands-on setup task.
- Android: strong biometric plus correct PIN, cancellation/lockout, enrollment
  changes and Keystore invalidation. Cover Android 9/10 before enabling those
  older enrollment paths for wider release.
- Windows: Hello, DPAPI account isolation and actual OS lock notifications.
- Browsers: real Apple Passwords/Google/third-party providers, actual PRF
  enrollment, provider loss and storage eviction. Virtual authenticators verify
  protocol logic and cannot certify these providers.
- Accessibility: VoiceOver/TalkBack, keyboard navigation, large text and focus
  returning from system dialogs; capture images only on nonsecret screens.

The precise steps are in [AUTH_RELEASE_GATES.md](AUTH_RELEASE_GATES.md). Device
acceptance is the purpose of this internal round; completion is required before
wider release. Production hosting/edge activation and historical CI-log removal
remain separate decisions.
