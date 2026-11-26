import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
// Reset translations after the shared harness loads the real English strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/device/device_controls.dart';
import 'package:web_dex/services/wallet_move/wallet_move_types.dart';
import 'package:web_dex/views/wallet_move/transfer_check_code.dart';
import 'package:web_dex/views/wallet_move/transfer_scanner.dart';
import 'package:web_dex/views/wallet_move/wallet_move_failure_text.dart';
import 'package:web_dex/views/wallet_move/wallet_move_receive.dart';

import '../../support/legal_onboarding_harness.dart';
import 'transfer_fakes.dart';

part 'wallet_move_receive_review_cases.dart';

typedef _Receive = ({
  FakeMoveProtocol protocol,
  TransferAuth auth,
  TransferWallets wallets,
  FakeScanner scanner,
  FakeDeviceControls device,
  List<int> cancels,
});

final _scan = find.byKey(const Key('wallet-move-scan-reply'));
final _import = find.byKey(const Key('transfer-review-import'));
final _differ = find.byKey(const Key('transfer-review-codes-differ'));
final _cancel = find.byKey(const Key('transfer-review-cancel'));
final _nameField = find.byKey(const Key('transfer-review-name'));
Finder _notice(String kind) => find.byKey(ValueKey('wallet-move-notice-$kind'));

bool _importEnabled(WidgetTester tester) =>
    tester.widget<UiPrimaryButton>(_import).onPressed != null;

Widget _receiveWith(_Receive setup, DateTime Function() now) =>
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<WalletMoveProtocol>.value(value: setup.protocol),
        RepositoryProvider<WalletsRepository>.value(value: setup.wallets),
        RepositoryProvider<DeviceControls>.value(value: setup.device),
      ],
      child: BlocProvider<AuthBloc>.value(
        value: setup.auth,
        child: WalletMoveReceive(
          onCancel: () => setup.cancels.add(1),
          scan: setup.scanner.call,
          now: now,
        ),
      ),
    );

_Receive _newSetup(WidgetTester tester) {
  final auth = TransferAuth();
  addTearDown(auth.close);
  return (
    protocol: FakeMoveProtocol(now: () => tester.binding.clock.now()),
    auth: auth,
    wallets: TransferWallets(),
    scanner: FakeScanner(),
    device: FakeDeviceControls(),
    cancels: <int>[],
  );
}

Future<_Receive> _pumpReceive(WidgetTester tester) async {
  final setup = _newSetup(tester);
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
  await LegalFormHarness().pump(
    tester,
    _receiveWith(setup, () => tester.binding.clock.now()),
    size: const Size(420, 1800),
    contentWidth: 360,
    // The busy indicator holds still, so pumpAndSettle can settle.
    disableAnimations: true,
  );
  return setup;
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// Scans [reply] and lets its check code arrive.
Future<void> _openReply(WidgetTester tester, _Receive setup, [String? reply]) {
  setup.scanner.add(reply ?? 'GLEECMOVE1R.reply');
  return _tap(tester, _scan);
}

void main() {
  group('WalletMoveReceive', () {
    setUpAll(() async {
      // The analyzer does not recognize the test_units directory as test code.
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
    });
    tearDown(() => Localization.load(const Locale('en')));

    testWidgets('shows a code for the old phone and keeps the screen on', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final setup = await _pumpReceive(tester);
      expect(setup.protocol.offers, hasLength(1));
      expect(find.byType(QrImageView), findsOneWidget);
      expect(
        find.bySemanticsLabel('walletMoveReceiveCodeLabel'.tr()),
        findsOneWidget,
      );
      expect(find.text('walletMoveReceiveStepOld'.tr()), findsOneWidget);
      // The code's content is never exposed to assistive technology.
      expect(find.bySemanticsLabel(RegExp('GLEECMOVE')), findsNothing);
      expect(setup.device.isScreenKeptOn, isTrue);
      semantics.dispose();
    });

    testWidgets('the camera is asked for the old phone\'s code', (
      tester,
    ) async {
      final setup = await _pumpReceive(tester);
      await _tap(tester, _scan);
      expect(setup.scanner.instructions, ['walletMoveScannerOldPhone'.tr()]);
      expect(setup.protocol.offers.single.opened, isEmpty);
      expect(_notice('refused'), findsNothing);
    });

    for (final failure in WalletMoveFailure.values) {
      testWidgets('a ${failure.name} reply says what to do next', (
        tester,
      ) async {
        final setup = await _pumpReceive(tester);
        setup.protocol.openReply = (_) => throw WalletMoveException(failure);
        await _openReply(tester, setup, 'scanned');
        expect(
          find.text(walletMoveFailureText(failure, onNewPhone: true)),
          findsOneWidget,
        );
        // Only an expired code is replaced; the others can still be used.
        final expired = failure == WalletMoveFailure.expired;
        expect(setup.protocol.offers, hasLength(expired ? 2 : 1));
        expect(setup.protocol.offers.first.disposed, expired);
      });
    }

    testWidgets('a reply the check refuses leaves the code usable', (
      tester,
    ) async {
      final setup = await _pumpReceive(tester);
      setup.protocol.checkFailure = WalletMoveFailure.damaged;
      await _openReply(tester, setup, 'GLEECMOVE1R.torn');
      final offer = setup.protocol.offers.single;
      expect(offer.opened, isEmpty);
      expect(offer.disposed, isFalse);
      expect(
        find.text(
          walletMoveFailureText(WalletMoveFailure.damaged, onNewPhone: true),
        ),
        findsOneWidget,
      );
    });

    testWidgets('camera access that is off offers Settings and a retry', (
      tester,
    ) async {
      final setup = await _pumpReceive(tester);
      setup.scanner.results.add(const TransferScanDenied());
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
      expect(setup.device.settingsOpened, 1);

      await _openReply(tester, setup);
      expect(find.text('walletTransferReviewTitle'.tr()), findsOneWidget);
    });

    testWidgets('a camera that cannot scan says so', (tester) async {
      final setup = await _pumpReceive(tester);
      setup.scanner.results.add(const TransferScanUnsupported());
      await _tap(tester, _scan);
      expect(find.text('walletMoveCameraUnavailable'.tr()), findsOneWidget);
      expect(find.byKey(const Key('transfer-open-settings')), findsNothing);
    });

    testWidgets('a code that runs out is replaced by a fresh one', (
      tester,
    ) async {
      final setup = await _pumpReceive(tester);
      final first = setup.protocol.offers.single;
      await tester.pump(const Duration(minutes: 9, seconds: 59));
      expect(setup.protocol.offers, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(setup.protocol.offers, hasLength(2));
      expect(first.disposed, isTrue);
      expect(_notice('renewed'), findsOneWidget);
    });

    testWidgets('leaving forgets the offer and lets the screen sleep', (
      tester,
    ) async {
      final setup = await _pumpReceive(tester);
      await _tap(tester, find.byKey(const Key('wallet-move-receive-cancel')));
      expect(setup.cancels, [1]);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(setup.protocol.offers.single.disposed, isTrue);
      expect(setup.device.screenOn.last, isFalse);
    });

    reviewCases();
  });
}
