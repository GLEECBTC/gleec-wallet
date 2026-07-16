# Mock-first Gnosis Pay card architecture

## Milestone boundary

This milestone provides the complete Gnosis Pay onboarding experience through
deterministic adapters. It has no live Gnosis connection and adds no runtime
backend. The existing `/card` route and post-onboarding dashboard remain the
entry and destination for the flow.

Mock mode is debug-only. The production default is `disabled`; a production
build that requests `mock` rejects it and remains disabled, while an
unconfigured `live` mode fails closed. Run the happy path with:

```sh
flutter run \
  --dart-define=GNOSIS_CARD_MODE=mock \
  --dart-define=GNOSIS_CARD_SCENARIO=happyPath \
  --dart-define=GNOSIS_CARD_COIN=GNO
```

The mock owns onboarding and card API responses, but it does not mock signing.
SIWE and Safe registration use `KdfSmartAccountSigner` against genuine KDF.
For local KDF signing on macOS/Linux, run
`test_harness/gnosis_card/link_local_kdf.sh` before Flutter. The wallet must
have GNO/KDF ready; unavailable or empty KDF responses are actionable failures,
and there is no synthetic signer or runtime fallback.

## Onboarding sequence and progress

The native flow follows the Gnosis Pay contract in this order:

1. Discover Card and authenticate with a SIWE challenge signed by KDF.
2. Register with email, load the current terms, and accept every outstanding
   term and version. The full legal documents open externally.
3. Launch Sumsub KYC externally and refresh the Gnosis user status after return.
4. Load the source-of-funds questions and submit all required answers together.
5. Enter and confirm an E.164 phone number, request a six-digit OTP, and verify
   it. Mock mode labels `123456` as the demo code and enforces a 60-second
   resend cooldown.
6. Ask the Gnosis Pay API to deploy and configure the user's Safe, poll its
   status, verify its configuration and integrity, then register the verified
   Safe/Delay association with KDF.
7. Select a virtual or physical card. A virtual card is issued immediately; a
   physical card continues through address, order, simulated payment, card
   creation, and PIN setup.

`GnosisOnboardingProgress` is derived from independent server-shaped facts,
not an ordinal step or a client-side `advance()` counter. Registration, terms,
KYC, source-of-funds, phone, Safe, card, and pending-order state each determine
the next incomplete action. Refreshing after an external flow or reopening
`/card` re-derives the action and skips completed work. The deterministic
repository lives for the lifetime of the root dependency graph, so navigation
does not reset progress; a full process restart intentionally does. If the
active KDF owner changes, the mock clears the previous user's in-memory facts
before authenticating the new owner, preventing cross-owner card or Safe state.

The UI summarizes progress as four milestones rather than a numbered stepper:

| Milestone | Completion criteria |
| --- | --- |
| Account | SIWE session, registration, and all current terms complete |
| Identity | KYC approved, source of funds answered, and phone verified |
| Card account | API-owned Safe configured, integrity accepted, and KDF registered |
| Card | Virtual card active or physical-card order and PIN flow complete |

Submission events are explicit and typed. Duplicate submissions are dropped,
KYC and dashboard refreshes use latest-result semantics, and Safe plus
physical-order transitions are serialized. Errors remain on the active step
with the relevant retry, reopen, reauthenticate, reset, or support action.

## Ports and ownership

| App-owned port | Mock adapter | Live replacement |
| --- | --- | --- |
| `GnosisPayRepository` | `DeterministicGnosisPayRepository` | JWT-authenticated Gnosis HTTP adapter |
| `SmartAccountSigner` | `KdfSmartAccountSigner` | Same adapter against a released fixed KDF/SDK |
| `ExternalFlowLauncher` | HTTPS-only external-tab launcher for mock URLs | Platform browser/deep-link integration |
| `CardOrderPaymentGateway` | Explicit debug-only simulated EURe payment | Partnership-approved payment integration |
| `CardSecureElementGateway` | Synthetic provisioning handoff | Gleec-hosted PSE frame/native surface |
| `GnosisCardCoordinator` | Workflow facade | Unchanged |
| `GnosisCardDependencies` | Disabled/mock factory | Partnership-approved live bindings |

