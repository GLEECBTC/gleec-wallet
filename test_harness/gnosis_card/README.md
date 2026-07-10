# Local Gnosis card contract harness

This test-only harness supplies the on-chain half of mock card mode. The in-app
`DeterministicGnosisPayRepository` remains the mock API and is the only layer
that returns the Safe address. The harness never represents wallet-side Safe
deployment.

It starts Anvil on chain ID 100 and installs:

- a Safe-compatible fixture at `0x1111…1111`;
- exact Zodiac minimal-proxy runtimes for the official Delay and Roles
  mastercopies;
- the exact Account Kit v4.10.1 Bouncer runtime with Safe, Roles, and selector
  immutables bound to the fixtures;
- Delay storage bound to the chosen KDF owner and the fixture Safe;
- a Safe-specific Bouncer and ERC-20 target used by shared payload vectors.

Run it with:

```sh
docker compose -f test_harness/gnosis_card/docker-compose.yml up -d
OWNER=0xYOUR_KDF_GNO_ADDRESS test_harness/gnosis_card/setup_fixtures.sh
```

Configure the locally patched KDF GNO activation to use
`http://127.0.0.1:8545`. On macOS or Linux, build and link the local KDF
dynamic library so the SDK loads the patch ahead of its bundled library:

```sh
test_harness/gnosis_card/link_local_kdf.sh
```

Then launch Flutter with:

```sh
flutter run -d macos \
  --dart-define=GNOSIS_CARD_MODE=mock \
  --dart-define=GNOSIS_CARD_SCENARIO=happyPath \
  --dart-define=GNOSIS_CARD_COIN=GNO
```

The normal card flow proves SIWE signing, API-owned deployment polling, KDF
registration, withdrawal and limit EIP-712 signatures, and delayed-state
submission. Restart only KDF while leaving the app running; re-entering the
card feature calls `smart_account::register` again because the registry is
session-scoped.

Remove the local-library link when finished:

```sh
REMOVE=1 test_harness/gnosis_card/link_local_kdf.sh
```
