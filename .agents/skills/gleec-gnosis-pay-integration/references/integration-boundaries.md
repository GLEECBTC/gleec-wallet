# Integration boundaries

## Ownership

| Concern | Owner |
| --- | --- |
| SIWE nonce/challenge, onboarding, KYC, Safe deployment/status, cards, orders, transactions | Gnosis Pay API adapter |
| Private-key selection, registered Safe/Delay validation, EIP-191/EIP-712 signature | KDF via Flutter SDK |
| Workflow ordering and typed domain conversion | `GnosisCardCoordinator` and repositories |
| Sensitive card rendering | PSE-backed `CardSecureElementGateway` |
| mTLS ephemeral tokens and webhook verification | Gleec backend |

## Required sequence

1. Authenticate with SIWE.
2. Complete registration and KYC.
3. Request API-owned Safe deployment and poll to a valid integrity state.
4. Register the returned Safe with KDF; re-register after KDF restart.
5. For signed actions, fetch typed data, normalize and decode it, compare it to the requested action, show the intent, then sign and submit the exact payload.

## Security invariants

- Gnosis Chain is chain ID 100 for card-account operations.
- A ModuleTx verifier must be the enabled official Delay proxy for the registered Safe and the owner must be enabled on that Delay.
- Withdrawal calldata must represent a CALL for ERC-20 transfer or native value transfer.
- Daily-limit calldata must pass through the Safe-specific Bouncer to the official Roles modifier's `setAllowance` function.
- Mock fixtures may use synthetic addresses and digits but must never be confused with live data or enabled in production.

Authorities: https://docs.gnosispay.com/llms.txt and https://github.com/gnosispay/account-kit.
