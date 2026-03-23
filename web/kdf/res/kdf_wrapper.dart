// NB! This file is not currently used and will possibly be removed in the
// future. We can consider migrating the KDF JS bootstrapper to Dart and
// compile to JavaScript.

// ignore_for_file: avoid_dynamic_calls

import 'dart:async';
// This is a web-specific file, so it's safe to ignore this warning
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart';

@JS('mm2_main')
external JSAny? _mm2MainJs(String conf, JSFunction logCallback);

@JS('mm2_main_status')
external JSAny? _mm2MainStatusJs();

@JS('mm2_stop')
external JSAny? _mm2StopJs();

class KdfPlugin {
  static void registerWith(Registrar registrar) {
    final plugin = KdfPlugin();
    // ignore: unused_local_variable
    final channel = MethodChannel(
      'komodo_defi_framework/kdf',
      const StandardMethodCodec(),
      registrar,
    )..setMethodCallHandler(plugin.handleMethodCall);
  }

  Future<dynamic> handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'ensureLoaded':
        return _ensureLoaded();
      case 'mm2Main':
        final args = call.arguments as Map<String, dynamic>;
        return _mm2Main(
          args['conf'] as String,
          args['logCallback'] as Function,
        );
      case 'mm2MainStatus':
        return _mm2MainStatus();
      case 'mm2Stop':
        return _mm2Stop();
      default:
        throw PlatformException(
          code: 'Unimplemented',
          details: 'Method ${call.method} not implemented',
        );
    }
  }

  bool _libraryLoaded = false;
  Future<void>? _loadPromise;

  Future<void> _ensureLoaded() async {
    if (_loadPromise != null) return _loadPromise;

    _loadPromise = _loadLibrary();
    await _loadPromise;
  }

  Future<void> _loadLibrary() async {
    if (_libraryLoaded) return;

    final completer = Completer<void>();

    final script = HTMLScriptElement()
      ..src = 'kdf/kdflib.js'
      ..onload = () {
        _libraryLoaded = true;
        completer.complete();
      }.toJS
      ..onerror = (event) {
        completer.completeError('Failed to load kdflib.js');
      }.toJS;

    document.head!.appendChild(script);

    return completer.future;
  }

  Future<int> _mm2Main(String conf, Function logCallback) async {
    await _ensureLoaded();

    try {
      final jsCallback = logCallback.toJS;
      final jsResponse = _mm2MainJs(conf, jsCallback);
      if (jsResponse == null) {
        throw Exception('mm2_main call returned null');
      }

      final dynamic dartResponse = jsResponse.dartify();
      if (dartResponse == null) {
        throw Exception('Failed to convert mm2_main response to Dart');
      }

      return (dartResponse as num).toInt();
    } catch (e) {
      throw Exception('Error in mm2_main: $e\nConfig: $conf');
    }
  }

  int _mm2MainStatus() {
    if (!_libraryLoaded) {
      throw StateError('KDF library not loaded. Call ensureLoaded() first.');
    }

    final jsResult = _mm2MainStatusJs();
    return (jsResult.dartify()! as num).toInt();
  }

  Future<int> _mm2Stop() async {
    await _ensureLoaded();
    final jsResult = _mm2StopJs();
    return (jsResult.dartify()! as num).toInt();
  }
}
