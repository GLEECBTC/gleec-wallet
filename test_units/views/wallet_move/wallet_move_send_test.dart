import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
// Reset translations after the harness loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';
import 'package:web_dex/views/wallet_move/read_wallet_transfer_secret.dart';
import 'package:web_dex/views/wallet_move/transfer_check_code.dart';
import 'package:web_dex/views/wallet_move/transfer_scanner.dart';
import 'package:web_dex/views/wallet_move/wallet_move_failure_text.dart';
import 'package:web_dex/views/wallet_move/wallet_move_send.dart';

import 'transfer_fakes.dart';

part 'wallet_move_send_cleared_cases.dart';

class _Access extends Fake implements WalletAccessService {
  _Access() {
    unlockCoordinator.attachWallet(
      'entry-1',
      requiresAuthentication: true,
      authenticated: true,
    );
  }

  @override
  final unlockCoordinator = WalletUnlockCoordinator(
    operationGate: WalletOperationGate(),
  );
}

typedef _Send = ({
  FakeMoveProtocol protocol,
  FakeScanner scanner,
  FakeDeviceControls device,
  List<int> reads,
  List<int> closes,
  ScreenshotSensitivityController sensitivity,
});

const _offer = 'GLEECMOVE1O.new-phone';
final _scan = find.byKey(const Key('wallet-move-send-scan'));
final _replyCode = find.byKey(const Key('wallet-move-reply-code'));
final _notice = find.byKey(const Key('wallet-move-send-notice'));

Future<_Send> _pumpSend(
  WidgetTester tester, {
  WalletSecretRead? read,
  _Access? access,
  Size size = const Size(420, 1400),
  double textScale = 1,
}) async {
  final protocol = FakeMoveProtocol(now: () => tester.binding.clock.now());
  final auth = TransferAuth(AuthBlocState.loggedIn(transferUser()));
  addTearDown(auth.close);
  final scanner = FakeScanner();
  final device = FakeDeviceControls();
  final reads = <int>[];
  final closes = <int>[];
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  final sensitivity = await pumpTransferScreen(
    tester,
    WalletMoveSend(
      onClose: () => closes.add(1),
      readSecret: (_) async {
        reads.add(1);
        return read ?? WalletSecretReady(transferSecret());
      },
      scan: scanner.call,
      now: () => tester.binding.clock.now(),
    ),
    auth: auth,
    protocol: protocol,
    device: device,
    extra: [
      if (access != null)
        RepositoryProvider<WalletAccessService>.value(value: access),
    ],
    size: size,
    textScale: textScale,
  );
  return (
    protocol: protocol,
    scanner: scanner,
    device: device,
    reads: reads,
    closes: closes,
    sensitivity: sensitivity,
  );
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _showReply(WidgetTester tester, _Send send) async {
  send.scanner.add(_offer);
  await _tap(tester, _scan);
  expect(_replyCode, findsOneWidget);
}

String _countdown(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const Key('wallet-move-reply-countdown')))
    .data!;

void main() {
  group('WalletMoveSend', () {
    setUpAll(() async {
      // The analyzer does not recognize the test_units directory as test code.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    testWidgets('explains the move and warns before the camera opens', (
      tester,
    ) async {
      final send = await _pumpSend(tester);
      expect(find.text('walletMoveSendWarning'.tr()), findsOneWidget);
      expect(find.text('walletMoveSendStays'.tr()), findsOneWidget);
      expect(send.reads, isEmpty);
      expect(send.device.screenOn, isEmpty);
    });

    testWidgets('confirms only after a valid code, then seals at once', (
      tester,
    ) async {
      final send = await _pumpSend(tester);
      send.protocol.checkGate = Completer<void>();
      await _showReply(tester, send);
      expect(send.scanner.instructions, ['walletMoveScannerNewPhone'.tr()]);
      expect(send.reads, [1]);
      // Checked before the lock was asked for; sealed once, after it.
      expect(send.protocol.offersChecked, [_offer]);
      expect(send.protocol.sealed.single.$1, _offer);
      expect(send.protocol.sealed.single.$2.seed, transferTestSeed);
      expect(send.sensitivity.isSensitive, isTrue);
      expect(send.device.isScreenKeptOn, isTrue);
      // The slow digits: a placeholder first, never a blocked screen.
      expect(
        find.byKey(const Key('transfer-check-code-working')),
        findsOneWidget,
      );
      send.protocol.checkGate!.complete();
      await tester.pumpAndSettle();
      expect(send.protocol.checked, ['GLEECMOVE1R.reply-for-$_offer']);
      expect(find.text('1234 5678'), findsOneWidget);
      expect(
        _countdown(tester),
        'walletMoveSendReplyCountdown'.tr(args: ['2:00']),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        _countdown(tester),
        'walletMoveSendReplyCountdown'.tr(args: ['1:59']),
      );
      // Done is the quiet way out, not the screen's main action.
      final done = find.byKey(const Key('wallet-move-send-done'));
      expect(tester.widget(done), isA<SecuritySecondaryButton>());
      await _tap(tester, done);
      expect(send.closes, [1]);
    });

    for (final failure in WalletMoveFailure.values) {
      testWidgets('a ${failure.name} code is refused before anyone confirms', (
        tester,
      ) async {
        final send = await _pumpSend(tester);
        send.protocol.sealFailure = failure;
        send.scanner.add('scanned');
        await _tap(tester, _scan);
        expect(send.reads, isEmpty);
        expect(
          find.text(walletMoveFailureText(failure, onNewPhone: false)),
          findsOneWidget,
        );
        expect(_replyCode, findsNothing);
      });
    }

    testWidgets('a closed camera or confirmation shares nothing', (
      tester,
    ) async {
      final send = await _pumpSend(
        tester,
        read: const WalletSecretNotRead(WalletSecretUnread.canceled),
      );
      await _tap(tester, _scan);
      expect(send.reads, isEmpty);
      send.scanner.add(_offer);
      await _tap(tester, _scan);
      expect(send.reads, [1]);
      expect(_replyCode, findsNothing);
      expect(_notice, findsNothing);
    });

    for (final (reason, key) in [
      (WalletSecretUnread.interrupted, 'walletMoveSendInterrupted'),
      (WalletSecretUnread.unsupported, 'walletMoveSendUnsupported'),
      (WalletSecretUnread.failed, 'walletMoveSendReadFailed'),
    ]) {
      testWidgets('an ${reason.name} confirmation is explained', (
        tester,
      ) async {
        final send = await _pumpSend(tester, read: WalletSecretNotRead(reason));
        send.scanner.add(_offer);
        await _tap(tester, _scan);
        expect(find.text(key.tr()), findsOneWidget);
        // The code was valid, but nothing was sealed without the wallet.
        expect(send.protocol.offersChecked, [_offer]);
        expect(send.protocol.sealed, isEmpty);
      });
    }

    testWidgets('camera access that is off offers Settings and a retry', (
      tester,
    ) async {
      final send = await _pumpSend(tester);
      send.scanner.results.add(const TransferScanDenied());
      await _tap(tester, _scan);
      expect(find.text('walletMoveCameraDenied'.tr()), findsOneWidget);
      expect(
        find.descendant(
          of: _scan,
          matching: find.text(LocaleKeys.tryAgain.tr()),
        ),
        findsOneWidget,
      );
      await _tap(tester, find.byKey(const Key('transfer-open-settings')));
      expect(send.device.settingsOpened, 1);
      expect(send.reads, isEmpty);
    });

    clearedCases();
  });
}
