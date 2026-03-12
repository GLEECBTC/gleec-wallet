import 'dart:js_interop';

@JS('kdf')
external _KdfBindings? get _kdfBindings;

@JS()
extension type _KdfBindings._(JSObject _) implements JSObject {
  @JS('init_wasm')
  external JSPromise<JSAny?> initWasm();

  @JS('run_mm2')
  external JSPromise<JSAny?> runMm2(String params, JSFunction handleLog);

  @JS('mm2_status')
  external JSAny? mm2Status();

  @JS('mm2_version')
  external String mm2Version();

  @JS('rpc_request')
  external JSPromise<JSAny?> rpcRequest(String request);

  @JS('reload_page')
  external void reloadPage();
}

_KdfBindings _requireKdfBindings() {
  final bindings = _kdfBindings;
  if (bindings == null) {
    throw StateError('KDF bootstrap is not loaded');
  }
  return bindings;
}

JSPromise<JSAny?> initWasm() => _requireKdfBindings().initWasm();

JSPromise<JSAny?> wasmRunMm2(String params, JSFunction handleLog) =>
    _requireKdfBindings().runMm2(params, handleLog);

JSAny? wasmMm2Status() => _requireKdfBindings().mm2Status();

String wasmVersion() => _requireKdfBindings().mm2Version();

JSPromise<JSAny?> wasmRpc(String request) =>
    _requireKdfBindings().rpcRequest(request);

void reloadPage() => _requireKdfBindings().reloadPage();

@JS('changeTheme')
external void changeHtmlTheme(int themeIndex);
