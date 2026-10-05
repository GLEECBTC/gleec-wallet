// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/views/common/seed_backup_gate/seed_backup_gate.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';

import '../../helpers/runtime_auth_fixture.dart';
import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

KdfUser _user({required bool hasBackup}) => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'swap-wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'swap-wallet-pubkey-hash',
  ),
  isBip39Seed: true,
  metadata: {'type': 'hdwallet', 'has_backup': hasBackup},
);

class _Auth with RuntimeAuthFixture implements KomodoDefiLocalAuth {
  _Auth(this.bloc);

  final AuthBloc bloc;

  @override
  Future<KdfUser?> get currentUser async => bloc.state.currentUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sdk implements KomodoDefiSdk {
  _Sdk(AuthBloc bloc) : auth = _Auth(bloc);

  @override
  final KomodoDefiLocalAuth auth;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Covers the wallet's own addresses on the swap surface, under the amount
/// cards and in the review. Anyone could pay the wallet at them, so copying
/// one warns first while the seed is not backed up, as across the wallet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  const payAddress = '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91';
  const receiveAddress = '0x80A1c2d4E5f60718293a4B5c6D7e8F9012A342F0';
  const usdcContract = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
  final notice = find.byKey(const Key('seed-backup-gate-notice'));
  final continueAnyway = find.byKey(
    const Key('seed-backup-gate-continue-button'),
  );

  late RecordingSwapBloc swap;
  late FakeSwapServices services;

  setUp(() {
    resetSeedBackupAcknowledgements();
    swap = RecordingSwapBloc();
    services = FakeSwapServices();
  });

  tearDown(() async {
    resetSeedBackupAcknowledgements();
    await swap.close();
  });

  /// Shows [view] on [state], signed in as [user], or signed out without one.
  Future<void> pump(
    WidgetTester tester,
    Widget view,
    UnifiedSwapState state, {
    KdfUser? user,
  }) async {
    final auth = FakeAuthBloc(
      user == null ? null : AuthBlocState.loggedIn(user),
    );
    addTearDown(auth.close);
    swap.emit(state);
    await pumpSwapUi(
      tester,
      RepositoryProvider<KomodoDefiSdk>.value(value: _Sdk(auth), child: view),
      bloc: swap,
      services: services,
      providers: [BlocProvider<AuthBloc>.value(value: auth)],
      size: const Size(420, 2400),
    );
  }

  Future<void> showForm(WidgetTester tester, {KdfUser? user}) => pump(
    tester,
    const SwapEntryView(),
    swapPricedForm().copyWith(
      payAddress: payAddress,
      receiveAddress: receiveAddress,
    ),
    user: user,
  );

  Future<void> showReview(WidgetTester tester, {KdfUser? user}) async {
    final quote = quoteWith(
      quoteOf(),
      fromAddress: payAddress,
      toAddress: receiveAddress,
    );
    await pump(
      tester,
      const SwapReviewView(),
      swapPricedForm(ranked: [quote]).copyWith(
        view: UnifiedSwapView.review,
        review: SwapReview(quote: quote, status: SwapReviewStatus.ready),
      ),
      user: user,
    );
    await tester.tap(find.text('Route & identities'));
    await tester.pumpAndSettle();
  }

  /// The review's Copy button for [value].
  Finder copyOf(String value) => find.descendant(
    of: find.ancestor(
      of: find.text(value),
      matching: find.byType(SwapCopyLine),
    ),
    matching: find.text('Copy'),
  );

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  group('the address under each card', () {
    for (final (side, shown, address) in [
      ('you pay from', 'From 0x5520…7B91', payAddress),
      ('you receive at', 'To 0x80A1…42F0', receiveAddress),
    ]) {
      testWidgets('$side waits for the backup warning before copying', (
        tester,
      ) async {
        final copied = recordClipboard(tester);
        await showForm(tester, user: _user(hasBackup: false));

        await tapAndSettle(tester, find.text(shown));
        expect(notice, findsOneWidget);
        expect(copied, isEmpty);

        await tapAndSettle(tester, continueAnyway);
        expect(copied, [address]);
        expect(find.text('Address copied'), findsOneWidget);
      });
    }

    for (final (name, user) in [
      ('signed out', null),
      ('once the seed is backed up', _user(hasBackup: true)),
    ]) {
      testWidgets('copies at once $name', (tester) async {
        final copied = recordClipboard(tester);
        await showForm(tester, user: user);

        await tapAndSettle(tester, find.text('From 0x5520…7B91'));
        await tapAndSettle(tester, find.text('To 0x80A1…42F0'));
        expect(notice, findsNothing);
        expect(copied, [payAddress, receiveAddress]);
      });
    }

    testWidgets('only a test network\'s copies at once', (tester) async {
      services.testnets = {eth};
      final copied = recordClipboard(tester);
      await showForm(tester, user: _user(hasBackup: false));

      await tapAndSettle(tester, find.text('From 0x5520…7B91'));
      expect(notice, findsNothing);
      expect(copied, [payAddress]);

      await tapAndSettle(tester, find.text('To 0x80A1…42F0'));
      expect(notice, findsOneWidget);
      expect(copied, [payAddress]);
    });
  });

  group('the review', () {
    for (final (name, address) in [
      ('Source address', payAddress),
      ('Receiving address', receiveAddress),
    ]) {
      testWidgets('waits for the backup warning before copying the $name', (
        tester,
      ) async {
        final copied = recordClipboard(tester);
        await showReview(tester, user: _user(hasBackup: false));

        await tapAndSettle(tester, copyOf(address));
        expect(notice, findsOneWidget);
        expect(copied, isEmpty);

        await tapAndSettle(tester, continueAnyway);
        expect(copied, [address]);
        expect(find.text('$name copied'), findsOneWidget);
      });
    }

    testWidgets('only a test network\'s address copies at once', (
      tester,
    ) async {
      services.testnets = {usdc};
      final copied = recordClipboard(tester);
      await showReview(tester, user: _user(hasBackup: false));

      await tapAndSettle(tester, copyOf(receiveAddress));
      expect(notice, findsNothing);
      expect(copied, [receiveAddress]);

      await tapAndSettle(tester, copyOf(payAddress));
      expect(notice, findsOneWidget);
      expect(copied, [receiveAddress]);
    });

    testWidgets('copies a token contract at once: no one pays the wallet '
        'there', (tester) async {
      services.contracts = {usdc: usdcContract};
      final copied = recordClipboard(tester);
      await showReview(tester, user: _user(hasBackup: false));

      await tapAndSettle(tester, copyOf(usdcContract));
      expect(notice, findsNothing);
      expect(copied, [usdcContract]);
    });
  });
}
