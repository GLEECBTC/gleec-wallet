# Mock-first Gnosis Pay card architecture

## Milestone boundary

This milestone has no live Gnosis connection and adds no runtime backend. The
app is code-first and deterministic in mock mode. Its production default is
`disabled`; a production build that requests `mock` rejects it and remains
disabled, while unconfigured `live` mode fails closed.

Run mock mode with:

```sh
flutter run \
  --dart-define=GNOSIS_CARD_MODE=mock \
  --dart-define=GNOSIS_CARD_SCENARIO=happyPath \
  --dart-define=GNOSIS_CARD_COIN=GNO
```

Available scenarios are `happyPath`, `deploymentFailure`, `kycExpired`,
`offline`, and `expiredSession`.

For genuine local KDF signing on macOS/Linux, run
`test_harness/gnosis_card/link_local_kdf.sh` before Flutter. It builds
`mm2_bin_lib` from the isolated KDF worktree and places an ignored symlink in
the wallet root, which the SDK resolves before its bundled library.

## Ports and replacement points

| App-owned port | Initial adapter | Live replacement |
| --- | --- | --- |
| `GnosisPayRepository` | `DeterministicGnosisPayRepository` | JWT-authenticated Gnosis HTTP adapter |
| `SmartAccountSigner` | `KdfSmartAccountSigner` | Same adapter against a released fixed KDF/SDK |
| `CardSecureElementGateway` | `SyntheticSecureElementGateway` | Gleec-hosted PSE frame/native surface |
| `GnosisCardCoordinator` | Workflow Facade | Unchanged |
| `GnosisCardDependencies` | Disabled/mock factory | Partnership-approved live bindings |

The repository owns authentication challenges, terms/KYC state, Safe
deployment status, issuance, card lifecycle, controls, and submission. The
signer owns only EIP-191 and EIP-712 KDF calls. The coordinator composes them;
it never constructs raw RPC or API maps.

## Deployment and signing sequence

1. The repository creates a SIWE challenge.
2. `KdfSmartAccountSigner` performs genuine KDF EIP-191 signing. Empty or
   unavailable KDF responses fail; there is no runtime fallback.
3. The mock repository advances terms, registration, phone/source-of-funds,
   and KYC.
4. The repository models Safe deployment as
   `accepted → processing → ok/failed` and alone returns the fixture address.
5. The coordinator validates integrity and only then calls
   `smart_account::register`.
6. The repository normalizes and prepares Account Kit `ModuleTx` payloads.
   The SDK rejects a chain or Delay mismatch against the API-owned deployment,
   then Flutter shows the decoded intent.
7. User confirmation invokes KDF `smart_account::sign_typed_data`; the signed
   response is checked against the prepared owner and Delay before submission.
8. The repository models the operation's cooldown and temporary-freeze state.

KDF registry state is session-scoped. `GnosisCardCoordinator.initialize`
revalidates and re-registers a previously deployed Safe after KDF restart.

## UI and platform behavior

Card is a first-class route at `/card`. Narrow navigation is Wallet, Swap,
Card, Fiat, More; wide navigation retains all destinations. The feature uses
the existing Manrope typography and semantic Flutter theme colors rather than
speculative Gnosis partnership branding.

The layout switches from a stacked phone/tablet view to a two-column desktop
view at 900 logical pixels. It uses adaptive controls, keyboard-focusable
Material actions, tabular monetary figures, large touch targets, explicit
offline/expired recovery, and no required motion. The same Dart UI runs on
Android, iOS, macOS, Windows, Linux, and web.

Card number, CVC, and PIN are created only inside the secure-element gateway's
screenshot-sensitive dialog. They are absent from card domain models, BLoC
state, repository logs, persistence, and analytics. A live PSE adapter must
keep mTLS and webhook receipt on a Gleec backend; Flutter may host the isolated
surface but must not deserialize sensitive values.

## Verification surfaces

- SDK official-shape normalization, calldata decode, action comparison, and
  payload-digest stability tests.
- Repository/coordinator tests for deployment ownership, both signing intents,
  delayed states, failure paths, and KDF re-registration.
- BLoC fail-closed tests and widget tests at phone and desktop widths.
- Flutter Widget Previewer entries for phone/light and desktop/dark states.
- `test_harness/gnosis_card` Anvil fixtures matching KDF's supported official
  Delay and Roles proxy identities, ownership graph, and exact Account Kit
  v4.10.1 Bouncer runtime.

Primary references:

- [Deploy and set up a Safe](https://docs.gnosispay.com/api-reference/safe-management/deploy-and-setup-a-safe)
- [Authentication](https://docs.gnosispay.com/auth)
- [Virtual cards](https://docs.gnosispay.com/cards/create-virtual-cards)
- [Physical cards](https://docs.gnosispay.com/cards/create-physical-cards)
- [Withdraw from a Safe](https://docs.gnosispay.com/gp-onchain/withdraw-funds-from-safe)
- [PSE integration](https://docs.gnosispay.com/cards/pse-integration)
- [Gnosis Pay Account Kit](https://github.com/gnosispay/account-kit)
