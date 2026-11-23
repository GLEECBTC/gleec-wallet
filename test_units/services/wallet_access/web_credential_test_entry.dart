import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;
import 'package:web_dex/services/wallet_access/platform/browser_credential_vault.dart';

// Let the existing Node protocol fixtures drive the exact Dart vault used
// in the app. No fixture store or factory is exported by the Flutter bundle.
void main() {
  globalContext.setProperty(
    'createGleecTestVault'.toJS,
    ((JSObject environment, JSObject? options) {
      final store = options?.getProperty<JSObject?>('store'.toJS);
      return createBrowserCredentialApi(
        BrowserCredentialVault(
          environment,
          store: store == null ? null : _FixtureStore(store),
        ),
      );
    }).toJS,
  );
}

final class _FixtureStore implements BrowserCredentialStore {
  _FixtureStore(this._store);

  final JSObject _store;

  Future<JSAny?> _call(String method, List<JSAny?> args) =>
      _store.callMethodVarArgs<JSPromise<JSAny?>>(method.toJS, args).toDart;

  @override
  Future<BrowserCredentialRecord?> get(String key) async =>
      (await _call('get', [key.toJS])) as BrowserCredentialRecord?;

  @override
  Future<BrowserCredentialRecord?> getStaged(String slot) async =>
      (await _call('getStaged', [slot.toJS])) as BrowserCredentialRecord?;

  @override
  Future<String> stage(
    BrowserCredentialRecord record,
    String identifier,
  ) async =>
      (await _call('stage', [record, identifier.toJS]) as JSString).toDart;

  @override
  Future<void> discardStage(String slot) async {
    await _call('discardStage', [slot.toJS]);
  }

  @override
  Future<void> promote(
    String key,
    int? expectedRevision,
    String stageSlot,
    int stagedRevision,
    web.AbortSignal signal,
  ) async {
    await _call('promote', [
      key.toJS,
      expectedRevision?.toJS,
      stageSlot.toJS,
      stagedRevision.toJS,
      signal,
    ]);
  }

  @override
  Future<void> remove(
    String key,
    int? expectedRevision,
    web.AbortSignal signal,
  ) async {
    await _call('remove', [key.toJS, expectedRevision?.toJS, signal]);
  }
}
