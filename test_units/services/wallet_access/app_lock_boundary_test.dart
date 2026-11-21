import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/views/common/wallet_access/app_lock_boundary.dart';

void main() {
  testWidgets('fallback authentication works above the blocked navigator', (
    tester,
  ) async {
    final coordinator = WalletUnlockCoordinator(
      operationGate: WalletOperationGate(),
    );
    addTearDown(coordinator.dispose);
    coordinator.attachWallet('a', requiresAuthentication: true);
    var passwordSubmits = 0;
    var sends = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppLockBoundary(
          coordinator: coordinator,
          observeLifecycle: false,
          onUnlock: () {},
          authenticationContent: Center(
            child: TextButton(
              onPressed: () => passwordSubmits++,
              child: const Text('Confirm password'),
            ),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: TextButton(
            onPressed: () => sends++,
            child: const Text('Send funds'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Confirm password'));
    expect(passwordSubmits, 1);
    expect(sends, 0);
    expect(coordinator.operationGate.allowsOperations, isFalse);
    coordinator.inactive();
    await tester.pump();
    expect(find.text('Confirm password'), findsNothing);
  });

  testWidgets('root lock excludes content and dialogs from semantics/actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final coordinator = WalletUnlockCoordinator(
      operationGate: WalletOperationGate(),
    );
    addTearDown(coordinator.dispose);
    coordinator.attachWallet(
      'a',
      requiresAuthentication: true,
      authenticated: true,
    );
    var financialActions = 0;
    var unlocks = 0;
    late BuildContext innerContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppLockBoundary(
          coordinator: coordinator,
          observeLifecycle: false,
          onUnlock: () => unlocks++,
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              innerContext = context;
              return TextButton(
                onPressed: () => financialActions++,
                child: const Text('Send all funds'),
              );
            },
          ),
        ),
      ),
    );
    if (!innerContext.mounted) throw StateError('Test context is not mounted');
    showDialog<void>(
      context: innerContext,
      builder: (_) => const AlertDialog(content: Text('Private phrase')),
    );
    await tester.pumpAndSettle();
    coordinator.lock();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wallet-lock-screen')), findsOneWidget);
    expect(find.semantics.byLabel('Private phrase'), findsNothing);
    expect(find.semantics.byLabel('Send all funds'), findsNothing);
    await tester.tap(find.byKey(const Key('wallet-lock-unlock')));
    expect(unlocks, 1);
    expect(financialActions, 0);

    coordinator.inactive();
    await tester.pump();
    expect(find.byKey(const Key('wallet-privacy-cover')), findsOneWidget);
    expect(find.byKey(const Key('wallet-lock-unlock')), findsNothing);
    semantics.dispose();
  });

  testWidgets('lock remains usable at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final coordinator = WalletUnlockCoordinator(
      operationGate: WalletOperationGate(),
    );
    addTearDown(coordinator.dispose);
    coordinator.attachWallet('a', requiresAuthentication: true);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: AppLockBoundary(
            coordinator: coordinator,
            observeLifecycle: false,
            onUnlock: () {},
            onUsePassword: () {},
            onSwitchWallet: () {},
            onRecoverWallet: () {},
            child: child!,
          ),
        ),
        home: const Scaffold(body: Text('Sensitive balance')),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('wallet-lock-unlock')), findsOneWidget);
  });
}
