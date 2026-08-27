# TRON GasFree V0 release runbook

V0 remains disabled unless every gate below passes for the exact application
artifact being promoted. Never place provider credentials or funded-wallet
secrets in this repository or CI logs.

## Immutable artifact gate

- KDF source commit is exactly
  `997332e5d6b0c5ca471aa7dc9727a7be96938ae2`.
- Every declared native/WASM archive reports that full commit and matches the
  SHA-256 checksum recorded in `app_build/build_config.json`.
- Android arm64-v8a and armeabi-v7a archives are present; the stale
  `43603a5…` markers are a release failure.
- The release build exposes `gasless::account_status`, GasFree withdrawal,
  submit, and trace on every supported platform.

## Nile canary

Use one empty canonical primary wallet and one funded canonical wallet.

1. Enable GasFree send, Receive, legacy-status Receive, provider configuration,
   and the short-lived control document only in the protected canary build.
2. Confirm Standard Receive appears before the GasFree status completes.
3. Confirm the empty wallet reaches ready with a stable KDF custody address,
   zero on-chain balance, positive transfer/activation fees, and working QR/copy.
4. Fund the GasFree address and confirm the KDF on-chain balance updates without
   an app restart.
5. Create a normal and `max: true` preview; verify native fallback is false and
   the preview—not account status—supplies the approved amount and fee.
6. Submit, restart the app while pending, reconcile the durable request/trace,
   and verify exact on-chain source, destination, token, amount, and fee.
7. Exercise provider outage, malformed status, remote disable, wallet switch,
   unknown submit acceptance, and final failure. QR/copy must revoke while the
   last KDF custody balance and Standard address remain visible. Confirm that
   the wallet makes no independent custody/provider REST request and renders
   unknown spendable, frozen, or fee values as `—`, never zero.

## Mainnet canary and rollout

1. Recheck canonical mainnet USDT contract, provider enrollment, positive fee
   profile, pinned provider configuration, and remote-control binding.
2. Execute the approved small-value end-to-end canary with the exact release
   artifact; record transaction and trace evidence outside the repository.
3. Obtain named Product/Design approval for the screenshot matrix in
   `TRON_GASFREE_V0_UI_HANDOFF.md`.
4. Roll out the small cohort with the default-on V0 and V1 switches. The legacy
   adapter takes precedence until explicit V1 evidence is returned. Use either
   switch as an emergency build-time kill switch if required.
5. Monitor privacy-safe receive/status and transfer lifecycle events. Disable
   the remote receive document immediately for status-shape failures, provider
   enrollment drift, unexpected zero fees, or elevated pending duration.

Repeat both canaries after any KDF artifact, provider, token contract, network,
remote-control schema, or GasFree policy change.
