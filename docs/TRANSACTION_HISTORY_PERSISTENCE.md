# Transaction history cache

The SDK caches recent transaction history for a quick first render after restart.
It owns encryption, key storage, retention, failure recovery and wallet scoping.
Applications configure cache behavior without handling encryption keys or Hive.

## Configuration and limits

`KomodoDefiSdkConfig.persistTransactionHistory` defaults to `true`.
`transactionHistoryCachePolicy` applies equally to persistence, explicit memory
storage and the memory fallback:

| Limit | Default |
|---|---:|
| Transactions per wallet and asset | 1,000 |
| Transactions across the cache | 20,000 |
| Logical bytes across the cache | 64 MiB |

`TransactionHistoryCachePolicy` accepts positive finite overrides. Logical bytes
include the serialized encrypted-envelope input, opaque keys and a conservative
allowance for ordering, identity and scope-recency indexes. This is a logical
cache budget, not a Dart heap quota or an exact filesystem-size guarantee.
Escaped JSON payload bytes are counted, including unusually large memos.

Within each wallet/asset scope, older transactions are evicted first. Global
count or byte pressure evicts older entries from the least recently used scopes.
Reads update recency in memory; a clean close persists that scope recency. An
interrupted process retains the recency recorded by its last successful writes.
Limits apply before writing a fetched batch and again while reopening a cache
created with larger limits. An oversized row is served from the network without
being retained. Hive's append-only file is compacted after eviction and on close.

These limits never apply to the durable unresolved GasFree transfer journal.
Evicting a cached transaction does not discard or authorize a pending transfer.

## Encryption and storage

The cache uses `komodo_tx_history_v2`. Each transaction has an opaque HMAC key;
wallet identity, asset scope, transaction hash, timestamp, addresses and amounts
are absent from plaintext Hive keys and values. Timestamp/ID ordering metadata
lives inside an encrypted envelope with the lossless `TransactionRecordCodec`
payload. A cold open decrypts envelopes in bounded batches to rebuild the
in-memory index; full transaction objects are decoded as rows are requested.

The SDK generates a random 32-byte key, protects it with platform secure storage,
and derives separate encryption and identifier keys. Native storage uses the
platform keychain/secure-storage facility; web uses its WebCrypto implementation.
The current web plugin stores its own encryption key in browser local storage.
A complete copy of that origin's local storage and IndexedDB can therefore be
decrypted. Script running in the origin can also access the data. WebCrypto does
not give this storage the same protection as a native keychain.
Preserve the wallet's CSP and do not expose cache keys to application callers.
Neither platform isolates data from an already authorised application or a
compromised device.

Hive currently uses AES-256-CBC. The HMAC database identifiers do not authenticate
the encrypted records, so this cache does not provide cryptographic tamper
detection. Authenticated encryption and browser key protection tied to wallet
unlock remain follow-up work. Physical native Keychain/Keystore behavior has
not been verified by the current tests.

Cache keys are independent of the wallet password, seed and RPC password. A
password change does not require cache re-encryption or another password prompt.
Sign-out invalidates SDK history operations but retains the encrypted cache for
the next login. Deleting a wallet purges its cache through the SDK's awaited
wallet-deletion hook. Wallet renames retain history; derivation method, private
key policy and verified wallet identity keep separate namespaces.

Cache cleanup is best effort after the wallet itself has been deleted. A history
purge failure is reported to the SDK's sanitized cleanup log; inaccessible disk
storage can retain encrypted rows. The memory fallback clears its rows but
reports that it could not verify deletion of persistent history. Such a failure
does not make a deleted wallet exist again or remove transfer recovery records.

Every in-isolate acquisition shares one cache owner and ordering index. Each
acquirer releases its reference on disposal. Native ownership combines an
isolate guard and OS advisory lock, scoped to the canonical cache directory.
A competing process or isolate falls back to bounded memory before key access
or corruption recovery. A crashed isolate conservatively retains its guard
until process restart. On web, a Web Lock grants one browser context ownership
of the persistent cache. Another context uses bounded memory until its next
cache acquisition; it cannot race key generation, writes,
eviction or an independently cached Hive index. The browser releases ownership
when the owning context exits.

## Upgrade and recovery

The SDK attempts to delete the obsolete plaintext `komodo_tx_history_v1` cache
without reading or migrating its rows. Failed cleanup is logged and retried.
Bootstrap attempts this cleanup even when persistence is disabled; a persistent
cache open retries it. The network rebuilds the cache.
A blocked browser database deletion has a five-second deadline and is retried on
subsequent SDK starts/opens. No unrelated Hive box or secure-storage key is reset.

A missing key creates a new random key and reconstructible history is refetched.
An inaccessible or malformed key, failed key persistence, unavailable Web Lock,
or unusable cache switches that owner to bounded memory. It never opens a
plaintext replacement. Key acquisition has a deadline. Corrupt individual rows
are evicted; a box that cannot open is deleted and reopened once. Failure to
persist or enforce retention disables persistence for that owner while its
successful network response remains usable. Diagnostics contain only generic
cache errors, not decrypted records, key material or provider payloads.

## Cache data and provider pagination

`TransactionStorage.getTransactions` returns `CachedTransactionPage` with
`transactions` and `cachedCount`. The count describes only retained cache rows;
it is never a provider total or a promise that history is complete.

`TransactionHistoryManager.getTransactionHistory` obtains pages, totals and
continuation tokens from the asset's provider strategy. It never substitutes
cached transaction IDs for opaque provider cursors. `getTransactionsStreamed`
yields cached rows before activation, then fetches current history from the
provider. Older network history remains accessible after cache eviction.

## Validation

SDK history tests cover common storage behavior, wallet isolation and deletion,
real encrypted files, raw IndexedDB inspection, key loss/failure, corruption,
per-scope and global limits, logical byte accounting, browser ownership, and
provider pagination beyond retained rows. The SDK bootstrap harness verifies
wallet lifecycle wiring. Use the pinned Flutter toolchain and the commands in
[TESTING.md](TESTING.md); browser cache tests run with `--platform chrome`.
