import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';

void main() {
  group('WalletOperationGate', () {
    test('uninstalled headless gate is permissive', () {
      WalletOperationGate().capture().ensureCurrent();
    });

    test('installation invalidates earlier unguarded permits', () {
      final gate = WalletOperationGate();
      final old = gate.capture();
      gate.attachWallet('a', allowOperations: true);
      expect(old.ensureCurrent, throwsA(isA<WalletOperationDenied>()));
    });

    test('queued operation cannot dispatch after lock and unlock', () {
      final gate = WalletOperationGate()
        ..attachWallet('a', allowOperations: true);
      final old = gate.capture(expectedWalletEntryId: 'a');
      gate.block();
      expect(old.ensureCurrent, throwsA(isA<WalletOperationDenied>()));
      gate.allow(walletEntryId: 'a');
      expect(old.ensureCurrent, throwsA(isA<WalletOperationDenied>()));
      gate.capture(expectedWalletEntryId: 'a').ensureCurrent();
    });

    test('wallet and session identity are independently enforced', () {
      final gate = WalletOperationGate()
        ..attachWallet('a', sessionIdentity: Object(), allowOperations: true);
      expect(
        () => gate.capture(expectedWalletEntryId: 'b'),
        throwsA(isA<WalletOperationDenied>()),
      );
      final old = gate.capture();
      gate.attachWallet('a', sessionIdentity: Object(), allowOperations: true);
      expect(old.ensureCurrent, throwsA(isA<WalletOperationDenied>()));
      final beforeSwitch = gate.capture();
      gate.attachWallet('b', allowOperations: true);
      expect(beforeSwitch.ensureCurrent, throwsA(isA<WalletOperationDenied>()));
    });

    test('signed out authority cannot be enabled by an old identity', () {
      final gate = WalletOperationGate()..attachWallet(null);
      expect(gate.capture, throwsA(isA<WalletOperationDenied>()));
      expect(
        () => gate.allow(walletEntryId: 'a'),
        throwsA(isA<WalletOperationDenied>()),
      );
    });

    test('same session observation does not invalidate a valid action', () {
      final session = Object();
      final gate = WalletOperationGate()
        ..attachWallet('a', sessionIdentity: session, allowOperations: true);
      final pending = gate.capture();
      gate.attachWallet('a', sessionIdentity: session, allowOperations: true);
      pending.ensureCurrent();
    });
  });
}
