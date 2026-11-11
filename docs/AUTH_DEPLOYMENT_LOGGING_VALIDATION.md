# Firebase deployment logging privacy — 2026-11-09

The coordinating Solana task reported sensitive Identity Toolkit configuration
fields in verbose Firebase deployment output. This review inspected source and
run metadata only; it did not open, copy or store real provider values.

The shared action previously added `--debug` and streamed raw output to Actions
logs. The pinned Firebase CLI 15.22.3 also creates a debug-level file in its
working directory without that flag. Removing the flag alone was insufficient.

## Correction

- The action delegates to `firebase_hosting_deploy.sh`. It runs the CLI from a
  unique mode-0700 temporary directory, captures both streams, and keeps its
  mode-0600 credentials, debug logs, config store and npm logs there.
- An absolute `--config` preserves the checkout's public-file paths and
  `.firebaserc` target mapping. Existing unrelated files are not removed.
- Raw provider output is never echoed. Diagnostics use fixed messages; the
  inherited service-account and debug environment variables are removed before
  invoking the CLI. Exit, interruption and termination clean the private files.
- Existing deployment failure codes, bounded retries and current-active-version
  handling are preserved. Each attempt replaces its captured output so a prior
  attempt cannot supply the preview URL.
- Only one unambiguous, canonical HTTPS `*.web.app` hostname URL of the
  requested deployment kind may reach the action output. Preview mode requires
  a channel URL even when the CLI also prints its ordinary live-site URL. Credentials, ports, paths, queries,
  fragments, control characters and shell syntax are rejected.
- The SDK preview caller passes the URL/channel through environment variables
  and quoted `printf`, instead of interpolating output into shell source.

Hard termination cannot execute a shell cleanup trap. Private file permissions
and the disposable CI runner remain the limit for that case; no guaranteed
memory erasure is claimed.

## Validation

- 27 Python tests exercise the real wrapper and action run block with synthetic
  credentials and a fake provider. They cover canaries in stdout, stderr and
  debug files, permissions, cleanup, cancellation, retries, failure codes,
  malformed credentials, URL attacks and ambiguous output.
- Eight shell URL fixtures pass, including the actual combined live/preview
  output. ShellCheck and whitespace checks pass.
- The actual installed 15.22.3 `Config.load`, `loadRC` and logger modules were
  checked offline: a private working directory still resolves the original
  project/public paths and hosting target, while the debug file stays private.
- The Python suite is included in `validate-code-guidelines.yml`; these are CI
  infrastructure tests, not app tests requiring the Flutter aggregator.
- Independent review found no remaining actionable issue in this patch.

Standalone handoff: `/private/tmp/gleec-hosting-deploy-privacy-only.patch`,
SHA-256 `e810997e49bc2f793f26078aaf7bf18b96a97c45dafd08f997cd1b68bfe98a45`.
It changes seven deployment/test files and applies to a clean baseline. It does
not change application authentication, SDK pins or production hosting.

## Hosted follow-up

The first protected deployment, [run 42541703281](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42541703281),
uploaded the preview but failed URL extraction. The pinned CLI normally emits
both `Hosting URL` and `Channel URL`; the initial strict parser incorrectly
rejected that valid pair. The coordinating task reported no raw provider output
leak in this run.

Follow-up commit `c9f14d34dc793dd7680da72088ed06aea340b8ad` was integrated and
reviewed independently in this checkout. The wrapper passes an explicit mode;
preview mode requires a unique channel URL and never falls back to a live URL.
Combined/reordered/duplicated lines, omitted version metadata, invalid canonical
prefixes and conflicting preview URLs are covered. All 27 Python tests, eight
shell fixtures and ShellCheck pass. Hosted confirmation passed in
[run 42542882339](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42542882339),
job `128921491560`, at that exact source head. The correct preview URL is
[the Solana feature preview](https://walletrc--pull-3611-merge-8wrn0cav.web.app).
Its public identity was independently checked: app merge
`b607818561e93dfa747f0b87b9fd1adf4a9602a5`, SDK
`34faf005b2e092419d0cb12b84f21b02a6c7f0d6`, approved configuration SHA-256
`137fa2b780ea57e7ec46b3fa0245fe97adfaae2557615d6e6ffced7977c62b22`,
with `production_approved=false` and `legal_availability_bypass=false`.
This verifies the shared deployment wrapper, not the full onboarding UI branch.

The coordinating task confirmed the fixed completion marker and absence of
`hashConfig`, `signerKey` and `[apiv2][body]` markers in the new log. This checkout
verified CI metadata and public build identity without retrieving raw run logs.
[Sanitized evidence](../tool/auth_release_gates/evidence/hosting-deployment-privacy.json)
records that distinction.

Follow-up patch: `/private/tmp/gleec-hosting-preview-url-followup.patch`, SHA-256
`d7d3328920598d26aeef2c59bec10ed252c9de64328d82aa8069b6f9f827aed7`.
It changes only four deployment scripts/tests and retains the privacy controls.

## Earlier logs — cleanup decision pending

| Run | Evidence and disposition |
| --- | --- |
| [42539838475](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42539838475) | The coordinating task reported sensitive fields in job `128912078797`, head `9a0c1704a8f04425bfd04e3a7756a1e26e34c144`. The run completed successfully. No values were inspected in this review. |
| [42540695130](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42540695130) | Cancelled at head `f292f8a085eb88cbed31d8125efb6715e2c4ba0c`. Deployment briefly started before cancellation completed, so treat its logs as potentially exposed. No raw logs were inspected. |

The coordinating Solana task adopted the exact reviewed patch in separate
commit `c99278a770029fea91581580b111ba989e5a21b5`, after independently passing
21 privacy tests, seven URL fixtures, ShellCheck and review. Subsequent preview
CI uses the corrected wrapper; the parser failure and subsequent correction
are recorded above. No authentication logic, app code, SDK pointer
or native pin changed in that commit.

No historical run logs were deleted and no credential or provider configuration
was rotated. Removing those run logs is a permanent action requiring the user's approval. This two-run record is not an audit of
every historical deployment; any wider exposure assessment must avoid copying
provider values into chats, artifacts or support reports.
