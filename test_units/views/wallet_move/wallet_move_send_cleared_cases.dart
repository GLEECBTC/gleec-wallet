part of 'wallet_move_send_test.dart';

/// When the reply goes, what stays (its check code), and how it comes back.
void clearedCases() {
  final cleared = find.byKey(const Key('wallet-move-send-cleared'));
  // Translated in the test: at registration the strings are not loaded.
  String clearedWithCode() => 'walletMoveSendClearedWithCode'.tr(
    args: [TransferCheckCode.grouped('12345678')],
  );

  testWidgets('after 2 minutes the reply goes and its digits stay', (
    tester,
  ) async {
    final send = await _pumpSend(tester);
    await _showReply(tester, send);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    expect(_replyCode, findsNothing);
    expect(tester.widget<WalletAccessNotice>(cleared).text, clearedWithCode());
    expect(find.text('1234 5678'), findsOneWidget);
    expect(send.sensitivity.isSensitive, isFalse);
    expect(send.device.screenOn.last, isFalse);
  });

  testWidgets('showing it again confirms the owner and seals afresh', (
    tester,
  ) async {
    final send = await _pumpSend(tester);
    await _showReply(tester, send);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump();
    await _tap(tester, find.byKey(const Key('wallet-move-send-show-again')));
    expect(send.reads, [1, 1]);
    expect(
      send.protocol.sealed.where((seal) => seal.$2.walletName != 'probe'),
      hasLength(2),
    );
    expect(_replyCode, findsOneWidget);
    expect(send.device.isScreenKeptOn, isTrue);
  });

  testWidgets('leaving the app clears the reply', (tester) async {
    final send = await _pumpSend(tester);
    await _showReply(tester, send);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // No frames are drawn while paused; coming back shows what is left.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(_replyCode, findsNothing);
    expect(cleared, findsOneWidget);
    expect(send.sensitivity.isSensitive, isFalse);
  });

  testWidgets(
    'losing focus covers the reply, not its digits, until the app is back',
    (tester) async {
      final send = await _pumpSend(tester);
      await _showReply(tester, send);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(_replyCode, findsNothing);
      expect(find.text('walletMoveSendReplyHidden'.tr()), findsOneWidget);
      expect(find.text('1234 5678'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(_replyCode, findsOneWidget);
      expect(send.reads, [1]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('locking the wallet clears the reply', (tester) async {
    final access = _Access();
    addTearDown(access.unlockCoordinator.dispose);
    final send = await _pumpSend(tester, access: access);
    await _showReply(tester, send);
    access.unlockCoordinator.lock();
    await tester.pump();
    expect(_replyCode, findsNothing);
    expect(cleared, findsOneWidget);
  });

  testWidgets('closing the screen drops the reply, its timer and the '
      'screen hold', (tester) async {
    final send = await _pumpSend(tester);
    await _showReply(tester, send);
    expect(send.sensitivity.isSensitive, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    // A countdown left running would fail the test as a pending timer.
    expect(send.sensitivity.isSensitive, isFalse);
    expect(send.device.screenOn.last, isFalse);
  });

  testWidgets('a check code that cannot be worked out ends the move', (
    tester,
  ) async {
    final send = await _pumpSend(tester);
    send.protocol.checkError = StateError('isolate died');
    send.scanner.add(_offer);
    await _tap(tester, _scan);
    expect(_replyCode, findsNothing);
    expect(find.text('walletMoveCheckCodeFailed'.tr()), findsOneWidget);
    expect(send.device.screenOn.last, isFalse);
  });

  testWidgets('at twice the text size the check code stays in view', (
    tester,
  ) async {
    // A 667-dp phone, the shortest still common.
    const phone = Size(375, 667);
    final send = await _pumpSend(tester, size: phone, textScale: 2);
    // The step number grows with the text instead of clipping.
    final badge = find
        .ancestor(of: find.text('1'), matching: find.byType(Container))
        .first;
    expect(tester.getSize(badge).height, 56);
    await _showReply(tester, send);
    expect(tester.takeException(), isNull);
    final code = tester.getBottomLeft(find.byType(TransferCheckCode));
    expect(code.dy, lessThanOrEqualTo(phone.height));
  });

  testWidgets('the flow closes when the wallet changes', (tester) async {
    final auth = TransferAuth(AuthBlocState.loggedIn(transferUser()));
    addTearDown(auth.close);
    await pumpTransferScreen(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => openWalletMoveSend(context),
          child: const Text('open'),
        ),
      ),
      auth: auth,
      protocol: FakeMoveProtocol(now: DateTime.now),
    );
    await _tap(tester, find.text('open'));
    expect(find.byType(WalletMoveSend), findsOneWidget);
    auth.push(
      AuthBlocState.loggedIn(transferUser(name: 'Other', hash: 'other')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(WalletMoveSend), findsNothing);
  });
}