`GnosisPayRepository` owns SIWE challenges and submission, registration,
terms, KYC integration/status, source-of-funds questions, phone challenges,
user-scoped Safe deployment/configuration/reset, card products, orders, and
issuance. It exposes typed domain values only; widgets and BLoCs never construct
raw Gnosis request maps.

The coordinator orders the workflow and converts recoverable failures into
step-local recovery. The signer owns only local key selection, verified
Safe/Delay registration, and EIP-191/EIP-712 signing. Safe deployment and
module configuration always start with the Gnosis Pay API and never occur in
Flutter, the Flutter SDK, or KDF.

## External-only surfaces

Third-party content is not recreated in Flutter. Native screens expose launch,
return, status, and recovery controls for these boundaries:

- Terms and privacy documents open in an external browser or tab. Flutter
  renders the dynamically returned title, version, link, and acceptance box.
- Sumsub owns all KYC document capture and review UI. Flutter launches or
  relaunches it, refreshes status on return, and displays the resulting state.
- Support content opens externally for final rejection, manual review, or an
  unrecoverable onboarding failure.
- PSE owns PIN entry. Flutter hands off an opaque provisioning handle and
  displays only waiting, returned, cancelled, and recoverable error states.

The native flow must not imitate third-party forms or retain data collected by
those surfaces.

## KYC and Safe state contracts

The mock exposes every documented Gnosis Pay KYC status:

| KYC status | Native behavior |
| --- | --- |
| `notStarted` | Offer to launch KYC |
| `documentsRequested` | Explain that documents are required and reopen KYC |
| `pending` | Show submitted/waiting state and allow status refresh |
| `processing` | Show processing state and allow status refresh |
| `approved` | Derive and show the next incomplete onboarding action |
| `resubmissionRequested` | Explain what can be retried and relaunch KYC |
| `rejected` | Show final rejection and launch support |
| `requiresAction` | Show manual-review state and launch support |

Safe deployment is also server-shaped. `POST /api/v1/safe/deploy` returns
`accepted`; `GET /api/v1/safe/deploy` is then the source of truth and returns
`not_deployed`, `processing`, `ok`, or `failed`. A polling `timeout` is a typed
client outcome rather than an API deployment status. Flutter can retry polling
or request the API reset operation, but it never invents an address or
deploys/configures contracts. After deployment, `GET /api/v1/safe-config` must
report a configured account.

Integrity is a separate gate. Account Kit values `Ok (0)` and
`DelayQueueNotEmpty (7)` are valid because both indicate that the expected
modules are deployed; every other value blocks registration and issuance.
Only after integrity succeeds does the coordinator register the returned Safe
and official Delay association with KDF. Because the KDF registry is
session-scoped, initialization revalidates and re-registers an existing Safe
after a KDF restart. An invalid mock configuration remains invalid until the
explicit reset operation begins a new deployment generation.

## Card issuance

Virtual cards use the simplified Gnosis flow: no address, payment, or PIN is
required, and successful issuance produces an immediately active card.

The mocked physical-card branch preserves the API order:

1. Collect a shipping address in the same country as the verified KYC address.
2. Review the address, embossed name, and EURe quote, then create an order in
   `PENDINGTRANSACTION`.
3. Clearly label and run a simulated EURe payment. No asset transfer, signed
   transaction, broadcast, or other movement of funds occurs.
4. Attach the synthetic receipt/transaction hash to the order and confirm
   payment, moving the mock order to `READY`.
5. Create the physical card, retain only its opaque provisioning handle, and
   hand that handle to the PSE boundary for initial PIN setup.
6. Mark the card ordered after PIN setup returns successfully.

