# Web hosting topology

The checked-in `.firebaserc` and `firebase.json` define the wallet hosting
targets. The table below describes configuration, not the currently deployed
version. Verify the served build and headers after every release.

## Deploying

There is **one** `hosting` entry in `firebase.json`, and it is not tied to a
site. It names the deploy target `web`, and `.firebaserc` maps that target
to a different site in each project:

| `--project` | target `web` resolves to | who deploys it |
|---|---|---|
| `komodo-wallet-official` | site `walletrc` | CI, every push to `dev` |
| `komodo-wallet-preview` | site `komodo-wallet-preview` | local default |
| `gleec-wallet-official` | site `gleec-wallet-official` (dex.gleec.com) | by hand |

```bash
# Release candidate (what CI runs on every push to dev)
firebase deploy --only hosting:web --project komodo-wallet-official

# Production, dex.gleec.com
firebase deploy --only hosting:web --project gleec-wallet-official
```

Production being the *same* config rather than a second entry is deliberate:
production must never end up with weaker headers than the release candidate,
and one entry cannot drift from itself. The target is called `web` because it
names a role — "the wallet web app site for this project" — not a site; a
site-shaped name would be wrong in every project but one. `--project` is what
selects the site, so it is the only thing separating an RC deploy from a
production one. Always pass it: a bare
`firebase deploy` uses `.firebaserc`'s default, which is deliberately the
preview project, and a bare `firebase deploy --project gleec-wallet-official`
will push whatever is currently in `build/web` straight to dex.gleec.com.

`.firebaserc` is load-bearing here. Remove the `gleec-wallet-official` block
and production cannot be deployed from this config at all — the CLI aborts with
"Deploy target web not configured". `test_units/tests/fiat/fiat_checkout_url_allowlist_test.dart`
fails if that mapping is dropped or repointed.

## Header and cache rules

Keep `firebase.json` as standard JSON without comments. The reasons for its
settings live here so the same file can be consumed by strict JSON tooling and
the Firebase CLI. The wallet's existing hosting-config tests also parse it as
strict JSON.

Each header glob owns a distinct set of header keys. Firebase combines matching
entries, so the global security headers also apply to the narrower cache rules.

- `Content-Security-Policy: frame-ancestors 'self'` allows the wallet's own
  same-origin payment wrapper to be framed. `X-Frame-Options: SAMEORIGIN` keeps
  equivalent protection for older clients.
- `Permissions-Policy` keeps USB available to the wallet's Trezor transport
  through `usb=(self)`. Camera, microphone, payment, encrypted-media, and MIDI
  are deliberately not denied globally, allowing the wrapper to delegate the
  capabilities needed by provider checkout and identity-verification frames.
- Do not enable `Cross-Origin-Embedder-Policy: credentialless` as a routine
  hardening change. It strips cross-origin credentials needed by provider
  identity-verification flows and can break checkout.

| Files | Cache policy | Reason |
|---|---|---|
| `index.html`, `flutter_bootstrap.js`, `flutter.js`, `main.dart.js`, `flutter_service_worker.js`, `version.json` | `no-cache, max-age=0, must-revalidate` | Stable boot URLs and update-version checks must revalidate so a reload can install the deployed app. Revalidating only the HTML shell can still load an older cached application. |
| Bundled coin icons | `public, max-age=2592000` | A bounded 30-day lifetime reduces repeat downloads. Icons are not content-hashed, so this is not an `immutable` policy. |
| `/assets/assets/web_pages/**` | `public, max-age=0, must-revalidate` | Shipped native clients fetch these wrappers at runtime and need the latest checkout restrictions after a deployment. |

An icon fallback only handles missing assets; it does not replace an old but
successfully loaded cached icon. If an in-place icon replacement must reach
clients promptly, shorten its cache lifetime or give it a new filename.

## Verifying a deploy

`tool/verify_web_deploy.sh` asks a deployed site whether it is hardened. It
needs only `curl`, so whoever holds production access can confirm the result
without granting access to anyone else.

```bash
tool/verify_web_deploy.sh https://dex.gleec.com
```

It checks the wrapper asset and the response headers separately, because they
ship through different mechanisms and can land independently. Exit status is 0
only if everything passed. CI runs it against `walletrc` after every `dev`
deploy, so drift there is caught automatically; production has to be checked by
hand after each manual deploy.

## Still unconfirmed

Whether the existing production deploy actually uses this repository's
`firebase.json`. If it is run from a separate checkout or a locally modified
config, the `gleec-wallet-official` entry added here will not be the one in
effect and the `headers` block has to be copied into whatever config is. The
verifier above answers this definitively after a deploy: if the wrapper checks
pass but the header checks fail, production deployed a build from this repo with
a different hosting config.
