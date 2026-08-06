# Transaction history persistence

Transaction history is cached on disk between sessions. A coin details page
renders the history it already knows on a cold start, instead of waiting for the
first network round trip, and the walk that follows becomes a refresh rather
than a cold fetch.

Everything here lives in the `sdk/` submodule, under
`packages/komodo_defi_sdk/lib/src/transaction_history/`.

## What changed

| | Before | After |
|---|---|---|
| Implementations of `TransactionStorage` | `InMemoryTransactionStorage` only | plus `HiveTransactionStorage` |
| Lifetime | one process | across sessions |
| Wiring | implicit, via `TransactionStorage.defaultForPlatform()` | explicit in `bootstrap.dart`, behind a config flag |
| Retention | unbounded | unbounded (deliberately unchanged) |

`TransactionStorage.defaultForPlatform()` still returns the in-memory store.
Flipping it would silently repoint every consumer that constructs a manager
outside `bootstrap()` — the example app and the KDF harness among them — at
disk.

## Turning it off

`KomodoDefiSdkConfig.persistTransactionHistory`, default `true`. The app can
disable it in `lib/mm2/mm2.dart` with no submodule bump and no SDK revert:

```dart
KomodoDefiSdkConfig(persistTransactionHistory: false)
```

It defaults to on rather than dark-launching because with it off, `bootstrap()`
— and therefore the KDF harness job that drives the real bootstrap on every PR —
stays on the in-memory path and the feature ships unexercised end to end.

## How it is stored

One Hive entry per transaction in a lazy box, `komodo_tx_history_v1`.

```
key = <walletToken:20 hex>|<assetToken:20 hex>|<timestampMicros:16 digits>|<internalId>
```

`TransactionOrderIndex` rebuilds ordering, pagination, lookups and stats from
`box.keys` alone. A cold open costs one pass over the key list and zero record
decodes; only rows actually returned are read from disk. `getLatestTransactionId`
— polled per watched asset every 30 seconds — is O(1) with no disk read at all.

One entry per transaction rather than a blob per asset keeps writes proportional
to what changed. Production stores a page at a time and re-stores page one on
every confirmations refresh; against a per-asset blob that would rewrite the
whole history each time, and Hive's VM backend is an append-only log, so every
rewrite stays on disk until compaction. Byte-identical re-stores are skipped
outright.

### Wallet scoping

`walletToken` hashes `walletStorageNamespace(walletId)`, never
`WalletId.compoundId` — the compound ID omits authentication options, so an HD
and an Iguana session on one seed would share a namespace. Consequences, all
covered by tests:

- Derivation method, private-key policy (including distinct WalletConnect
  sessions) and pubkey hash each isolate history.
- A **renamed** wallet keeps its history, and pubkey-hash casing does not fork
  it. This differs from the in-memory store, which keys on raw `WalletId`
  equality, and matches `HivePubkeysStorage`.
- A name-only identity stays separate from an enriched one: a reused name is not
  proof that the data belongs to the authenticated wallet.

### The 255-byte key guard

`hive_ce` writes a String key as a single length byte followed by its UTF-8
bytes, and validates nothing. A key over 255 bytes wraps that byte modulo 256,
misparses the frame, fails CRC, and — with the default `crashRecovery: true` —
makes Hive **truncate the box file at that frame**, discarding everything
written after it. Silent, and VM-only, since on web the key goes into IndexedDB
with no length prefix.

`TransactionStorageKey.build` refuses to emit an over-long key. Internal IDs
past the budget are replaced by a digest; the record body keeps the true ID.

## Serialization

`Transaction.toJson`/`fromJson` are a KDF wire format and **do not round-trip**.
`TransactionRecordCodec` is independent of them. A test pins the asymmetry so
this stays visible:

- `toJson` nests `balance_changes`; `fromJson` reads `my_balance_change` at the
  top level, so decoding an encoded transaction throws.
- `chain_id` is written as a formatted String and read as an `int`.
- The symbol's four external price-provider IDs are written nested and read at
  the top level — silently nulled. `parentId` is written as a bare ticker that
  `fromJson` cannot resolve, because it passes `knownIds: null`.
