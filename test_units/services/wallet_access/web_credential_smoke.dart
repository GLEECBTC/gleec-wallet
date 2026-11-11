import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import 'package:web_dex/services/wallet_access/platform/web_credential_backend.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final backend = WebCredentialBackend();
  Future<JSAny?> exercise(JSString action) async {
    try {
      switch (action.toDart) {
        case 'write':
          await backend.write(
            'flutter-web-fixture',
            'Unfunded-fixture-42@',
            requireAuthentication: false,
          );
          return 'written'.toJS;
        case 'read':
          final value = await backend.read(
            'flutter-web-fixture',
            reason: 'Test wallet',
          );
          return (value == 'Unfunded-fixture-42@').toJS;
        case 'enroll':
          await backend.enrollPasskey(
            'flutter-web-fixture',
            'Unfunded-fixture-42@',
            label: 'Unfunded fixture',
          );
          return 'enrolled'.toJS;
        case 'authenticationRequired':
          await backend.read(
            'flutter-web-fixture',
            reason: 'Test wallet',
            requireAuthentication: true,
          );
          return 'unexpectedSuccess'.toJS;
        case 'delete':
          final authorization = await backend.prepareDelete(
            'flutter-web-fixture',
            reason: 'Delete test wallet',
          );
          await backend.delete(
            'flutter-web-fixture',
            authorization: authorization,
          );
          return 'deleted'.toJS;
      }
      return 'unknown'.toJS;
    } on WalletAccessException catch (error) {
      return error.failure.name.toJS;
    }
  }

  web.window.setProperty(
    'gleecCredentialSmoke'.toJS,
    ((JSString action) => exercise(action).toJS).toJS,
  );
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Credential bridge fixture ready')),
      ),
    ),
  );
}
