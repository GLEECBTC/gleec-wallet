# Gleec Wallet legal-document hosting handoff

Publish these files at the root of `https://privacy.gleec.com/`:

| File | URL |
| --- | --- |
| `tos_gleec_wallet.md` | https://privacy.gleec.com/tos_gleec_wallet.md |
| `eula_gleec_wallet.md` | https://privacy.gleec.com/eula_gleec_wallet.md |
| `privacy_notice_gleec_wallet.md` | https://privacy.gleec.com/privacy_notice_gleec_wallet.md |
| `kyc_due_diligence_policy_gleec_wallet.md` | https://privacy.gleec.com/kyc_due_diligence_policy_gleec_wallet.md |
| `tos_lifi_gleec_wallet.md` | https://privacy.gleec.com/tos_lifi_gleec_wallet.md |

**Decker:** Serve UTF-8 Markdown (`Content-Type: text/markdown; charset=utf-8`, or `text/plain; charset=utf-8`). Preserve the existing files’ bytes so previously recorded content hashes stay compatible. Enable browser CORS for the wallet, allow `If-None-Match` in preflight requests, and expose `ETag`. Support conditional GET/304 and sensible cache revalidation. Apply CORS headers to errors and 304 responses too. Missing files must return genuine HTTP 404s; do not serve the website’s HTML fallback. Verify all five URLs from the wallet’s browser build and native app.

**Ilya/counsel:** Finalize the LI.FI swap document and confirm the applicable disclosures and wording, including the app’s informational website referral. The four existing documents have been moved without legal edits.

**Decker:** Replace `tos_lifi_gleec_wallet.md` with Ilya’s final text and remove `<!-- gleec-legal-status: placeholder -->`. The placeholder is informational only and cannot be accepted. Confirm deployment completion.

## Wallet behavior

A new installation needs the EULA and wallet ToS before creating, importing, logging in, or continuing with a hardware wallet. A new routed swap also needs the LI.FI document. Valid cached full text remains usable offline. Missing documents, placeholders, HTML errors and malformed responses never become consent records. The website referral is informational; opening it is not acceptance. Existing swaps and their recovery remain usable.

For local/preview testing only, `--dart-define=BYPASS_LEGAL_DOCUMENT_GATE=true` allows submission while keeping the notice. It never records acceptance of missing or placeholder documents. The default is false; production builds must leave it disabled. No hosting manifest is needed.

Until the required files are deployed, production consent forms on devices without valid cached documents remain disabled and offer Retry.
