import 'dart:js_interop';

@JS()
external JSPromise<JSAny?> initWasm();

@JS('run_mm2')
external JSPromise<JSAny?> wasmRunMm2(String params, JSFunction handleLog);

@JS('mm2_status')
external JSAny? wasmMm2Status();

@JS('mm2_version')
external String wasmVersion();

@JS('rpc_request')
external JSPromise<JSAny?> wasmRpc(String request);

@JS('reload_page')
external void reloadPage();

@JS('changeTheme')
external void changeHtmlTheme(int themeIndex);
