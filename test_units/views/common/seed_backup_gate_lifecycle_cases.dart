part of 'seed_backup_gate_test.dart';

const _phones = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.android,
  TargetPlatform.iOS,
});
const _desktops = TargetPlatformVariant(<TargetPlatform>{
  TargetPlatform.macOS,
  TargetPlatform.windows,
  TargetPlatform.linux,
});
const _interrupted = Key('seed-backup-gate-interrupted');

/// Opens the gate, authorizes, and reveals the words on the first step.
Future<void> _revealWords(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  await tester.tap(find.text('reveal'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('seed-backup-gate-backup-button')));
  await tester.pumpAndSettle();
  tester
      .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
      .onSuccess('test-password');
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('seed-show-switch')));
  await tester.pumpAndSettle();
  expect(_wordsShown(tester), isTrue);
}

/// Walks the app out to [state] and back in the order a platform reports it.
Future<void> _leaveAndReturn(
  WidgetTester tester,
  AppLifecycleState state,
) async {
  const away = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ];
  final out = away.sublist(0, away.indexOf(state) + 1);
  final back = state == AppLifecycleState.detached
      ? const <AppLifecycleState>[]
      : out.reversed.skip(1);
  for (final step in [...out, ...back, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(step);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

bool _wordsShown(WidgetTester tester) =>
    BlocProvider.of<SecuritySettingsBloc>(tester.element(find.byType(SeedShow)))
        .state
        .showSeedWords;

/// What the gate does when the app loses focus, is left, or is locked while
/// the recovery phrase is on screen.
void _seedBackupLifecycleCases() {
  testWidgets(
    'on a phone, inactivity covers the words again and keeps the step',
    (tester) async {
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(_user(hasBackup: false)),
      );
      addTearDown(authBloc.close);
      final results = await _pumpGate(tester, authBloc: authBloc);
      await _revealWords(tester);
      // The notification shade, or the moment before the app switcher.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(SeedShow), findsOneWidget);
      expect(_wordsShown(tester), isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(SeedShow), findsOneWidget);
      expect(find.byKey(_interrupted), findsNothing);
      expect(results, isEmpty);
    },
    variant: _phones,
  );

  testWidgets(
    'on desktop, clicking another window leaves the words on screen',
    (tester) async {
      final authBloc = _FakeAuthBloc(
        AuthBlocState.loggedIn(_user(hasBackup: false)),
      );
      addTearDown(authBloc.close);
      final results = await _pumpGate(tester, authBloc: authBloc);
      await _revealWords(tester);
      // The notes app the words are being typed into.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.byType(SeedShow), findsOneWidget);
      expect(_wordsShown(tester), isTrue);
      expect(find.byKey(_interrupted), findsNothing);
      expect(results, isEmpty);
    },
    variant: _desktops,
  );

  for (final leaving in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets(
      'leaving the app (${leaving.name}) ends the backup without a grace '
      'period and says why on return',
      (tester) async {
        final authBloc = _FakeAuthBloc(
          AuthBlocState.loggedIn(_user(hasBackup: false)),
        );
        addTearDown(authBloc.close);
        final results = await _pumpGate(tester, authBloc: authBloc);
        await _revealWords(tester);
        await _leaveAndReturn(tester, leaving);
        expect(find.byType(SeedShow), findsNothing);
        // The gate is still there, with the reason and a way to restart.
        expect(find.byKey(_interrupted), findsOneWidget);
        expect(find.text('authRecoveryHiddenLeftApp'), findsOneWidget);
        expect(results, isEmpty);
        await tester.tap(
          find.byKey(const Key('seed-backup-gate-backup-button')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(_interrupted), findsNothing);
        expect(find.byType(PasswordDialogContent), findsOneWidget);
        // Close the prompt so its polling timer does not outlive the test.
        tester
            .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
            .onCancel();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();
      },
      variant: const TargetPlatformVariant(<TargetPlatform>{
        TargetPlatform.android,
        TargetPlatform.macOS,
      }),
    );
  }

  for (final locksAtOnce in [false, true]) {
    testWidgets(
      'on desktop, lost focus reported by the wallet lock '
      '${locksAtOnce ? 'ends the backup when it locks the wallet' : 'is ignored while the wallet stays unlocked'}',
      (tester) async {
        final user = _user(hasBackup: false);
        final authBloc = _FakeAuthBloc(AuthBlocState.loggedIn(user));
        final access = _Access(user.walletId);
        addTearDown(authBloc.close);
        addTearDown(access.unlockCoordinator.dispose);
        if (locksAtOnce) {
          access.unlockCoordinator.setBackgroundGrace(Duration.zero);
        }
        final results = await _pumpGate(
          tester,
          authBloc: authBloc,
          access: access,
        );
        await _revealWords(tester);
        // What the app lock does when the window loses focus.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        access.unlockCoordinator.inactive();
        await tester.pumpAndSettle();
        expect(
          find.byType(SeedShow),
          locksAtOnce ? findsNothing : findsOneWidget,
        );
        expect(
          find.byKey(_interrupted),
          locksAtOnce ? findsOneWidget : findsNothing,
        );
        expect(results, isEmpty);
      },
      variant: _desktops,
    );
  }
}
