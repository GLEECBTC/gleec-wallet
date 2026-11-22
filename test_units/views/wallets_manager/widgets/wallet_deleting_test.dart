import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
// Restore shared localization state after loading the actual warning strings.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_deleting.dart';

import '../../../support/legal_onboarding_harness.dart';

class _Journal extends Fake implements PendingGaslessTransferRepository {
  bool unreadable = false;
  List<PendingGaslessTransfer> rows = [];

  @override
  Future<List<PendingGaslessTransfer>> list(WalletId walletId) async {
    if (unreadable) throw StateError('locked');
    return rows;
  }
}

class _Repository extends Fake implements WalletsRepository {
  late Future<WalletDeletionReview?> Function(Wallet) prepare;
  Future<WalletDeletionResult> Function()? confirm;
  final acknowledgements = <WalletDeletionReview?>[];
  final deletedWallets = <Wallet>[];

  @override
  Future<WalletDeletionReview?> prepareWalletDeletion(Wallet wallet) =>
      prepare(wallet);

  @override
  Future<WalletDeletionResult> deleteWallet(
    Wallet wallet, {
    required String password,
    WalletDeletionReview? acknowledgedReview,
  }) async {
    deletedWallets.add(wallet);
    acknowledgements.add(acknowledgedReview);
    return confirm?.call() ??
        const WalletDeletionResult(WalletDeletionStatus.deleted);
  }
}

PendingGaslessTransfer _transfer({String destination = 'TDestination'}) {
  final at = DateTime.utc(2026, 9, 15, 12);
  return PendingGaslessTransfer(
    journalId: 'private-request-identity',
    traceId: 'private-provider-trace',
    assetId: 'USDT-TRC20',
    network: '728126428',
    sourceAddress: 'TPrivateSource',
    custodyAddress: 'TPrivateCustody',
    destinationAddress: destination,
    requestedAmount: Decimal.fromInt(7),
    signedMaxFee: Decimal.one,
    authorizationDeadline: BigInt.from(1790000000),
    balanceChanges: BalanceChanges(
      netChange: -Decimal.fromInt(8),
      receivedByMe: Decimal.zero,
      spentByMe: Decimal.fromInt(8),
      totalAmount: Decimal.fromInt(7),
    ),
    fee: FeeInfo.tronGasless(
      coin: 'USDT-TRC20',
      feeMethod: 'gasless',
      providerName: 'gasfree',
      gasfreeAddress: 'TPrivateCustody',
      transferFee: Decimal.one,
      totalTokenFee: Decimal.one,
      signedMaxFee: Decimal.one,
    ),
    acceptedAt: at,
    updatedAt: at,
    state: GaslessTransferState.submittedUnknown,
  );
}