- `FeeInfoTendermint.toJson()` emits `"type": "CosmosGas"`, so it decodes back
  as a **different variant** with its amount re-derived through a `double`.
  `Qrc20Gas`/`CosmosGas` write `gas_price` through a `double` too.

Two conventions carry the correctness:

- Every `Decimal` is stored via `toString()`, which round-trips exactly.
- `FeeInfo` is tagged by its **Dart** variant through an exhaustive `switch`
  over the sealed type, never by the wire `"type"`. Because the type is sealed,
  adding a variant upstream is a compile error here rather than silent loss.

`DateTime` stores microseconds **and** `isUtc` — `DateTime.==` compares both, and
`timestamp` is among `Transaction`'s Equatable props, so dropping `isUtc` would
make restored rows compare unequal to freshly parsed ones.

`subClass` is stored as the **enum name**, never `subClass.formatted`.
`CoinSubClass.parse` sanitizes its input but matches against un-sanitized
formatted names, so `'Komodo Smart Chain'` and every other multi-word name is
unresolvable, and `'Ethereum'` resolves to `ethereumClassic` rather than `erc20`.

### Asset identity

`getTransactions`, `clearTransactions` and `getLatestTransactionId` all receive
the live `AssetId`, so rows are rebuilt carrying **that instance** — `parentId`
linkage, the concrete `ChainId` subtype and the symbol's provider IDs survive
exactly as the rest of the SDK produced them.

`getTransactionById` and `getStats` have no `AssetId` to scope by, so they
reconstruct one. It compares equal (`AssetId.props` is
`[id, subClass.formatted, chainId.formattedChainId]`) but `parentId` is `null`.
Neither method has any production caller.

## Failure posture

Throw for caller bugs, degrade for I/O. The cache is derived state, so no
storage fault should be able to break the wallet.

| Situation | Behaviour |
|---|---|
| Empty internal ID, unknown pagination cursor | throws `TransactionStorageException`, as before |
| Box will not open | deleted and reopened once; still failing → in-memory for the process, `isDegraded == true`. Construction and first use never throw |
| Record will not decode, or is from a newer schema | dropped and evicted; the rest of the asset stays readable. The network refetches it |
| Write fails (disk full, IndexedDB quota) | logged and swallowed — the caller already has the rows, and a cache miss must not look like a fetch error |

Per-record containment is why the box is **lazy**: a non-lazy box decodes
everything at open, so one bad frame would take the whole dataset with it.

Re-keying — a pending row gaining a real timestamp — writes the new key **before**
deleting the old one, so a crash between them leaves a recoverable duplicate
rather than losing the row.

### Web

The recovery delete is wrapped in a 5-second timeout. On web
`deleteBoxFromDisk` resolves to `IDBFactory.deleteDatabase`, which blocks while
another tab holds the database open and never completes; without a deadline,
corruption recovery would hang forever. `compact()` is a safe no-op there —
IndexedDB genuinely deletes, so there is no append-only log to compact.

## Known gaps

**No purge on wallet deletion.** `AuthService.deleteWallet` issues the KDF RPC
and clears secure storage, and nothing else. This is pre-existing — the pubkey
cache, the activation config box and the wallet asset list all already survive
wallet deletion — but transaction history is the most sensitive of the four.

Two mitigations ship here. `HiveTransactionStorage.purgeWallet(walletId)` is
available to callers that delete a wallet, and a garbage collector runs at open
against `auth.getUsers()`, dropping history for wallets that no longer exist. The
GC **fails open**: a throwing or empty provider means "do not know", never
"delete everything".

The cross-cutting fix — one purge covering all four stores, wired into
`deleteWallet` — belongs in `komodo_defi_local_auth` and is not done.

**Unencrypted.** Plain Hive, consistent with `HivePubkeysStorage`, which already
persists every derived address and balance in the clear. Be honest about the
delta though: a pubkey cache is an identity list, whereas transaction history is
a financial profile — counterparties, amounts, timings. That is a product
decision, not a technical one. `HiveTransactionStorage` accepts an optional
`HiveCipher` so encryption can be turned on later without a rewrite;
`flutter_secure_storage` is the wrong tool for bulk data, but is the right place
for the key if it ever happens.

