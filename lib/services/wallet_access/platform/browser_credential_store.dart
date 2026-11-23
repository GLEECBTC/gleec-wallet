part of 'browser_credential_vault.dart';

/// Persistence boundary for the vault. Promotion and removal compare the
/// active revision inside the same transaction that changes the active row.
abstract interface class BrowserCredentialStore {
  Future<BrowserCredentialRecord?> get(String key);
  Future<BrowserCredentialRecord?> getStaged(String slot);
  Future<String> stage(BrowserCredentialRecord record, String identifier);
  Future<void> discardStage(String slot);
  Future<void> promote(
    String key,
    int? expectedRevision,
    String stageSlot,
    int stagedRevision,
    web.AbortSignal signal,
  );
  Future<void> remove(
    String key,
    int? expectedRevision,
    web.AbortSignal signal,
  );
}

extension type _CredentialRow(JSObject _) implements JSObject {
  external String? get walletKey;
  external BrowserCredentialRecord? get record;
}

JSObject _row(String slot, BrowserCredentialRecord record) =>
    _object({'slot': slot, 'walletKey': record.key, 'record': record});

final class _IndexedDbCredentialStore implements BrowserCredentialStore {
  _IndexedDbCredentialStore(this._environment);

  final _VaultEnvironment _environment;
  Future<web.IDBDatabase>? _opening;

  Future<web.IDBDatabase> _open() {
    final existing = _opening;
    if (existing != null) return existing;
    final factory = _environment.indexedDB ?? _fail('unavailable');
    final request = factory.open(_databaseName, _schema);
    final completer = Completer<web.IDBDatabase>();
    final opening = _opening = completer.future;
    void forget() {
      if (identical(_opening, opening)) _opening = null;
    }

    void reject(String code) {
      forget();
      if (!completer.isCompleted) completer.completeError(_VaultFailure(code));
    }

    request.onupgradeneeded = (() {
      try {
        final db = request.result as web.IDBDatabase;
        db
            .createObjectStore(
              _storeName,
              web.IDBObjectStoreParameters(keyPath: 'slot'.toJS),
            )
            .createIndex('walletKey', 'walletKey'.toJS);
      } on Object {
        request.transaction?.abort();
        reject('storageFailed');
      }
    }).toJS;
    request.onerror = (() => reject('storageFailed')).toJS;
    request.onblocked = (() => reject('busy')).toJS;
    request.onsuccess = (() {
      final db = request.result as web.IDBDatabase;
      if (completer.isCompleted) {
        db.close();
        return;
      }
      db.onversionchange = (() {
        db.close();
        forget();
      }).toJS;
      // Safari can close the database while the page is in the background.
      db.onclose = forget.toJS;
      completer.complete(db);
    }).toJS;
    return opening;
  }

  web.IDBTransaction _begin(web.IDBDatabase database, String mode) {
    try {
      return database.transaction(
        _storeName.toJS,
        mode,
        web.IDBTransactionOptions(durability: 'strict'),
      );
    } on Object catch (error) {
      if (_errorName(error) == 'InvalidStateError') rethrow;
      // Some engines do not support durability options.
      return database.transaction(_storeName.toJS, mode);
    }
  }

  Future<JSAny?> _transaction(
    String mode,
    void Function(_VaultTransaction) start, {
    web.AbortSignal? signal,
  }) async {
    web.IDBTransaction transaction;
    try {
      transaction = _begin(await _open(), mode);
    } on Object catch (error) {
      if (_errorName(error) != 'InvalidStateError') rethrow;
      // No request was queued. Reopen a silently closed connection once.
      _opening = null;
      transaction = _begin(await _open(), mode);
    }
    final work = _VaultTransaction(transaction, signal);
    work.run(start);
    return work.result;
  }

  Future<BrowserCredentialRecord?> _getSlot(String slot) async =>
      (await _transaction('readonly', (work) {
        work.read(work.store.get(slot.toJS), (value) {
          work.value = (value as _CredentialRow?)?.record;
        });
      })) as BrowserCredentialRecord?;

  @override
  Future<BrowserCredentialRecord?> get(String key) => _getSlot('active:$key');

  @override
  Future<BrowserCredentialRecord?> getStaged(String slot) => _getSlot(slot);

