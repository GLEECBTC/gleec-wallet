import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_state.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/bloc/platform/platform_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/legal_documents/legal_acceptance.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/remember_wallet_service.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_login.dart';

import '../../../support/legal_documents_fixture.dart';
import '../../../support/legal_onboarding_harness.dart';
import '../../../support/wallet_access_ui_fixture.dart';

class _Auth extends Cubit<AuthBlocState> implements AuthBloc {
  _Auth() : super(AuthBlocState.initial());
  final events = <AuthBlocEvent>[];
  void show(AuthBlocState state) => emit(state);
  @override
  void add(AuthBlocEvent event) => events.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Analytics extends Cubit<AnalyticsState> implements AnalyticsBloc {
  _Analytics() : super(AnalyticsState.initial());
  @override
  void add(AnalyticsEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Coins extends Cubit<CoinsState> implements CoinsBloc {
  _Coins() : super(CoinsState.initial());
  @override
  void add(CoinsEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends Cubit<SettingsState> implements SettingsBloc {
  _Settings() : super(SettingsState.fromStored(StoredSettings.initial()));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Wallets extends Fake implements WalletsRepository {
  _Wallets(this.stored);
  final List<Wallet> stored;
  @override
  List<Wallet>? get wallets => stored;
  @override
  Stream<List<Wallet>> watchWallets() => Stream.value(stored);
  @override
  Future<List<Wallet>> refreshWallets() async => stored;
}

class _Legal extends Fake implements LegalDocumentsRepository {
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<void> refreshConsentDocuments({bool force = false}) async {}
  @override
  bool canSubmit(LegalConsentSnapshot? snapshot) =>
      snapshot?.isAvailable ?? false;
  @override
  Future<LegalConsentSnapshot> loadConsentSnapshot() async =>
      legalFixtureSnapshot(documents: walletConsentDocuments);
  @override
  Future<bool> hasAcceptedCurrentTerms({
    LegalConsentSnapshot? snapshot,
  }) async => true;
  @override
  Future<LegalAcceptance?> readAcceptance() async => null;
  @override
  Future<void> recordAcceptance({
    required String surface,
    LegalConsentSnapshot? snapshot,
  }) async {}
}

class _SdkAuth extends Fake implements KomodoDefiLocalAuth {
  @override
  Future<List<KdfUser>> getUsers() async => [];
}

class _Sdk extends Fake implements KomodoDefiSdk {
  @override
  KomodoDefiLocalAuth get auth => _SdkAuth();
}

/// A wallet stored without a wallet lock, remembered from the last session.
class _Access extends AccessibilityAccess {
  _Access() {
    this.protected = false;
  }
  final lookup = Completer<Wallet?>();
  @override
  Future<bool> get automaticEntrySuppressed async => false;
  @override
  Future<Wallet?> lastWallet() => lookup.future;
}

final _wallet = accessibilityUser().wallet;

class _App {
  final auth = _Auth();
  final access = _Access();
  final legal = _Legal();
  final successes = <Wallet>[];
  late BuildContext host;

  Future<void> pump(WidgetTester tester, {Widget body = const Text('page')}) {
    addTearDown(access.unlockCoordinator.dispose);
    addTearDown(auth.close);
    return tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const LegalEnglishLoader(),
        child: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<WalletAccessService>.value(value: access),
            RepositoryProvider<WalletsRepository>.value(
              value: _Wallets([_wallet]),
            ),
            RepositoryProvider<LegalDocumentsRepository>.value(value: legal),
            RepositoryProvider<KomodoDefiSdk>.value(value: _Sdk()),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<AnalyticsBloc>(create: (_) => _Analytics()),
              BlocProvider<CoinsBloc>(create: (_) => _Coins()),
              BlocProvider<SettingsBloc>(create: (_) => _Settings()),
              BlocProvider<PlatformBloc>(create: (_) => PlatformBloc()),
            ],
            child: Builder(
              builder: (context) => MaterialApp(
                theme: theme.global.dark,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                home: Scaffold(
                  body: Builder(
                    builder: (context) {
                      host = context;
                      return body;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The setup dialog Connect wallet opens.
  void openSetup() => unawaited(
    AppDialog.showWithCallback<void>(
      context: host,
      width: 320,
      barrierDismissible: false,
      childBuilder: (close) => WalletsManagerWrapper(
        eventType: WalletsManagerEventType.header,
        onCancel: close,
        onSuccess: (wallet) {
          successes.add(wallet);
          close();
        },
      ),
    ),
  );
}

void main() {
  group('A wallet opened elsewhere', () {
    setUp(() {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      RememberWalletService.resetOnLogout();
    });
    tearDown(RememberWalletService.resetOnLogout);

    testWidgets('the remembered-wallet prompt does not cover a setup dialog', (
      tester,
    ) async {
      final app = _App();
      await app.pump(tester);
      await tester.pumpAndSettle();
      var settled = false;
      unawaited(
        RememberWalletService.maybeShowRememberedWallet(
          tester.element(find.text('page')),
        ).whenComplete(() => settled = true),
      );
      await tester.pump();
      app.openSetup();
      await tester.pumpAndSettle();
      app.access.lookup.complete(_wallet);
      await tester.pumpAndSettle();
      // A prompt that was shown would still be awaiting its own dismissal.
      expect(settled, isTrue);
      expect(find.byType(SimpleDialog), findsOneWidget);
      expect(find.byType(WalletLogIn), findsNothing);
      expect(RememberWalletService.hasShownRememberMeDialogThisSession, false);
    });

    testWidgets('closes a setup dialog that shows the wallet list', (
      tester,
    ) async {
      final app = _App();
      await app.pump(tester);
      await tester.pumpAndSettle();
      app.openSetup();
      await tester.pumpAndSettle();
      expect(find.text(_wallet.displayName), findsOneWidget);
      app.auth.show(AuthBlocState.loggedIn(accessibilityUser()));
      await tester.pumpAndSettle();
      expect(find.byType(SimpleDialog), findsNothing);
      expect(app.successes.map((wallet) => wallet.name), [_wallet.name]);
      expect(app.auth.events, isEmpty);
    });

    testWidgets('choosing the open wallet finishes instead of asking again', (
      tester,
    ) async {
      final app = _App();
      await app.pump(tester);
      app.auth.show(AuthBlocState.loggedIn(accessibilityUser()));
      await tester.pumpAndSettle();
      app.openSetup();
      await tester.pumpAndSettle();
      await tester.tap(find.text(_wallet.displayName));
      await tester.pumpAndSettle();
      expect(find.byType(WalletLogIn), findsNothing);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(app.successes.map((wallet) => wallet.name), [_wallet.name]);
      expect(app.auth.events, isEmpty);
    });

    testWidgets(
      'a cancelled automatic unlock leaves the unlock without error',
      (tester) async {
        final app = _App();
        await app.pump(
          tester,
          body: BlocProvider(
            create: (_) =>
                LegalAgreementBloc(app.legal)
                  ..add(const LegalAgreementOpened()),
            child: WalletLogIn(
              wallet: _wallet,
              initialQuickLogin: true,
              onLogin: (_, _, _) {},
              onCancel: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final requests = app.auth.events
            .whereType<AuthManagedSignInRequested>();
        expect(requests.single.automatic, isTrue);
        // What AuthBloc reports when the browser could not prompt.
        app.auth.show(AuthBlocState.loading());
        await tester.pump();
        app.auth.show(AuthBlocState.initial());
        await tester.pumpAndSettle();
        expect(find.textContaining('Unlock canceled'), findsNothing);
        expect(find.textContaining('Unable to unlock'), findsNothing);
        await tester.tap(find.byKey(const Key('managed-wallet-unlock')));
        await tester.pumpAndSettle();
        expect(requests.map((request) => request.automatic), [true, false]);
      },
    );
  });
}
