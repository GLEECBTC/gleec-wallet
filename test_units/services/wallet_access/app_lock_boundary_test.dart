import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/views/common/wallet_access/app_lock_boundary.dart';

const _desktop = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
});
const _handheld = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.android,
  TargetPlatform.iOS,
});

/// A signed-in wallet with a text field being edited under the boundary.
class _Editing {
  _Editing(this.tester) {
    coordinator = WalletUnlockCoordinator(
      operationGate: WalletOperationGate(),
      monotonicNow: () => now,
    );
    addTearDown(coordinator.dispose);
    addTearDown(field.dispose);
    addTearDown(() => lifecycle(AppLifecycleState.resumed));
    coordinator.attachWallet(
      'a',
      requiresAuthentication: true,
      authenticated: true,
    );
  }

  final WidgetTester tester;
  final field = FocusNode(debugLabel: 'address field');
  late final WalletUnlockCoordinator coordinator;
  Duration now = Duration.zero;

  Finder get cover => find.byKey(const Key('wallet-privacy-cover'));
  Finder get lock => find.byKey(const Key('wallet-lock-screen'));

  Future<void> pump() async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppLockBoundary(
          coordinator: coordinator,
          onUnlock: () {
            final attempt = coordinator.beginUnlock();
            if (attempt != null) coordinator.completeUnlock(attempt);
          },
          child: child!,
        ),
        home: Scaffold(body: TextField(focusNode: field, autofocus: true)),
      ),
    );
    await tester.pump();
    expect(field.hasFocus, isTrue);
  }

  /// Walks to [target] through the states the platform reports in between.
  Future<void> lifecycle(AppLifecycleState target) async {
    const order = [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    var at = order.indexOf(
      tester.binding.lifecycleState ?? AppLifecycleState.resumed,
    );
    final end = order.indexOf(target);
    while (at != end) {
      at += end > at ? 1 : -1;
      tester.binding.handleAppLifecycleStateChanged(order[at]);
    }
    await tester.pump();
    await tester.pump();
  }
}

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

  for (final brightness in Brightness.values) {
    testWidgets(
      'lock holds at 320 dp and 200% text in the $brightness app theme',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final coordinator = WalletUnlockCoordinator(
          operationGate: WalletOperationGate(),
        );
        addTearDown(coordinator.dispose);
        coordinator.attachWallet('a', requiresAuthentication: true);
        final appTheme = brightness == Brightness.dark
            ? theme.global.dark
            : theme.global.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: AppLockBoundary(
                coordinator: coordinator,
                observeLifecycle: false,
                onUnlock: () {},
                onUsePassword: () {},
                onSwitchWallet: () {},
                onRecoverWallet: () {},
                labels: const WalletLockLabels(
                  title: 'Unlock Everyday savings wallet',
                  unlock: 'Unlock with this device',
                ),
                errorMessage:
                    'Unlock canceled. You can try again or use another option.',
                child: child!,
              ),
            ),
            home: const Scaffold(body: Text('Sensitive balance')),
          ),
        );
        expect(tester.takeException(), isNull);
        final title = find.text('Unlock Everyday savings wallet');
        expect(
          tester.widget<Text>(title).style?.fontSize,
          appTheme.textTheme.titleLarge?.fontSize,
        );
        expect(tester.getSize(title).width, lessThanOrEqualTo(320 - 48));
        for (final key in [
          'wallet-lock-unlock',
          'wallet-lock-use-password',
          'wallet-lock-switch-wallet',
          'wallet-lock-recover-wallet',
        ]) {
          final action = find.byKey(Key(key));
          await tester.ensureVisible(action);
          await tester.pump();
          expect(action.hitTestable(), findsOneWidget, reason: key);
          expect(
            tester.getSize(action).height,
            greaterThanOrEqualTo(48),
            reason: key,
          );
          expect(tester.takeException(), isNull, reason: key);
        }
        // The whole method label is shown, however many lines it takes.
        final label = find.descendant(
          of: find.byKey(const Key('wallet-lock-unlock')),
          matching: find.text('Unlock with this device'),
        );
        expect(
          tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
          isFalse,
        );
      },
    );
  }

  testWidgets('Enter and Space activate the primary unlock action', (
    tester,
  ) async {
    final coordinator = WalletUnlockCoordinator(
      operationGate: WalletOperationGate(),
    );
    addTearDown(coordinator.dispose);
    coordinator.attachWallet('a', requiresAuthentication: true);
    var unlocks = 0;
    var passwords = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppLockBoundary(
          coordinator: coordinator,
          observeLifecycle: false,
          onUnlock: () => unlocks++,
          onUsePassword: () => passwords++,
          child: child!,
        ),
        home: const Scaffold(body: Text('Sensitive balance')),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(unlocks, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(unlocks, 2);
    expect(passwords, 0);
  });

  testWidgets('a busy unlock keeps keyboard focus on the primary action', (
    tester,
  ) async {
    final coordinator = WalletUnlockCoordinator(
      operationGate: WalletOperationGate(),
    );
    addTearDown(coordinator.dispose);
    coordinator.attachWallet('a', requiresAuthentication: true);
    var unlocks = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppLockBoundary(
          coordinator: coordinator,
          observeLifecycle: false,
          onUnlock: () => unlocks++,
          child: child!,
        ),
        home: const Scaffold(body: Text('Sensitive balance')),
      ),
    );
    await tester.pump();
    final primary = find.byKey(const Key('wallet-lock-unlock'));
    FocusNode focused() => Focus.of(
      tester.element(find.descendant(of: primary, matching: find.byType(Text))),
    );
    expect(focused().hasFocus, isTrue);

    final attempt = coordinator.beginUnlock()!;
    await tester.pump();
    await tester.pump();
    expect(find.text('Unlocking…'), findsOneWidget);
    expect(focused().hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(unlocks, 0, reason: 'A press while busy must not start another');

    coordinator.cancelUnlock(attempt);
    await tester.pump();
    await tester.pump();
    expect(focused().hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(unlocks, 1);
  });

  testWidgets(
    'losing window focus neither covers the wallet nor starts the clock',
    (tester) async {
      final editing = _Editing(tester);
      await editing.pump();
      await editing.lifecycle(AppLifecycleState.inactive);
      expect(editing.cover, findsNothing);
      expect(editing.coordinator.state.isObscured, isFalse);
      expect(editing.coordinator.operationGate.allowsOperations, isTrue);

      // Far beyond the grace period: reading beside another window is not
      // time away.
      editing.now += const Duration(hours: 1);
      await editing.lifecycle(AppLifecycleState.resumed);
      expect(editing.coordinator.state.isLocked, isFalse);
      expect(editing.cover, findsNothing);
      expect(editing.lock, findsNothing);
      expect(editing.field.hasFocus, isTrue);
    },
    variant: _desktop,
  );

  testWidgets(
    'a hidden window is covered at once and locks after the grace period',
    (tester) async {
      final editing = _Editing(tester);
      await editing.pump();
      await editing.lifecycle(AppLifecycleState.hidden);
      expect(editing.cover, findsOneWidget);
      expect(editing.coordinator.operationGate.allowsOperations, isFalse);

      editing.now += const Duration(seconds: 5);
      await editing.lifecycle(AppLifecycleState.resumed);
      expect(editing.cover, findsNothing);
      expect(editing.lock, findsNothing);
      expect(
        editing.field.hasFocus,
        isTrue,
        reason: 'A cover that lifts on its own returns focus to the field',
      );

      await editing.lifecycle(AppLifecycleState.hidden);
      editing.now += const Duration(minutes: 5);
      await editing.lifecycle(AppLifecycleState.resumed);
      expect(editing.lock, findsOneWidget);
      expect(editing.coordinator.state.isLocked, isTrue);
    },
    variant: _desktop,
  );

  testWidgets(
    'on a phone, inactivity covers the wallet and focus returns with it',
    (tester) async {
      final editing = _Editing(tester);
      await editing.pump();
      await editing.lifecycle(AppLifecycleState.inactive);
      expect(editing.cover, findsOneWidget);
      expect(editing.field.hasFocus, isFalse);
      expect(editing.coordinator.operationGate.allowsOperations, isFalse);

      editing.now += const Duration(seconds: 5);
      await editing.lifecycle(AppLifecycleState.resumed);
      expect(editing.cover, findsNothing);
      expect(editing.field.hasFocus, isTrue);

      // The clock still starts at the first interruption.
      await editing.lifecycle(AppLifecycleState.inactive);
      editing.now += const Duration(minutes: 5);
      await editing.lifecycle(AppLifecycleState.resumed);
      expect(editing.lock, findsOneWidget);
    },
    variant: _handheld,
  );

  testWidgets('focus is not handed back after a lock was required', (
    tester,
  ) async {
    final editing = _Editing(tester);
    await editing.pump();
    await editing.lifecycle(AppLifecycleState.paused);
    editing.now += const Duration(minutes: 5);
    await editing.lifecycle(AppLifecycleState.resumed);
    expect(editing.lock, findsOneWidget);

    await tester.tap(find.byKey(const Key('wallet-lock-unlock')));
    await tester.pump();
    await tester.pump();
    expect(editing.lock, findsNothing);
    expect(editing.field.hasFocus, isFalse);
  });

  testWidgets('the cover brings an overlay for text selection and tooltips', (
    tester,
  ) async {
    final coordinator = WalletUnlockCoordinator(
      operationGate: WalletOperationGate(),
    );
    addTearDown(coordinator.dispose);
    coordinator.attachWallet('a', requiresAuthentication: true);
    // The toolbar asks the clipboard whether Paste applies.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => call.method == 'Clipboard.hasStrings'
          ? <String, dynamic>{'value': true}
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => AppLockBoundary(
          coordinator: coordinator,
          observeLifecycle: false,
          onUnlock: () {},
          authenticationContent: const Center(
            child: Tooltip(
              message: 'Show password',
              child: TextField(key: Key('cover-field')),
            ),
          ),
          child: child!,
        ),
        home: const Scaffold(body: Text('Sensitive balance')),
      ),
    );
    final field = tester.element(find.byKey(const Key('cover-field')));
    final overlay = Overlay.maybeOf(field);
    expect(overlay, isNotNull);
    // Not the Navigator's: that one is under the cover.
    expect(
      find.ancestor(
        of: find.byWidget(overlay!.widget),
        matching: find.byType(Navigator),
      ),
      findsNothing,
    );
    // It spans the boundary, so toolbars are placed in screen coordinates.
    expect(
      tester.getSize(find.byWidget(overlay.widget)),
      tester.getSize(find.byType(MaterialApp)),
    );

    final input = find.byKey(const Key('cover-field'));
    await tester.enterText(input, 'selectable');
    await tester.longPressAt(tester.getTopLeft(input) + const Offset(24, 24));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
  });
}
