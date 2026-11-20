# Narrow release gate tools

These tools support the November 2026 onboarding release checks. They are not
general deployment commands. Their project, source commit, channel and archive
names are deliberately fixed; review changes before using them for another
release.

- `hosting_snapshot.py` reads the current Gleec live release, static file
  hashes, configuration and `dex.gleec.com` domain mapping. Its output excludes
  credentials and deployment-user details. It rejects a release change during
  capture.
- `hosting_phase.py` accepts a reviewed `hosting-operation.json`. Preview mode
  checks the exact candidate archive and unchanged live version before deploying
  static hosting only. A separately reviewed configuration overlay must match
  its own SHA-256 before replacing the archive configuration; static-only
  validation still applies. The complete finalized remote file inventory and
  configuration must equal the uploaded candidate. It disables Firebase
  Authentication domain updates.
  Promotion releases the already-tested immutable preview version, with the old
  version retained as the rollback anchor. It reconciles a lost promotion
  response without issuing a second write.
- `native_publish.py` accepts a reviewed `native-publication.json` and the two
  exact `f9632e0ec771668a6f21b37aede01a30110141cb` native archives. It uses the
  existing KDF file-server account in CI, exclusive temporary uploads, standard
  non-overwriting rename and independent HTTPS SHA-256 verification. Existing
  final files are read-only on retry and must match exactly. No private source
  archive is uploaded.

The legacy file-server account has no operator-provided SSH host pin. This
publisher explicitly records TOFU and the observed public host-key fingerprint;
it does not claim authenticated server identity from that observation. Final
manifest acceptance requires an independent HTTPS download and exact digest.
Only intended-public binaries use this route. Old archive hashes are checked
separately in the release evidence.

Run the focused failure and side-effect tests without credentials or network:

```sh
python3 tool/auth_release_gates/test_native_publish.py
python3 tool/auth_release_gates/test_hosting_phase.py
```

Credential-bearing tools run only in narrowly scoped CI jobs using the existing
repository secrets. Never copy service-account JSON, SSH private keys or access
tokens into these files, build artifacts or reports. The hosting preview and
promotion workflow must serialize jobs; Firebase's release API does not provide
an atomic expected-version precondition against unrelated external deployers.

The current remote evidence workflow branch is
`auth/hosting-security-gate-20261108` in `GLEECBTC/gleec-wallet`. Native publication
uses `auth/native-artifact-gate-20261108` in `GLEECBTC/kdf-internal`. These branches
contain only the reviewed gate scripts and workflows, not the dirty working tree.

## Completed November 9 evidence

Native publication [run 42537351151](https://github.com/GLEECBTC/kdf-internal/actions/runs/42537351151)
used a read-only GitHub token. The intended-public binaries were staged in a
[public SDK prerelease](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/releases/tag/native-library-assets-f9632e0-20261108)
with no release/tag-triggered workflow, then downloaded without credentials by
the isolated file-server publisher. No write permission was granted to
`kdf-internal`, and neither its draft release nor private Git objects were
published. `evidence/native-publication.json`, independent downloads and
unchanged old-archive hashes record the result.

The wallet's one download-only capture job temporarily held `contents: write`
to read its unpublished draft archive. It had no checkout step or deployment
credentials. This permission was removed immediately after capture in commit
`6bf55a48`; subsequent preview jobs use `contents: read` and `actions: read`.
All three official action references were verified before use and pinned to
immutable commits.

Final preview [run 42538745323](https://github.com/GLEECBTC/gleec-wallet/actions/runs/42538745323)
verified `sites/gleec-wallet-official/versions/4a7943088d4ee536`.
The exact archive SHA-256 remains
`a26c400356a4327a86c423ee6e202af13314dc5cc54c0134c6b4794b04a17c0d`;
its cache-only configuration overlay is
`4ba5e021a0ce94f8e0b02f30635367d6586e0b31d31d052505faf020678c27fd`.
Both are bound in `evidence/hosting-preview.json`; the reviewed configuration
is retained beside it. Application responses revalidate, including deep SPA
routes and helper documents; the coin-icon cache exception remains.

This is a security-policy rebuild of the exact live app source, **not a hosted
preview of the new onboarding implementation**. The new onboarding normal and
rollback browser builds were validated separately and sealed in the rollback
record. Production hosting remains on
`sites/gleec-wallet-official/versions/05f0079ed5c6ab96`. No promotion, production
DNS/routing change or Cloudflare login was performed. Prepared production edge
activation remains deferred per the user's preview-only instruction.

The successful remote preview run passed 19 deployment-guard tests. Final local
review strengthened the distinct-overlay assertion and added correctly hashed
hook/dynamic-overlay rejection: **21 tests pass** without another deployment.
The runtime helper is unchanged from the successful remote run. Final current
workflow permission checks are retained in `evidence/final-ci-permissions.json`.
Actual served response and browser-flow evidence is in
[`AUTH_WEB_PREVIEW_EVIDENCE.json`](../../docs/AUTH_WEB_PREVIEW_EVIDENCE.json).

The coordinating Solana task also reported successful Linux/Windows/macOS
application builds in run `42542882336` and Android/iOS builds in run
`42542882385`, all at wallet `c9f14d34dc793dd7680da72088ed06aea340b8ad`.
`evidence/coordinating-native-ci.json` retains the exact job IDs and scope.
These support native preparation and packaging; they do not replace onboarding
UI acceptance, physical-provider checks or the still-enforced SDK merge-pin gate.
