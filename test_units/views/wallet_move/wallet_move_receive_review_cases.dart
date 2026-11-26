part of 'wallet_move_receive_test.dart';

/// The review after a reply opened: the check code, the import, and when
/// the opened wallet is let go.
void reviewCases() {
  testWidgets('importing waits for the check code to show', (tester) async {
    final setup = await _pumpReceive(tester);
    final gate = Completer<void>();
    setup.protocol.checkGate = gate;
    await _openReply(tester, setup);
    final offer = setup.protocol.offers.single;
    expect(offer.opened, ['GLEECMOVE1R.reply']);
    // Spent once opened: its key is forgotten at once.
    expect(offer.disposed, isTrue);
    expect(setup.device.screenOn.last, isFalse);
    expect(find.text('walletTransferReviewTitle'.tr()), findsOneWidget);
    expect(
      find.byKey(const Key('transfer-check-code-working')),
      findsOneWidget,
    );
    expect(_importEnabled(tester), isFalse);
    await _tap(tester, _import);
    expect(setup.auth.events, isEmpty);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('1234 5678'), findsOneWidget);
    expect(
      find.descendant(
        of: _import,
        matching: find.text('walletMoveReviewCodesMatch'.tr()),
      ),
      findsOneWidget,
    );
    expect(_importEnabled(tester), isTrue);
    // Said before the system asks for it.
    expect(
      tester
          .getTopLeft(find.byKey(const Key('transfer-review-screen-lock')))
          .dy,
      lessThan(tester.getTopLeft(_import).dy),
    );

    await _tap(tester, _import);
    final event = setup.auth.events.single as AuthManagedImportRequested;
    expect(event.walletName, 'Savings');
    expect(event.source, ManagedImportSource.movedFromDevice);
    expect(event.secret.seed, transferTestSeed);
  });

  testWidgets('the check code is read out when it arrives', (tester) async {
    final spoken = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        spoken.add((message as Map?)?['data']?['message']);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );
    final setup = await _pumpReceive(tester);
    final gate = Completer<void>();
    setup.protocol.checkGate = gate;
    await _openReply(tester, setup);
    expect(spoken, contains('walletTransferReviewTitle'.tr()));
    gate.complete();
    await tester.pumpAndSettle();
    expect(spoken, contains(TransferCheckCode.spoken('12345678')));
  });

  testWidgets('codes that differ discard the wallet and show a new code', (
    tester,
  ) async {
    final setup = await _pumpReceive(tester);
    await _openReply(tester, setup);
    await _tap(tester, _differ);
    expect(setup.auth.events, isEmpty);
    expect(find.text('walletTransferReviewTitle'.tr()), findsNothing);
    expect(setup.protocol.offers, hasLength(2));
    expect(setup.protocol.offers.last.disposed, isFalse);
    expect(_notice('discarded'), findsOneWidget);
    expect(setup.device.isScreenKeptOn, isTrue);
  });

  testWidgets('a check code that cannot be worked out imports nothing', (
    tester,
  ) async {
    final setup = await _pumpReceive(tester);
    setup.protocol.checkError = StateError('isolate died');
    await _openReply(tester, setup);
    expect(find.text('walletTransferReviewTitle'.tr()), findsNothing);
    expect(find.text('walletMoveCheckCodeFailed'.tr()), findsOneWidget);
    expect(setup.protocol.offers, hasLength(2));
  });

  testWidgets('leaving the app during the review drops the wallet', (
    tester,
  ) async {
    final setup = await _pumpReceive(tester);
    await _openReply(tester, setup);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // No frames are drawn while paused; coming back shows what is left.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('walletTransferReviewTitle'.tr()), findsNothing);
    expect(_notice('cleared'), findsOneWidget);
    expect(setup.protocol.offers, hasLength(2));
    expect(setup.auth.events, isEmpty);
  });

  testWidgets('the wallet is dropped once its code would have run out', (
    tester,
  ) async {
    final setup = await _pumpReceive(tester);
    await _openReply(tester, setup);
    await tester.pump(const Duration(minutes: 10));
    await tester.pumpAndSettle();
    expect(find.text('walletTransferReviewTitle'.tr()), findsNothing);
    expect(_notice('cleared'), findsOneWidget);
  });

  testWidgets('a running import keeps the wallet when the app is left', (
    tester,
  ) async {
    final setup = await _pumpReceive(tester);
    await _openReply(tester, setup);
    await _tap(tester, _import);
    expect(setup.auth.events, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('walletTransferReviewTitle'.tr()), findsOneWidget);
    expect(_cancel, findsNothing);
    expect(_differ, findsNothing);
  });

  testWidgets('keyboard Done checks a new name and never imports', (
    tester,
  ) async {
    final setup = await _pumpReceive(tester);
    setup.wallets.taken.addAll(['Savings', 'Savings 2']);
    await _openReply(tester, setup);
    expect(_nameField, findsOneWidget);
    expect(
      find.text(LocaleKeys.walletImportNameTaken.tr(args: ['Savings'])),
      findsOneWidget,
    );
    // No keyboard pops up over the codes being compared.
    final editable = find.descendant(
      of: _nameField,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).autofocus, isFalse);

    await tester.enterText(_nameField, 'Savings 2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      find.text(LocaleKeys.walletImportNameTaken.tr(args: ['Savings 2'])),
      findsOneWidget,
    );
    await tester.enterText(_nameField, 'Savings 3');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(setup.auth.events, isEmpty);

    await _tap(tester, _import);
    final event = setup.auth.events.single as AuthManagedImportRequested;
    expect(event.walletName, 'Savings 3');
    expect(event.secret.walletName, 'Savings');
  });

  testWidgets('the engine refusing the name brings the field back', (
    tester,
  ) async {
    final setup = await _pumpReceive(tester);
    await _openReply(tester, setup);
    await _tap(tester, _import);
    setup.auth.push(AuthBlocState.loading());
    await tester.pump();
    setup.auth.push(
      AuthBlocState.error(
        AuthException('taken', type: AuthExceptionType.walletAlreadyExists),
      ),
    );
    await tester.pumpAndSettle();
    expect(_nameField, findsOneWidget);
    expect(
      find.text(LocaleKeys.walletImportNameTaken.tr(args: ['Savings'])),
      findsOneWidget,
    );
    // Back to a review the user may leave.
    expect(_cancel, findsOneWidget);
  });

  testWidgets('another import failure is reported with a retry', (
    tester,
  ) async {
    final setup = await _pumpReceive(tester);
    await _openReply(tester, setup);
    await _tap(tester, _import);
    setup.auth.push(AuthBlocState.loading());
    await tester.pump();
    setup.auth.push(
      AuthBlocState.error(
        AuthException('no', type: AuthExceptionType.generalAuthError),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('authImportFailed'.tr()), findsOneWidget);
    await _tap(tester, _import);
    expect(setup.auth.events, hasLength(2));
  });

  testWidgets('back waits while importing, and success still closes', (
    tester,
  ) async {
    final setup = _newSetup(tester);
    await LegalFormHarness().pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                body: SingleChildScrollView(
                  child: _receiveWith(setup, () => tester.binding.clock.now()),
                ),
              ),
            ),
          ),
          child: const Text('open'),
        ),
      ),
      size: const Size(420, 1800),
      disableAnimations: true,
    );
    await _tap(tester, find.text('open'));
    await _openReply(tester, setup);
    await _tap(tester, _import);
    expect(_cancel, findsNothing);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(WalletMoveReceive), findsOneWidget);

    // The wallets manager closes its sheet the same way once it opens.
    setup.auth.push(AuthBlocState.loggedIn(transferUser()));
    await tester.pump();
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(WalletMoveReceive), findsNothing);
  });

  testWidgets('an unconfirmed phrase is flagged on the review', (tester) async {
    final setup = await _pumpReceive(tester);
    setup.protocol.openReply = (_) => transferSecret(phraseConfirmed: false);
    await _openReply(tester, setup);
    expect(
      find.byKey(const Key('transfer-review-phrase-unconfirmed')),
      findsOneWidget,
    );
  });
}
