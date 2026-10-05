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
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/views/common/seed_backup_gate/seed_backup_gate.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/entry/swap_entry_view.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';

import '../../helpers/runtime_auth_fixture.dart';
import 'swap_accessibility_checks.dart';
import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// A wallet; [generated] when the app made its seed, so the warning also
/// offers to restore another wallet instead.
KdfUser _user({required bool hasBackup, bool generated = false}) => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'swap-wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'swap-wallet-pubkey-hash',
  ),
  isBip39Seed: true,
  metadata: {
    'type': 'hdwallet',
    'has_backup': hasBackup,
    if (generated) 'wallet_provenance': 'generated',
  },
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
/// one, or showing one in full, warns first while the seed is not backed up,
/// as across the wallet.
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

  /// Shows [view] on [state], signed in as [user], or signed out without one,
  /// and returns the sign-in.
  Future<FakeAuthBloc> pump(
    WidgetTester tester,
    Widget view,
    UnifiedSwapState state, {
    KdfUser? user,
    Size size = const Size(420, 2400),
    double textScale = 1,
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
      size: size,
      textScale: textScale,
    );
    return auth;
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

  /// The review of [quote].
  UnifiedSwapState reviewOf(SwapQuote quote) =>
      swapPricedForm(ranked: [quote]).copyWith(
        view: UnifiedSwapView.review,
        review: SwapReview(quote: quote, status: SwapReviewStatus.ready),
      );

  /// Shows the review of [quote], both addresses unless given one, with
  /// "Route & identities" open, and returns the sign-in.
  Future<FakeAuthBloc> showReview(
    WidgetTester tester, {
    KdfUser? user,
    SwapQuote? quote,
    Size size = const Size(420, 2400),
    double textScale = 1,
  }) async {
    final auth = await pump(
      tester,
      const SwapReviewView(),
      reviewOf(
        quote ??
            quoteWith(
              quoteOf(),
              fromAddress: payAddress,
              toAddress: receiveAddress,
            ),
      ),
      user: user,
      size: size,
      textScale: textScale,
    );
    final section = find.text('Route & identities');
    await tester.ensureVisible(section);
    await tester.pumpAndSettle();
    await tester.tap(section);
    await tester.pumpAndSettle();
    return auth;
  }

  /// The [action] button on the review's line showing [text].
  Finder actionOn(String text, String action) => find.descendant(
    of: find.ancestor(of: find.text(text), matching: find.byType(SwapCopyLine)),
    matching: find.text(action),
  );

  Finder copyOf(String value) => actionOn(value, 'Copy');

  Finder showOf(String value) => actionOn(value, 'Show');

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
    const payShort = '0x5520…7B91';
    const receiveShort = '0x80A1…42F0';

    for (final (name, address, short) in [
      ('Source address', payAddress, payShort),
      ('Receiving address', receiveAddress, receiveShort),
    ]) {
      testWidgets('shortens the $name until the backup warning is passed', (
        tester,
      ) async {
        final copied = recordClipboard(tester);
        await showReview(tester, user: _user(hasBackup: false));

        expect(find.text(short), findsOneWidget);
        expect(find.text(address), findsNothing);
        expect(copyOf(short), findsNothing);

        await tapAndSettle(tester, showOf(short));
        expect(notice, findsOneWidget);
        expect(find.text(address), findsNothing);

        await tapAndSettle(tester, continueAnyway);
        expect(find.text(address), findsOneWidget);
        expect(find.text(short), findsNothing);

        await tapAndSettle(tester, copyOf(address));
        expect(notice, findsNothing);
        expect(copied, [address]);
        expect(find.text('$name copied'), findsOneWidget);
      });
    }

    testWidgets('after one warning, the other address shows at once', (
      tester,
    ) async {
      await showReview(tester, user: _user(hasBackup: false));
      await tapAndSettle(tester, showOf(payShort));
      await tapAndSettle(tester, continueAnyway);

      await tapAndSettle(tester, showOf(receiveShort));
      expect(notice, findsNothing);
      expect(find.text(receiveAddress), findsOneWidget);
    });

    testWidgets('keeps the address shortened when the warning is declined', (
      tester,
    ) async {
      final auth = await showReview(
        tester,
        user: _user(hasBackup: false, generated: true),
      );

      await tapAndSettle(tester, showOf(payShort));
      await tapAndSettle(
        tester,
        find.byKey(const Key('seed-backup-gate-import-instead-button')),
      );
      expect(auth.events, [isA<AuthSignOutRequested>()]);
      expect(find.text(payShort), findsOneWidget);
      expect(find.text(payAddress), findsNothing);
    });

    testWidgets('hides an address that arrives where one was shown', (
      tester,
    ) async {
      await showReview(
        tester,
        user: _user(hasBackup: false),
        quote: quoteWith(quoteOf(), toAddress: receiveAddress),
      );
      await tapAndSettle(tester, showOf(receiveShort));
      await tapAndSettle(tester, continueAnyway);
      expect(find.text(receiveAddress), findsOneWidget);

      // The source address arrives while the review is open, in the line
      // the receiving address had.
      await emitSwapState(
        tester,
        swap,
        reviewOf(
          quoteWith(
            quoteOf(),
            fromAddress: payAddress,
            toAddress: receiveAddress,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(payShort), findsOneWidget);
      expect(find.text(payAddress), findsNothing);
    });

    for (final (name, user) in [
      ('signed out', null),
      ('once the seed is backed up', _user(hasBackup: true)),
    ]) {
      testWidgets('shows both in full at once $name', (tester) async {
        await showReview(tester, user: user);

        expect(find.text(payAddress), findsOneWidget);
        expect(find.text(receiveAddress), findsOneWidget);
        expect(find.text('Show'), findsNothing);
      });
    }

    testWidgets('shows only a test network\'s address in full at once', (
      tester,
    ) async {
      services.testnets = {usdc};
      await showReview(tester, user: _user(hasBackup: false));

      expect(find.text(receiveAddress), findsOneWidget);
      expect(find.text(payShort), findsOneWidget);
      expect(find.text(payAddress), findsNothing);
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

    for (final (name, size, textScale) in [
      ('375', const Size(375, 812), 1.0),
      ('375 at 200%', const Size(375, 812), 2.0),
      ('1024', const Size(1024, 768), 1.0),
      ('1024 at 200%', const Size(1024, 768), 2.0),
    ]) {
      testWidgets('the shortened addresses meet the swap accessibility '
          'checks at $name', (tester) async {
        await showReview(
          tester,
          user: _user(hasBackup: false),
          size: size,
          textScale: textScale,
        );
        await tester.ensureVisible(find.text(receiveShort));
        await tester.pumpAndSettle();

        expect(showOf(payShort), findsOneWidget);
        await expectSwapAccessible(tester, largeText: textScale > 1);
      });
    }
  });
}