**Unbounded.** Retention matches the in-memory store it replaces: nothing is
evicted. `InMemoryTransactionStorage` now accepts `maxTransactionsPerAsset` if a
cap is ever wanted; the deadlock that made any cap unusable is fixed (below).

## Fixes this work depended on

Two live defects surfaced while building against the existing store.

**Every page of history after the first was being dropped.**
`InMemoryTransactionStorage` kept each asset's transactions in a `SplayTreeMap`
whose comparator resolved keys through a map captured when the tree was built —
so the tree's ordering depended on a snapshot of its own contents, and comparing
against any key added later threw. `storeTransactions` looked up
`existingMap[newInternalId]` before rebuilding, so the second batch for an asset
threw outright. `getTransactionsStreamed` swallows that in its retry catch and
sets `hasMore = false`, so the network walk silently stopped after page one.
`getTransactionById` threw for unknown IDs for the same reason. Ordering is now
applied on read over a plain map.

**Enabling any retention cap would have hung the SDK.** `storeTransactions`
called `_enforceStorageLimit` from inside its own `_mutex.protect` body, and
that method took `_mutex.protect` again. `package:mutex`'s `Mutex` is a
write-only `ReadWriteMutex` and is not reentrant, so the re-acquire waited on a
future only `release()` could complete — and `release()` was in the `finally`
that was itself waiting. A permanent hang, not an exception, and every later
call on the instance would hang too. Invisible only because the cap was a
hardcoded `null` that returned before taking the lock.

**Persisted rows no longer stand in for KDF activation.**
`getTransactionHistory` skipped `_ensureAssetActivated` whenever storage had
rows, reasoning that stored history proves prior activation. That only holds
while storage is per-process: on a cold start there are rows for an asset KDF has
not enabled, and the fetch below would run against an inactive coin. Activation
is now tracked in a per-session set, cleared on every wallet change.

## Testing

```bash
cd sdk/packages/komodo_defi_sdk && KDF_HARNESS="" fvm flutter test
```

`transaction_storage_conformance.dart` is the contract, run against **both**
implementations by `in_memory_transaction_storage_test.dart` and
`hive_transaction_storage_test.dart`. It covers ordering and tie-breaking,
accumulation across batches, merge semantics, pagination, lookups, clearing,
wallet and asset isolation, and stats, plus a durability group that only runs
for persistent implementations.

Only behaviour every implementation must share belongs there. The axes that
legitimately differ — rename tolerance and pubkey-hash casing — are asserted in
the Hive-specific suite instead.

Alongside it: `transaction_record_codec_test.dart` (all 10 `FeeInfo` variants,
every `CoinSubClass`, `isUtc`, decimal precision),
`transaction_storage_key_test.dart` (length guard, token isolation, timestamp
encoding), `transaction_order_index_test.dart`, and the Hive suite's
persistence, write-behaviour, recovery, degraded-mode and GC groups.

If the index generator has not been run after adding a file here, it will not be
exported:

```bash
cd sdk/packages/komodo_defi_sdk && dart run index_generator
```

## Manual verification

```bash
fvm flutter run -d macos --dart-define=TRON_GASLESS_ENABLED=true --dart-define=TRON_GASLESS_RECEIVE_ENABLED=true --dart-define=TRON_GASLESS_BASE_URL=https://quicknode.gleec.com/gasfree/tron --dart-define=TRON_GASLESS_SERVICE_PROVIDER=TLntW9Z59LYY5KEi9cmwk3PKjQga828ird
```

1. Sign in, open a coin page with real history, let it populate.
2. **Hard-kill** the app (⌘Q). Not hot restart — that keeps the Dart isolate and
   so gives a false pass.
3. Relaunch with **Wi-Fi off**. History must render from disk.
4. Switch to a second wallet and confirm zero bleed-through.

If step 3 shows a spinner, check
`lib/bloc/transaction_history/transaction_history_bloc.dart` before blaming
storage: it awaits `pubkeys.lastKnown ?? getPubkeys` *before* subscribing, and
that path only stays non-blocking because the **pubkey** cache is also
persisted.

Use `fvm flutter` throughout — the machine default may be a newer Flutter than
`.fvmrc` pins, and a bare `pub get` writes a lockfile CI cannot satisfy under
`--enforce-lockfile`.
