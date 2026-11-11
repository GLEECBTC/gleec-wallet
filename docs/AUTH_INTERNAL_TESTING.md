# Instant wallet onboarding — internal testing

The PR's pinned handoff records the exact preview URL, source commit, CI run and
artifact links. Use that handoff for invitations; previews expire after seven
days. A new build must pass its checks and publish matching identity before the
handoff is moved.

## What the team should test

Use a fresh browser profile and disposable, unfunded wallets. Create from the
opening screen without typing a name or password. Check the displayed protection
status, optional password-manager offer, cold return, cancel/retry, wallet switch,
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

## Completed engineering checks for this candidate

- Clean-checkout app suite: **4,494 passed, 26 skipped**, zero failures. The 22
  Linux-only cases run on Linux CI; four existing skips remain documented.
- Whole-checkout analysis: **zero errors**, 55 existing warnings and 2,143
  informational notices. Changed authentication files have scoped analysis.
- SDK authentication: **196 passed**; SDK replay fixture corrections: **six
  passed**, with **225 passed/four opt-in skips** in the complete replay round.
- Browser release/lifecycle: instant creation, full process restart, passkeys,
  cross-tab invalidation, corrupt ciphertext, provider loss and 29/31-second
  background returns with frozen timers pass on the compiled app.
- Recovery: generated-password phrase confirmation, requested-only browser
  export, independent phrase/file restoration and secret-diagnostic canaries
  pass. Passkey replacement and clean-origin missing-data cases also pass.
- Browser-only protocol suite: 82 cases pass through the main CI aggregator.
- CI performs the same unfunded browser acceptance before publishing the PR
  preview, and publishes source/SDK/bundle identity afterward.

These local results bind to the isolated integration source. The pinned PR
handoff adds hosted CI outcomes and the independently verified served bundle;
local results alone do not mark a hosted build accepted.

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