void main() {
  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));

  late Wallet first;
  late Wallet second;
  late ValueNotifier<Wallet> selected;
  late _Journal journal;
  late _Repository repository;
  late WalletDeletionManager reviews;
  var closes = 0;
  VoidCallback? onBackUpFirst;

  const confirm = Key('wallet-removal-confirm');
  const acknowledge = Key('wallet-removal-acknowledge');
  const safeAction = Key('wallet-removal-safe-action');
  final transferNote = find.byKey(
    const Key('wallet-deletion-recovery-warning'),
  );

  // The shared flow tests review a wallet whose phrase is confirmed; the
  // unconfirmed variant has its own tests below.
  Wallet backedUp(String name) =>
      Wallet.fromName(name: name)
        ..config.recoveryEvidence = RecoveryEvidence.phraseConfirmed;

  setUp(() {
    first = backedUp('First wallet');
    second = backedUp('Second wallet');
    onBackUpFirst = null;
    selected = ValueNotifier(first);
    journal = _Journal();
    repository = _Repository();
    reviews = WalletDeletionManager(
      readWallets: () async => [
        for (final wallet in [first, second])
          KdfUser(
            walletId: WalletId(
              name: wallet.name,
              pubkeyHash: wallet.id,
              authOptions: const AuthOptions(
                derivationMethod: DerivationMethod.hdWallet,
              ),
            ),
            isBip39Seed: true,
            metadata: {walletEntryIdMetadataKey: wallet.id},
          ),
      ],
      deleteWallet: ({
        required walletName,
        required password,
        required validateTarget,
      }) async {},
      pendingTransfers: journal,
    );
    repository.prepare = (wallet) => reviews.prepare(wallet.name);
    closes = 0;
  });

  tearDown(() => selected.dispose());

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const LegalEnglishLoader(),
        child: RepositoryProvider<WalletsRepository>.value(
          value: repository,
          child: Builder(
            builder: (context) => MaterialApp(
              theme: theme.global.dark,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SizedBox(
                    width: 500,
                    child: ValueListenableBuilder<Wallet>(
                      valueListenable: selected,
                      builder: (_, wallet, _) => WalletDeleting(
                        key: const Key('deletion-panel'),
                        wallet: wallet,
                        close: () => closes++,
                        onBackUpFirst: onBackUpFirst,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('delete-wallet-password')),
      'Sample-password-123!',
    );
    await tester.tap(find.byKey(confirm));
    await tester.pump();
  }

  bool enabled(WidgetTester tester) =>
      switch (tester.widget(find.byKey(confirm))) {
        UiPrimaryButton(:final onPressed) => onPressed != null,
        ButtonStyleButton(:final enabled) => enabled,
        final other => throw StateError('Unexpected confirm control $other'),
      };

  testWidgets(
    'inactive passkey wallet explains the required password unlock before deletion',
    (tester) async {
      repository.confirm = () async => throw const WalletAccessException(
        WalletAccessFailure.walletMustBeUnlocked,
      );
      await pump(tester);
      await submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('authUnlockWalletBeforeDeletion'.tr()), findsOneWidget);
      expect(closes, 0);
      expect(enabled(tester), isTrue);
    },
  );

  testWidgets('shows payment warning without private recovery internals', (
    tester,
  ) async {
    journal.rows = [_transfer()];
    await pump(tester);
    expect(transferNote, findsOneWidget);
    expect(find.textContaining('7 USDT-TRC20'), findsOneWidget);
    expect(find.textContaining('TDestination'), findsOneWidget);
    expect(find.textContaining('private-provider-trace'), findsNothing);
    expect(find.textContaining('private-request-identity'), findsNothing);
    expect(find.textContaining('TPrivateSource'), findsNothing);
    expect(find.text('authRemoveWalletPendingTransfers'.tr()), findsOneWidget);
    expect(enabled(tester), isTrue);
  });

  testWidgets(
    'unreadable recovery displays uncertainty and allows confirmation',
    (tester) async {
      journal.unreadable = true;
      await pump(tester);
      expect(
        find.text(LocaleKeys.walletDeletionRecoveryUnavailable.tr()),
        findsOneWidget,
      );
      expect(transferNote, findsOneWidget);
      expect(enabled(tester), isTrue);
      await submit(tester);
      expect(closes, 1);
      await tester.pump();
      expect(find.text('authWalletRemoved'.tr()), findsOneWidget);
    },
  );

  testWidgets('backed-up wallet needs no acknowledgement and opens on Cancel', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(acknowledge), findsNothing);
    expect(find.byKey(const Key('wallet-removal-not-backed-up')), findsNothing);
    expect(
      find.byKey(const Key('wallet-removal-backed-up-reminder')),
      findsOneWidget,
    );
    final cancel = find.byKey(const Key('wallet-removal-cancel'));
    expect(
      tester.widget<OutlinedButton>(cancel).focusNode!.hasPrimaryFocus,
      isTrue,
    );
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('delete-wallet-password')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.enableSuggestions, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.autofillHints, contains(AutofillHints.password));
    // With nothing pending, the transfer note stays out of the way.
    expect(transferNote, findsNothing);
    expect(enabled(tester), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closes, 1);
    expect(repository.deletedWallets, isEmpty);
  });

  group('recovery phrase not backed up', () {
    setUp(() => selected.value = first = Wallet.fromName(name: 'First wallet'));

    testWidgets('removal waits for the acknowledgement; backup leads', (
      tester,
    ) async {
      var backups = 0;
      onBackUpFirst = () => backups++;
      final semantics = tester.ensureSemantics();
      await pump(tester);
      expect(
        find.byKey(const Key('wallet-removal-not-backed-up')),
        findsOneWidget,
      );
      final backUp = tester.widget<UiPrimaryButton>(find.byKey(safeAction));
      expect(backUp.text, 'authBackUpRecoveryPhraseFirst'.tr());
      expect(backUp.focusNode!.hasPrimaryFocus, isTrue);
      expect(enabled(tester), isFalse);
      await submit(tester);
      expect(repository.deletedWallets, isEmpty);
      expect(
        tester.getSemantics(find.byKey(acknowledge)),
        containsSemantics(hasCheckedState: true, isChecked: false),
      );
      await tester.tap(find.byKey(acknowledge));
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(acknowledge)),
        containsSemantics(hasCheckedState: true, isChecked: true),
      );
      expect(enabled(tester), isTrue);
      await tester.tap(find.byKey(safeAction));
      expect(backups, 1);
      expect(closes, 0);
      await submit(tester);
      expect(repository.deletedWallets, [same(first)]);
      expect(closes, 1);
      semantics.dispose();
    });

    testWidgets('with no backup route, keeping the wallet is primary', (
      tester,
    ) async {
      await pump(tester);
      expect(
        tester.widget<UiPrimaryButton>(find.byKey(safeAction)).text,
        LocaleKeys.cancel.tr(),
      );
      expect(enabled(tester), isFalse);
      await tester.tap(find.byKey(safeAction));
      expect(closes, 1);
      expect(repository.deletedWallets, isEmpty);
    });
  });

  testWidgets('changed warning requires a second explicit confirmation', (
    tester,
  ) async {
    final original = await reviews.prepare(first.name);
    journal.rows = [_transfer(destination: 'TNewDestination')];
    final updated = await reviews.prepare(first.name);
    repository.prepare = (_) async => original;
    repository.confirm = () async => repository.acknowledgements.length == 1
        ? WalletDeletionResult(
            WalletDeletionStatus.reviewChanged,
            review: updated,
          )
        : const WalletDeletionResult(WalletDeletionStatus.deleted);
    await pump(tester);
    await submit(tester);
    expect(closes, 0);
    expect(repository.acknowledgements, [same(original)]);
    expect(
      find.text(LocaleKeys.walletDeletionReviewChanged.tr()),
      findsOneWidget,
    );
    expect(find.textContaining('TNewDestination'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    // Confirmation is explicit again, including fresh password input. The
    // previous secret is not retained while a payment warning changes.
    await tester.tap(find.byKey(confirm));
    await tester.pump();
    expect(repository.acknowledgements, [same(original)]);
    await submit(tester);
    expect(repository.acknowledgements.last, same(updated));
    expect(closes, 1);
  });

  testWidgets(
    'busy submission keeps the form available for an explicit retry',
    (tester) async {
      repository.confirm = () async => repository.acknowledgements.length == 1
          ? const WalletDeletionResult(WalletDeletionStatus.busy)
          : const WalletDeletionResult(WalletDeletionStatus.deleted);
      await pump(tester);
      await submit(tester);
      expect(
        find.text(LocaleKeys.walletDeletionSubmissionBusy.tr()),
        findsOneWidget,
      );
      expect(enabled(tester), isTrue);
      expect(closes, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.tap(find.byKey(confirm));
      await tester.pump();
      expect(repository.acknowledgements, hasLength(1));
      expect(closes, 0);
      await submit(tester);
      expect(closes, 1);
    },
  );

  testWidgets('replacement disables deletion until a new target is selected', (
    tester,
  ) async {
    repository.confirm = () async =>
        const WalletDeletionResult(WalletDeletionStatus.targetChanged);
    await pump(tester);
    await submit(tester);
    expect(enabled(tester), isFalse);
    expect(
      find.text(LocaleKeys.walletDeletionTargetChanged.tr()),
      findsOneWidget,
    );
    expect(find.text(LocaleKeys.tryAgain.tr()), findsNothing);
    selected.value = second;
    await tester.pump();
    await tester.pump();
    expect(enabled(tester), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('selection clears busy and ignores stale deletion after A B A', (
    tester,
  ) async {
    final pending = Completer<WalletDeletionResult>();
    repository.confirm = () => pending.future;
    await pump(tester);
    await submit(tester);
    // The control stays focusable while busy; progress is announced and a
    // repeated press removes nothing twice.
    expect(enabled(tester), isTrue);
    expect(find.byType(WalletAccessProgress), findsOneWidget);
    await tester.tap(find.byKey(confirm));
    await tester.pump();
    expect(repository.deletedWallets, [same(first)]);
    selected.value = second;
    await tester.pump();
    await tester.pump();
    expect(enabled(tester), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    selected.value = first;
    await tester.pump();
    await tester.pump();
    pending.complete(const WalletDeletionResult(WalletDeletionStatus.deleted));
    await tester.pump();
    expect(closes, 0);
    expect(enabled(tester), isTrue);
    expect(repository.deletedWallets, [same(first)]);
  });

  testWidgets('stale review after A B A cannot enable the new confirmation', (
    tester,
  ) async {
    final original = await reviews.prepare(first.name);
    final stale = Completer<WalletDeletionReview?>();
    final current = Completer<WalletDeletionReview?>();
    var requests = 0;
    repository.prepare = (_) {
      requests++;
      return requests == 1 ? stale.future : current.future;
    };
    await pump(tester);
    selected.value = second;
    await tester.pump();
    selected.value = first;
    await tester.pump();
    stale.complete(original);
    await tester.pump();
    expect(enabled(tester), isFalse);
    current.complete(original);
    await tester.pump();
    expect(enabled(tester), isTrue);
    expect(repository.deletedWallets, isEmpty);
  });
}
