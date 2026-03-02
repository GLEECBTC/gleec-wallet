@JS()
library wasmlib;

import 'package:js/js.dart';

@JS('init_wasm')
external dynamic initWasm();

@JS('run_mm2')
external Future<void> wasmRunMm2(
  String params,
  void Function(int, String) handleLog,
);

@JS('mm2_status')
external dynamic wasmMm2Status();

@JS('mm2_version')
external String wasmVersion();

@JS('rpc_request')
external Future<dynamic> wasmRpc(String request);

@JS('reload_page')
external void reloadPage();

@JS('changeTheme')
external void changeHtmlTheme(int themeIndex);
