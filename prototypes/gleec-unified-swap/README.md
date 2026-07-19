# Gleec Unified Swap prototype

This directory contains the editable, self-contained Unified Swap UX prototype and its regression evidence.

## Key files

- `gleec-unified-swap.html` — primary editable prototype.
- `gleec-unified-swap-standalone.html` — minimal full-window launcher used for local review.
- `gleec-unified-swap-assets/` — local fonts, Gleec logos, icons, chain badges, and token artwork.
- `verify-gleec-unified-swap.mjs` — dependency-free fixture and UX regression checks.
- `gleec-unified-swap-qa.md` and `design-qa.md` — acceptance and visual QA records.
- `qa-evidence/` — representative workbench captures, three raw 390×844 browser-viewport captures, and a machine-verified evidence manifest.

## Run locally

From the repository root:

```bash
python3 -m http.server 4173 --directory prototypes/gleec-unified-swap
```

Then open:

```text
http://127.0.0.1:4173/gleec-unified-swap-standalone.html
```

## Verify changes

```bash
node prototypes/gleec-unified-swap/verify-gleec-unified-swap.mjs
```

The currently deployed reference is available at:

<https://charlvs.github.io/gleec-wallet/gleec-unified-swap/>

Keep asset references relative so the same prototype works locally and from a repository subpath.
