# Web hosting topology

Which Firebase Hosting site serves what, and what that means for getting a fix
in front of users. Everything under "Measured" was read from the live sites with
`curl`; none of it needs Firebase console access to reproduce.

## Measured, 2026-08-27

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
production is two minor versions and four months behind `walletrc`.

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

## Deploying

`firebase.json` declares both sites, so the same config serves the same policy
either way. Each deploy has to name its site *and* its project, because the two
sites are in different projects:

```bash
# Release candidate (what CI runs on every push to dev)
firebase deploy --only hosting:walletrc --project komodo-wallet-official

# Production, dex.gleec.com
firebase deploy --only hosting:gleec-wallet-official --project gleec-wallet-official
```

A bare `firebase deploy` would try both entries and fail on credentials for
whichever project you are not authenticated against. Always pass `--only` and
`--project`.

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
