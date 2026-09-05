# Web hosting topology

Which Firebase Hosting site serves what, and what that means for getting a fix
in front of users. Everything under "Measured" was read from the live sites with
`curl`; none of it needs Firebase console access to reproduce.

## Measured, 2026-08-27

There are three Firebase projects in play: `komodo-wallet-official` (the RC),
`gleec-wallet-official` (production), and `komodo-wallet-preview` (the local
default in `.firebaserc`, used for ad-hoc previews).

| URL | Firebase site | Firebase project | Version | Last deployed | Deployed by |
|---|---|---|---|---|---|
| `dex.gleec.com` | `gleec-wallet-official` | **`gleec-wallet-official`** | 0.9.4 | 2026-04-17 | **by hand, not CI** |
| `walletrc.web.app` | `walletrc` | `komodo-wallet-official` | 0.9.6 | 2026-08-12 | CI, on push to `dev` |
| `prodrc.web.app` | `prodrc` | `komodo-wallet-official` | 0.9.3 | 2026-02-11 | nothing (see below) |

`dex.gleec.com` is a CNAME to `gleec-wallet-official.web.app`, and the two serve
byte-identical responses (same ETag, same `version.json`).

### How to re-derive this without console access

Firebase Hosting serves the site's own project config on a reserved path, so any
deployed site will tell you which project it belongs to:

```bash
curl -s https://dex.gleec.com/__/firebase/init.json
```

The same values are also compiled into `main.dart.js` from
`lib/firebase_options.dart`, and `dig +short dex.gleec.com` reveals the site ID
via the CNAME.

## Three consequences

**Production is a different Firebase project from everything CI touches.**
`dex.gleec.com` lives in project `gleec-wallet-official`; `walletrc` and
`prodrc` live in `komodo-wallet-official`. A single `firebase deploy` targets
one project, so no CI job that deploys the RC can ever also deploy production.
Merging to `dev` deploys `walletrc` and nothing else — a fix reaches users only
when the release master deploys production by hand. At the time of writing
production is two patch versions and four months behind `walletrc`.

**The `main` -> `prodrc` deploy step has never run.**
`.github/workflows/firebase-hosting-merge.yml` triggers on `push` to `dev` only,
so the step guarded by `github.ref == 'refs/heads/main'` is unreachable. Even if
it did fire it would target the wrong project for production. That is consistent
with `prodrc` being six months stale.

**Response headers only apply to the config that is actually deployed.**
Everything in `firebase.json` — the CSP, `X-Frame-Options`, `Permissions-Policy`
and the `must-revalidate` on `/assets/assets/web_pages/**` — is attached to the
hosting config being deployed. Deploy a site that config does not declare and
the headers simply do not exist on it. There is no error; the deploy succeeds
without them.

## What does *not* depend on any of this

The fiat on-ramp checkout URL allowlist lives inside
`assets/web_pages/fiat_widget.html`, which is build output. It ships with the
Flutter build regardless of which site is deployed and which `firebase.json` was
used. The headers are hardening layered on top; the allowlist is the fix.

This matters for desktop and mobile too: their `getOriginUrl()` is hardcoded to
`https://dex.gleec.com` (`lib/shared/utils/window/window_native.dart`), so
builds already in users' hands fetch that page from production at runtime.
Deploying production therefore fixes shipped native clients with no app release
— and conversely, until production is deployed, those clients keep fetching the
old page no matter what has merged.

That deploy is not a small change, and it is not this PR's to make. Production
is on 0.9.4 from 2026-04-17; deploying current `dev` to it moves the whole web
app forward by everything merged since, not just the on-ramp fix. Treat it as a
release, with whatever sign-off a release normally gets. The narrow question
this document answers is only *where* it has to land and *how to check* that it
did.

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