  @override
  Future<String> stage(
    BrowserCredentialRecord record,
    String identifier,
  ) async {
    final slot = 'staged:$identifier';
    await _transaction('readwrite', (work) {
      work.store.add(_row(slot, record));
    });
    return slot;
  }

  @override
  Future<void> discardStage(String slot) async {
    if (!slot.startsWith('staged:')) _fail('invalidResponse');
    await _transaction('readwrite', (work) {
      work.store.delete(slot.toJS);
    });
  }

  void _confirmedRevision(
    _VaultTransaction work,
    String key,
    int? expectedRevision,
    void Function() action,
  ) {
    work.read(work.store.get('active:$key'.toJS), (value) {
      final current = (value as _CredentialRow?)?.record?.rawRevision;
      if (current == null
          ? expectedRevision != null
          : !_sameObject(current, expectedRevision?.toJS)) {
        work.abort('staleOperation');
        return;
      }
      action();
    });
  }

  void _removeRows(_VaultTransaction work, String key, void Function() after) {
    work.read(work.store.index('walletKey').getAllKeys(key.toJS), (keys) {
      for (final slot in (keys as JSArray<JSAny?>).toDart) {
        work.store.delete(slot);
      }
      after();
    });
  }

  @override
  Future<void> promote(
    String key,
    int? expectedRevision,
    String stageSlot,
    int stagedRevision,
    web.AbortSignal signal,
  ) async {
    await _transaction('readwrite', (work) {
      _confirmedRevision(work, key, expectedRevision, () {
        work.read(work.store.get(stageSlot.toJS), (value) {
          final row = value as _CredentialRow?;
          final record = row?.record;
          if (record == null ||
              row!.walletKey != key ||
              record.revision != stagedRevision) {
            work.abort('staleOperation');
            return;
          }
          // Promote exactly the row whose decryption was verified.
          _removeRows(
            work,
            key,
            () => work.store.put(_row('active:$key', record)),
          );
        });
      });
    }, signal: signal);
  }

  @override
  Future<void> remove(
    String key,
    int? expectedRevision,
    web.AbortSignal signal,
  ) async {
    await _transaction('readwrite', (work) {
      _confirmedRevision(work, key, expectedRevision, () {
        _removeRows(work, key, () {});
      });
    }, signal: signal);
  }
}

/// Every IndexedDB request is queued synchronously in its event callback.
/// The result resolves on transaction commit, after writes are durable.
final class _VaultTransaction {
  _VaultTransaction(this._transaction, this._signal);

  final web.IDBTransaction _transaction;
  final web.AbortSignal? _signal;
  final _complete = Completer<JSAny?>();
  late final JSFunction _cancel = (() => abort('staleOperation')).toJS;
  String? _failure;
  JSAny? value;

  Future<JSAny?> get result => _complete.future;
  web.IDBObjectStore get store => _transaction.objectStore(_storeName);

  void run(void Function(_VaultTransaction) start) {
    _transaction.oncomplete = (() {
      _cleanup();
      if (!_complete.isCompleted) _complete.complete(value);
    }).toJS;
    final failed = (() => _reject()).toJS;
    _transaction.onabort = failed;
    _transaction.onerror = failed;
    if (_signal?.aborted == true) {
      abort('staleOperation');
      return;
    }
    _signal?.addEventListener(
      'abort',
      _cancel,
      web.AddEventListenerOptions(once: true),
    );
    _guard(() => start(this));
  }

  void read(web.IDBRequest request, void Function(JSAny? value) action) {
    request.onsuccess = (() => _guard(() => action(request.result))).toJS;
  }

  void _guard(void Function() action) {
    try {
      action();
    } on Object catch (error) {
      abort(_safeFailure(error).code);
    }
  }

  void abort(String code) {
    _failure = code;
    try {
      _transaction.abort();
    } on Object {
      // The transaction may have completed before cancellation arrived.
      if (!_complete.isCompleted) _reject();
    }
  }

  void _cleanup() => _signal?.removeEventListener('abort', _cancel);

  void _reject() {
    _cleanup();
    if (!_complete.isCompleted) {
      _complete.completeError(_VaultFailure(_failure ?? 'storageFailed'));
    }
  }
}
