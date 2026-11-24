part of 'browser_credential_vault.dart';

@JS('Object.freeze')
external JSObject _freeze(JSObject object);

@JS('Error')
extension type _VaultJsError._(JSObject _) implements JSObject {
  external factory _VaultJsError(String message);

  external set name(String value);
  external set code(String value);
}

extension type _VaultArguments(JSObject _) implements JSObject {
  JSAny? _value(String key) => getProperty<JSAny?>(key.toJS);

  String? text(String key) {
    final value = _value(key);
    if (value == null) return null;
    if (!value.isA<JSString>()) _fail('invalidResponse');
    return (value as JSString).toDart;
  }

  String requireText(String key) => text(key) ?? _fail('invalidResponse');

  bool flag(String key) => _sameObject(_value(key), true.toJS);

  int revision() {
    final revision = _safeInteger(_value('expectedRevision'));
    if (revision == null || revision < 1) _fail('invalidResponse');
    return revision;
  }
}

JSPromise<JSAny?> _jsOperation(FutureOr<Object?> Function() action) =>
    JSPromise<JSAny?>(
      ((JSFunction resolve, JSFunction reject) {
        unawaited(
          Future<Object?>.sync(action).then<void>(
            (value) {
              resolve.callAsFunction(null, value.jsify());
            },
            onError: (Object error) {
              final code = _safeFailure(error).code;
              reject.callAsFunction(
                null,
                _VaultJsError(code)
                  ..name = 'WalletCredentialError'
                  ..code = code,
              );
            },
          ),
        );
      }).toJS,
    );

/// The existing browser-facing contract, backed by the Dart vault in either
/// compiler. Release probes and the app share the same promise and event API.
JSObject createBrowserCredentialApi(BrowserCredentialVault vault) {
  final api = JSObject();
  void method(String name, FutureOr<Object?> Function(_VaultArguments) action) {
    api.setProperty(
      name.toJS,
      ((JSObject args) => _jsOperation(
        () => action(_VaultArguments(args)),
      )).toJS,
    );
  }

  api.setProperty(
    'capabilities'.toJS,
    (() => _jsOperation(vault.capabilities)).toJS,
  );
  api.setProperty('cancel'.toJS, vault.cancel.toJS);
  api.setProperty('subscribe'.toJS, vault.subscribe.toJS);

  method('metadata', (args) => vault.metadata(args.requireText('key')));
  method('write', (args) async {
    await vault.write(
      args.requireText('key'),
      args.requireText('value'),
      requireAuthentication: args.flag('requireAuthentication'),
    );
    return null;
  });
  method(
    'read',
    (args) => vault.read(
      args.requireText('key'),
      requireAuthentication: args.flag('requireAuthentication'),
      automatic: args.text('trigger') == 'automatic',
      purpose: args.text('purpose'),
    ),
  );
  method(
    'prepareDelete',
    (args) => vault.prepareDelete(args.requireText('key')),
  );
  method(
    'prepareDeleteAfterPasswordVerification',
    (args) => vault.prepareDeleteAfterPasswordVerification(
      args.requireText('key'),
      args.revision(),
    ),
  );
  method('delete', (args) async {
    await vault.delete(args.requireText('key'), args.text('authorization'));
    return null;
  });
  method(
    'enrollPasskey',
    (args) => vault.enrollPasskey(
      args.requireText('key'),
      args.requireText('value'),
      args.text('label') ?? 'Gleec Wallet',
    ),
  );
  method(
    'replacePasskeyAfterPasswordVerification',
    (args) => vault.replacePasskeyAfterPasswordVerification(
      args.requireText('key'),
      args.requireText('value'),
      args.revision(),
      args.text('label') ?? 'Gleec Wallet',
    ),
  );
  method(
    'savePassword',
    (args) => vault.savePassword(
      args.requireText('username'),
      args.requireText('password'),
      args.text('title') ?? 'Gleec Wallet',
    ),
  );
  return _freeze(api);
}
