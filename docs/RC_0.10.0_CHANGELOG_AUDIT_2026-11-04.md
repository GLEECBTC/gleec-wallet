# Gleec Wallet 0.10.0: changes accepted after the RC opened

Snapshot: **4 November 2026**. This is release preparation, not a publication
or production-readiness claim. Main app #3575 and SDK #416 remain open.

## Exact range

- Release PR [#3575](https://github.com/GLEECBTC/gleec-wallet/pull/3575)
  opened on 28 October at 19:21:28 UTC with head
  `ffcac83447af92e427dee47a3498cc4819c674ee`. Its first hosted workflow runs
  use that exact SHA, confirming the initial boundary.
- Accepted app RC: `42be44e92d111a12ef5ec5e62f84349118465fae`.
- SDK at the initial app head: `80e656101ce1b85fe05ddcbc05b0520f3265d1a0`;
  SDK at the accepted current RC: `ff43a0bad14577b2f5649fae22233a5fe9fe02c4`, the tree of
  SDK `release-0.9.0` `7636f554c77b0d4bfa02d20dc030f1a95596a755`.
- [Complete post-opening comparison](https://github.com/GLEECBTC/gleec-wallet/compare/ffcac83447af92e427dee47a3498cc4819c674ee...42be44e92d111a12ef5ec5e62f84349118465fae).
  **33 non-merge commits** were checked; **25** touch app files outside the
  SDK gitlink and eight are pointer-only reconciliations. Duplicate preparation,
  SDK-pointer and accepted-carry commits are mapped to the change they deliver.

## Coverage

| Accepted source / RC carry | Change and release-note disposition |
| --- | --- |
| [#3576](https://github.com/GLEECBTC/gleec-wallet/pull/3576) / [#3577](https://github.com/GLEECBTC/gleec-wallet/pull/3577) | Interim merged-dev engine input and exact gas-default regression. The later #3587 roll supersedes this pin. Keep the original validation as dated history; the pointer bump is not a separate user feature. |
| [#3579](https://github.com/GLEECBTC/gleec-wallet/pull/3579) / [#3580](https://github.com/GLEECBTC/gleec-wallet/pull/3580) | Restore prior atomic EVM-token trading, Advanced orders and bot starts, with accurate existing allowance copy. The bug-fix entry and compatibility limits retain the prior interaction flow; LI.FI keeps its separate approval contract. |
| [#3581](https://github.com/GLEECBTC/gleec-wallet/pull/3581) / [#3582](https://github.com/GLEECBTC/gleec-wallet/pull/3582) | Adopt SDK Trezor orphan-file/session correction and replace the misleading Suite-only error explanation. Root app bug-fix and SDK-update entries cover it. |
| [#3584](https://github.com/GLEECBTC/gleec-wallet/pull/3584) / [#3583](https://github.com/GLEECBTC/gleec-wallet/pull/3583) | Revoke reviewed atomic/routed starts on cancellation, replacement, hiding and every wallet-session boundary; serialize dispatch and retain uncertain-start recovery. Record the complete security correction once, with its transition tests and remediation record linked. |
| [#3586](https://github.com/GLEECBTC/gleec-wallet/pull/3586) / [#3587](https://github.com/GLEECBTC/gleec-wallet/pull/3587) | Accepted SDK/KDF/coins roll, frozen-branch previews, bounded MARTY balance-view readiness in GUI tests, named Banxa quote/selection deferral and final provenance. Notes now identify the actual current pins and limits; test-only changes remain validation evidence. |
| [#3592](https://github.com/GLEECBTC/gleec-wallet/pull/3592) / [#3593](https://github.com/GLEECBTC/gleec-wallet/pull/3593) | Review follow-ups on the session fix: amount, Max, unit switch and suggested amounts locked while a start is in doubt; tab-hide during a legal wait returns to the form; Review waits for the form's session; the SDK pin check counts only long-lived branches; docs trimmed; SDK #437 / #438 bound the dispatch lease. Root app notes (Swap Start Ownership) and the SDK-update subsection. |
| [#3594](https://github.com/GLEECBTC/gleec-wallet/pull/3594) / [#3595](https://github.com/GLEECBTC/gleec-wallet/pull/3595) | Final coins roll `efd3a647` → `cc8249e8` through SDK #439 / #440: Yenten (YTN) and L2 fee models, no coin removed; fresh file, icon and provider evidence. Root app notes (Frozen Inputs), checklist and input manifest. |

The SDK-update subsection also records user-visible paginated recovery and
session-owned offers/dispatch. SDK recovery #417/#418 was already present in
the app's initial `80e65610` SDK input; it stays in the complete release notes,
but is not counted as a second post-opening app change. All source/carry PR
authors in this range resolve to **@CharlVS**.

## Accepted inputs and evidence

- App source #3586 squash: `1249c500c96a7dc139ae7b86d8667e8304bd6a1b`.
  Normal RC carry #3587: `da3214d80f3c75aa0cc6fe718f75403226df6f30`.
- SDK source #430 squash: `db73613cd34a2c0779da024a71338052e4bbb030`.
  Normal RC carry #431: `3b4629048d8513af8f8a9d17a5cdf7eb5763d206`.
- App follow-ups #3592 squash `d7c369cef50e235f9e0272d86d4e83404c72e62a` /
  normal RC carry #3593 `62d6ded1e5e9c9156cc0a126fe908b4589f679f2`; coins
  repin #3594 squash `30e71b79aee94b9b46095fc84be1f0774a13a311` / normal RC
  carry #3595 `42be44e92d111a12ef5ec5e62f84349118465fae`.
- SDK follow-ups #437 squash `34dd5febb45193c7c66b649b89b68ef3d90f3675` /
  normal RC carry #438 `ad1799272121c18c7391287b9744247f89c04e44`; coins roll
  #439 squash `ab29d57aa05aa48240ab7430c6d51a4f5e60a579` / normal RC carry
  #440 `7636f554c77b0d4bfa02d20dc030f1a95596a755`, whose carry head `ff43a0bad14577b2f5649fae22233a5fe9fe02c4` the app pins.
- KDF `a51d69a11ff937ecf9678e9b37632af578252846` (`3.2.0-beta`), coins
  `cc8249e85e54467bc2684c2712857711eab55fd2` (previously `efd3a647`), specs
  `7c388ea7b91cb7c657435d416bc03e5349b46162`.
- Accepted source/carry trees matched tested candidates. App native **3,991
  passed /4 skipped**, browser/WASM **84 passed**; release-WASM/bundle checks
  passed. Source/carry hosted checks **14/9** and main-RC **17** passed for
  those recorded heads. SDK qualification and exact KDF/coin provenance are
  linked from the [checklist](RELEASE_0.10.0_CHECKLIST.md).
- The [4 November preview recheck](RC_0.10.0_PREVIEW_2026-11-04.json) confirms
  the ordinary main-RC preview's full source tree, SDK link, served JavaScript
  and 13 config/coin/engine files. Legal bypass is **false** and production
  approval is **false**. It qualifies that snapshot, not a later carry or a
  signed installer. No build, deployment or KDF repository test was run here.

## Work that still needs acceptance or qualification

At this snapshot, SDK logging carry
[#435](https://github.com/GLEECBTC/komodo-defi-sdk-flutter/pull/435) and wallet
default-selection source [#3590](https://github.com/GLEECBTC/gleec-wallet/pull/3590)
/ carry [#3589](https://github.com/GLEECBTC/gleec-wallet/pull/3589) remain pending.
Their changes are not asserted to be in this frozen app. Update the notes,
manifest, audit boundary and preview evidence after actual acceptance.

The separate Safe5 selection round on the pending source showed defaults
persisting after app/USB restart and fresh authentication. It did not certify
automatic authenticated-session recovery or a complete native balance view.
The version-null health-check/sign-out observation and device-lock-interrupted
`Unexpected message` attempts retain their own reproducibility/disposition
gate on the final candidate; a successful reconnect does not erase them.

Approved legal text, final promotion review, signed packaging/install/upgrade
evidence and any final SDK main pin remain separate release gates. The owner's
named Banxa on-ramp quote/selection deferral is a deferral, not a quote pass;
Ramp remains separate. No new waiver, main merge, tag, publication, production
deployment or funded action is part of this documentation work.
