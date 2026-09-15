# Diagnostic privacy and private-key export

This document defines the maintained diagnostic and private-key export
boundaries. TRON/TRC20 export remains unavailable until the engine implements
it through `get_private_keys`.

## SDK boundary

RPC diagnostics contain only recognized method names, outcomes, durations,
safe counts and fixed error categories. Requests, startup configuration,
responses, process output and exception bodies are excluded from diagnostics
regardless of verbosity. Unknown method names become `unknown`. Recursive
censorship recognizes private-key naming variants, including `priv_key`, as
secondary protection. Operational RPC values and deliberate export JSON retain
their original values. Secret-bearing models have redacted diagnostic strings,
including when Equatable stringification is enabled.

`SecurityManager.exportPrivateKeys` owns protocol selection. It returns a result
per requested asset, including keys, actual coverage and a typed failure when
unavailable. Offline assets run independently with at most two requests in
flight, so one unsupported asset cannot erase successful keys.
Default asset selection remains the SDK session's activated, pending and failed
assets, with existing app presentation exclusions preserved.

TRON and TRC20 return `unsupportedProtocol` without issuing an RPC. This
applies to both legacy and HD wallets, regardless of activation state or address
index. Supported assets in a mixed selection still export independently. The
strict `getPrivateKeys` API rejects selections containing TRON/TRC20 before
issuing an RPC. TRON/TRC20 export remains disabled until KDF supports TRON
through `get_private_keys`.

The temporary `show_priv_key` and `account_balance_read` wrappers, scalar and
address derivation, HD metadata search, and direct SDK PointyCastle dependency
are removed. The unreleased export API no longer has a TRON opt-in,
active-address coverage, limited-coverage flag, separate signing-asset field or
TRON-only failure categories.
Offline HD assets retain their actual account, chain and inclusive address
range. ZHTLC retains its account-level coverage and optional viewing-key fields.

Export capabilities belong to one SecurityManager, verified wallet identity and
source-owned authentication generation. Public authentication transitions revoke
the generation synchronously before asynchronous work starts, including logout
followed by login to the same wallet. Capture is unavailable while a transition
is pending. Generation and identity are rechecked around asynchronous operations;
any transition invalidates the entire export.

## App lifecycle and delivery

The screen-scoped `PrivateKeyExportBloc` depends on injected export and delivery
services. Widgets render results and dispatch actions. Passwords are never state
fields. Cancellation, navigation away, disposal, wallet replacement and logout
clear the result and invalidate pending operations. A synchronous authentication
generation signal also clears displayed keys as soon as logout is requested.

Clipboard, file and share delivery revalidate identity asynchronously and then
check generation synchronously immediately before releasing the data. Desktop
and Android destination pickers receive no key bytes. Validation is repeated
after the destination is selected. iOS sharing stages a temporary file and removes
it on completion, cancellation or error. Browser downloads report an unconfirmed
outcome because a browser cannot report whether the user saved or cancelled.
Viewing keys is not recorded as a successful export.
Private-key delivery does not mark the entire wallet as backed up; the seed
backup flow remains separate. Its legacy private-key collection also excludes
TRON/TRC20, so it cannot bypass the export restriction.

The `gleec-private-key-export` version 1 document preserves per-key fields and
adds coverage and unavailable outcomes for each requested asset. Its
filtered assets and coverage match the screen. Bulk actions refer to **Displayed
keys**. TRON/TRC20 outcomes are unavailable and never offer key display, copy,
QR, share or file export. The active-TRON coverage labels and limited-coverage
manifest flag have been removed.

## Diagnostic storage and feedback

Logger initialization has one awaited, retryable readiness boundary. The fixed
namespace is `gleec_diagnostics_v1`. Before enabling it, migration removes old
diagnostic storage, cached diagnostic exports and precisely named app-owned iOS
diagnostic archives. It preserves wallet files, unrelated files, nested folders
and symlink targets. Failure leaves diagnostic export unavailable while wallet
use and feedback remain available.

Queue flushing, migration, retention, snapshots and disposal share a serialized
storage lifecycle. Browser clients use Web Locks and fail closed without them.
Snapshots copy bounded chunks under the lock before consumption, so later
writes cannot invalidate the export. Updated clients never read an old namespace
recreated by an older tab.

`SafeLogExporter` is the only app diagnostic attachment/export path. It accepts
complete versioned records, reapplies the diagnostic policy, drops malformed or
unclassifiable payload records and applies byte limits after filtering. Both
feedback providers receive prepared immutable attachments and have no logger
storage dependency. Automatic feedback metadata uses an explicit allowlist;
intentional user feedback remains usable without a diagnostic attachment.

Feedback latches screenshot sensitivity for the capture session. A sensitive
screen appearing at any time during that session suppresses app preview painting
and replaces the outgoing screenshot, even if logout or navigation subsequently
clears the screen. Missing or replaced sensitivity controllers fail closed.

## Validation and security review

Validation uses Flutter **3.41.4**. New app regressions are registered in
`test_units/main.dart`; its four required GasFree defines are documented in
[TESTING.md](TESTING.md). Native filesystem and browser OPFS tests cover legacy
cleanup, retry, queued writes, immediate snapshots, concurrent lock users,
namespace recreation, disposal and preservation of wallet files.

SDK tests use synthetic seed, password and private-key sentinels across logging
flags, errors and fallback paths, and assert that successful operational RPCs
and intentional exports retain their values. Export regressions cover partial
failure, two-request concurrency, explicit range semantics, authentication
transitions, and TRON/TRC20 rejection without RPC calls. The tests and local-KDF execution wrapper for the removed active-key
workaround have been deleted.

Keep per-revision validation logs and independent review findings with release
review artifacts outside this checkout. Run the current test surfaces before
making platform verification claims; historical results do not validate changes.

### Limits

These fixes cannot revoke diagnostic files already downloaded or sent to another
party. Older open tabs can still run old code; updated clients exclude their
legacy storage. Desktop tests, Android channel tests/Java compilation and iOS
staging tests do not replace device testing of operating-system share sheets,
provider crashes or app termination. Browser tests exercise actual Web Locks,
OPFS and worker concurrency, not every browser/version or several complete app
tabs. Windows filesystem behavior was not exercised on this macOS host.

Private-key export deliberately releases secret material to the destination the
user chooses. Clearing references in Dart is not a promise of memory zeroization
or clipboard revocation after successful delivery.
