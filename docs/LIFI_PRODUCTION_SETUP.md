# LI.FI build configuration

The Wallet defaults to the production LI.FI integration, including direct Flutter
builds without defines. Versioned public profiles keep builds explicit and
verifiable. These settings are compiled into the application and are not
credentials. Provider API keys must
remain outside the application, build arguments and repository.

## Public profile

[Production](LIFI_PRODUCTION_BUILD_DEFINES.json) is the only supported profile,
including GitHub previews. Staging is unavailable while KDP is configured for
the production integration; the selector rejects staging before running Flutter.
A separate staging profile should return only after matching proxy/key routing
is configured and verified.

Each profile contains exactly five fields:

| Define | Purpose |
|---|---|
| `LIFI_PROXY_URL` | Public HTTPS endpoint used for LI.FI requests |
| `LIFI_INTEGRATOR_ENABLED` | Enables the integration policy |
| `LIFI_INTEGRATOR_NAME` | Integration identifier associated with requests |
| `LIFI_INTEGRATOR_FEE_BPS` | Requested integrator fee in integer basis points |
| `LIFI_FEE_BPS` | Expected provider fee allocation in integer basis points |

The checked-in profiles use the 178 + 22 bps policy. The reusable SDK leaves its
integrator unset by default; the Wallet supplies the selected policy through
`KomodoDefiSdkConfig` and KDF startup configuration. Build settings describe the
requested allocation; they do not establish an executed payout.

## Selecting a profile

The shared build action uses `LIFI_BUILD_ENVIRONMENT: production`. It validates
that public file before running Flutter and supplies it to both asset generation
and the final build. It rejects staging, explicit `LIFI_*` defines (including
`-D` and `--dart-defines` aliases), and additional define files that could
replace the selected configuration. Native, web, Docker and GitHub previews
all use production; there is no staging workflow choice.

For a direct Flutter build, supply the public production file explicitly:

```sh
flutter build web --release \
  --dart-define-from-file=docs/LIFI_PRODUCTION_BUILD_DEFINES.json
```

Use the same profile in both build passes when asset generation requires a
second build. Keep other required build flags, without conflicting LI.FI
arguments. The final build must succeed. The profile selector does not itself
publish a deployment or configure a provider account.

## Validation

After resolving the locked dependencies, run:

```sh
bash .github/scripts/test_lifi_profiles.sh
```

The required `validate_code_guidelines` job runs this gate on every PR. It checks
the production default and explicit profile against an independent identity and verifies
the proxy, fee allocation and SDK/KDF startup fields. It also covers conflicting
arguments, release selection, SDK manifest consistency and action pinning.
The separate `lifi_profile_validation` job provides fast Python-only feedback.
Neither check requires a provider key or funded wallet.

## Artifact records

Native and Docker artifacts include the profile in their names. Matching
`-provenance` artifacts contain:

- `build.json`: public profile, source revisions, build-manifest hash and artifact
  file hashes.
- `SHA256SUMS`: hashes using repository-relative build paths.
- Resolved Wallet dependencies and, when separately resolved, SDK dependencies.

CI keeps these records for 14 days, the repository's artifact retention limit;
the workflows request 30. They describe build inputs and bytes; they are not
signatures or evidence that a deployment or transaction occurred. A record
names the checked-out commit and does not detect local edits made before the
build, such as the Docker Android job's `build.gradle` change or the production
Firebase patch.

The tool only reads artifacts under `build/` and writes `build-provenance/`
unless you pass `--output`. When you record several targets, give each its own
`--output` directory, and record and verify each one before a later clean step
deletes its files.

For a local web artifact, record its completed output directory:

```sh
python3 tool/lifi_build_provenance.py production --artifact build/web
```

To verify that artifact against its trusted build record, set `RELEASE_COMMIT`
independently to the intended full commit SHA and run:

```sh
python3 tool/lifi_build_provenance.py production \
  --artifact build/web \
  --verify build-provenance \
  --expected-commit "$RELEASE_COMMIT"
```

Verification checks the selected profile, checkout revisions, build manifest,
dependency snapshots and artifact hashes. Changed, missing or extra artifact
files fail the check. Keep the record from the trusted build; regenerating it
would replace the evidence being checked. The tool verifies consistency and
does not publish artifacts or access provider credentials.

See [build instructions](BUILD_RUN_APP.md#lifi-commission) and
[testing](TESTING.md#lifi-production-ci-gate) for the application-side
configuration and test coverage.
