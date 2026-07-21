---
name: gleec-gnosis-pay-integration
description: Build or review Gleec's Gnosis Pay card integration, including mock-first repositories, SIWE and Safe signing boundaries, API-owned Safe deployment, card lifecycle UI, PSE isolation, and partnership rollout. Use for any Gnosis Pay card, Safe, KDF signer, withdrawal, daily-limit, card-detail, or webhook work.
---

# Gleec Gnosis Pay Integration

Read `references/integration-boundaries.md` before changing a Gnosis card flow.

1. Keep Gnosis API behavior behind `GnosisPayRepository`; widgets and BLoCs consume typed domain models only.
2. Safe deployment always begins with Gnosis `POST /api/v1/safe/deploy` and status polling. Never deploy or configure a Safe in Flutter, the SDK, or KDF.
3. Keep KDF limited to local key selection, verified Safe/Delay association, and EIP-191/EIP-712 signing.
4. Inspect and display an immutable typed-data intent before invoking KDF. KDF must independently reject unauthorized modules and unsupported calldata.
5. Model mock behavior with deterministic scenarios and the same domain contract as live behavior. Reject mock mode in production builds.
6. Render PAN/CVV/PIN only through `CardSecureElementGateway`; never place them in BLoC state, logs, analytics, persistence, screenshots, or golden fixtures.
7. Treat PSE mTLS and webhook receipt as backend-only live concerns.
8. Cover authentication expiry, KYC resubmission, Safe deployment failure, card lifecycle, destructive controls, and delayed withdrawal/limit execution.