The domain preserves the API-shaped order statuses `PENDINGTRANSACTION`,
`TRANSACTIONCOMPLETE`, `CONFIRMATIONREQUIRED`, `READY`, `CARDCREATED`,
`CANCELLED`, and `FAILEDTRANSACTION`. The happy path moves from
`PENDINGTRANSACTION` to `READY` and then `CARDCREATED`; intermediate and
terminal states remain representable for resume and recovery. Cancellation is
offered only when the current status is in the API's cancellable set:
`PENDINGTRANSACTION`, `TRANSACTIONCOMPLETE`, `CONFIRMATIONREQUIRED`, or
`FAILEDTRANSACTION`.

The adapter preserves entered address/review data on retryable failures. It
rejects any invalid transition. Editing a cancellable order returns to the
prefilled shipping form; abandoning it clears the selected product and returns
to card selection (or an existing card dashboard). Cancelling the external PIN
surface does not discard an already created card; reopening `/card` resumes PIN
setup.

PAN, CVV/CVC, PIN, and PIN-entry values never enter repository or BLoC state,
logs, persistence, analytics, previews, screenshots, or fixtures. Opaque PSE
provisioning handles are cleared after successful use. A live PSE adapter must
keep mTLS and webhook receipt on a Gleec backend.

## Deterministic scenarios

Set `GNOSIS_CARD_SCENARIO` to one of these values:

| Scenario | Deterministic behavior and recovery |
| --- | --- |
| `happyPath` | Completes either virtual or physical onboarding |
| `offline` | Fails the relevant request once; retry succeeds after the offline message |
| `expiredSession` | Expires authentication once; SIWE reauthentication resumes derived progress |
| `invalidOtp` | Rejects a phone code once; corrected demo code succeeds without losing the phone number |
| `kycResubmission` | Returns `resubmissionRequested`; relaunch and refresh then approve |
| `kycRejected` | Returns final `rejected`; only the external support action is offered |
| `kycRequiresAction` | Returns `requiresAction`; refresh and external support remain available |
| `deploymentFailure` | Safe deployment fails once; API reset/retry then succeeds |
| `safeIntegrityFailure` | Rejects Safe integrity once; reset and redeploy then succeeds |
| `paymentFailure` | Simulated physical-card payment fails once; retry reuses order and form data |
| `issuanceFailure` | Card creation/issuance fails once; retry resumes from the pending product or order |

The legacy `kycExpired` value maps to `kycResubmission` for configuration
compatibility. Recoverable scripts fail once and only succeed after the
corresponding recovery action. Rejection/manual-review scripts do not silently
advance.

## UI and verification

The feature uses the existing Gleec theme and UI kit. Native onboarding screens
adapt from a single-column phone layout to a constrained/two-column desktop
layout, preserve logical focus order, expose semantic labels and status
announcements, tolerate large text, and keep primary actions keyboard
accessible. Interactive Widget Previewer entries cover every native step and
representative blocked states at phone/light and desktop/dark sizes; external
content is never included in previews.

Repository/coordinator, BLoC, widget, and semantics specifications document
the intended regression coverage, including both card branches, derived resume,
duplicate submissions, all KYC/Safe states, and every deterministic scenario.
Per the repository guidance, the currently failing unit and integration test
suites are not run for this milestone. Verification consists of formatting
changed Dart files, `flutter analyze`, visual inspection of previews, and a
thorough static review of state transitions and sensitive-data boundaries.

Primary references:

- [Onboard users to Gnosis Pay](https://docs.gnosispay.com/onboarding-flow)
- [Authentication](https://docs.gnosispay.com/auth)
- [Create virtual cards](https://docs.gnosispay.com/cards/create-virtual-cards)
- [Create physical cards](https://docs.gnosispay.com/cards/create-physical-cards)
- [Card order state transitions](https://docs.gnosispay.com/cards/card-order-state-transitions)
- [Deploy and set up a Safe](https://docs.gnosispay.com/api-reference/safe-management/deploy-and-setup-a-safe)
- [PSE integration](https://docs.gnosispay.com/cards/pse-integration)
- [Gnosis Pay Account Kit](https://github.com/gnosispay/account-kit)
