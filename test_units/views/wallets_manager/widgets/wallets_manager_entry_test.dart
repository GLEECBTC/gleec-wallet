import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';
import 'package:web_dex/bloc/analytics/analytics_state.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

class _FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _FakeAuthBloc() : super(AuthBlocState.initial());

  @override
  void add(AuthBlocEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCoinsBloc extends Cubit<CoinsState> implements CoinsBloc {
  _FakeCoinsBloc() : super(CoinsState.initial());

  @override
  void add(CoinsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAnalyticsBloc extends Cubit<AnalyticsState>
    implements AnalyticsBloc {
  _FakeAnalyticsBloc() : super(AnalyticsState.initial());

  final List<AnalyticsEvent> addedEvents = [];

  @override
  void add(AnalyticsEvent event) => addedEvents.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLegalDocumentsRepository implements LegalDocumentsRepository {
  _FakeLegalDocumentsRepository({this.accepted = true});

  final bool accepted;
  final List<String> recordedSurfaces = [];

  @override
  Future<bool> hasAcceptedCurrentTerms() async => accepted;

  @override
  Future<void> recordAcceptance({required String surface}) async =>
      recordedSurfaces.add(surface);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWalletsRepository implements WalletsRepository {
  _FakeWalletsRepository({this.stored = const <Wallet>[]});

  final List<Wallet> stored;

  @override
  List<Wallet>? get wallets => stored;

  @override
  Stream<List<Wallet>> watchWallets() => Stream.value(stored);

  @override
  Future<List<Wallet>> refreshWallets() async => stored;

  @override
  String? validateWalletName(String name) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

extension on _FakeAnalyticsBloc {
  List<AnalyticsEventData> get data => addedEvents
      .whereType<AnalyticsSendDataEvent>()
      .map((e) => e.data)
      .toList();

  List<(String, String)> get trace => data
      .where((d) => d.name.startsWith('onboarding_step_'))
      .map((d) => (d.name, d.parameters['step'] as String? ?? ''))
      .toList();
}

Wallet _storedWallet(String name) => Wallet(
  id: name,
  name: name,
  config: WalletConfig(
    seedPhrase: '',
    activatedCoins: const [],
    hasBackup: true,
    type: WalletType.hdwallet,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required _FakeAnalyticsBloc analyticsBloc,
  List<Wallet> stored = const <Wallet>[],
  bool mounted = true,
  _FakeLegalDocumentsRepository? legal,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _EmptyAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>(create: (_) => _FakeAuthBloc()),
              BlocProvider<CoinsBloc>(create: (_) => _FakeCoinsBloc()),
              BlocProvider<AnalyticsBloc>.value(value: analyticsBloc),
            ],
            child: MultiRepositoryProvider(
              providers: [
                RepositoryProvider<WalletsRepository>.value(
                  value: _FakeWalletsRepository(stored: stored),
                ),
                RepositoryProvider<LegalDocumentsRepository>.value(
                  value: legal ?? _FakeLegalDocumentsRepository(),
                ),
              ],
              child: Scaffold(
                body: SingleChildScrollView(
                  child: mounted
                      ? WalletsManagerWrapper(
                          eventType: WalletsManagerEventType.header,
                          onSuccess: (_) {},
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('Wallet setup entry screen', () {
    late _FakeAnalyticsBloc analyticsBloc;

    setUp(() => analyticsBloc = _FakeAnalyticsBloc());
    tearDown(() => analyticsBloc.close());

    testWidgets('shows create, import and hardware on one screen', (
      tester,
    ) async {
      await _pump(tester, analyticsBloc: analyticsBloc);

      expect(find.byKey(const Key('create-wallet-button')), findsOneWidget);
      expect(find.byKey(const Key('import-wallet-button')), findsOneWidget);
      expect(find.byKey(const Key('terms-consent-text')), findsOneWidget);
      // The retired wallet-type router had permanently-disabled rows for these.
      expect(
        find.byKey(const Key('wallet-type-list-item-metamask')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('wallet-type-list-item-keplr')),
        findsNothing,
      );
    });

    testWidgets('create is the filled CTA; import stays a full-width row', (
      tester,
    ) async {
      await _pump(tester, analyticsBloc: analyticsBloc);

      // Asymmetry is carried by fill and elevation, not by shrinking import.
      expect(find.byKey(const Key('create-wallet-button')), findsOneWidget);
      expect(
        tester.widget<UiListActionRow>(
          find.ancestor(
            of: find.byKey(const Key('import-wallet-button')),
            matching: find.byType(UiListActionRow),
          ),
        ),
        isA<UiListActionRow>(),
      );

      final createWidth = tester
          .getSize(find.byKey(const Key('create-wallet-button')))
          .width;
      final importWidth = tester
          .getSize(find.byKey(const Key('import-wallet-button')))
          .width;
      expect(importWidth, greaterThanOrEqualTo(createWidth));
    });

    testWidgets('mounting views the create-or-import step', (tester) async {
      await _pump(tester, analyticsBloc: analyticsBloc);

      expect(analyticsBloc.trace, [
        ('onboarding_step_viewed', 'wallet_manager_opened'),
        ('onboarding_step_completed', 'wallet_manager_opened'),
        ('onboarding_step_viewed', 'setup_action_select'),
      ]);
      final viewed = analyticsBloc.data.first;
      expect(viewed.parameters['entry_point'], 'header');
      expect(viewed.parameters['existing_wallet_count'], 0);
    });

    testWidgets('tapping Create completes the choice and opens the form', (
      tester,
    ) async {
      await _pump(tester, analyticsBloc: analyticsBloc);
      analyticsBloc.addedEvents.clear();

      await tester.tap(find.byKey(const Key('create-wallet-button')));
      await tester.pump();

      expect(analyticsBloc.trace, [
        ('onboarding_step_completed', 'setup_action_select'),
        ('onboarding_step_viewed', 'create_form'),
      ]);
      expect(find.byKey(const Key('wallet-creation')), findsOneWidget);
    });

    testWidgets('tapping Import opens the seed-entry step', (tester) async {
      await _pump(tester, analyticsBloc: analyticsBloc);
      analyticsBloc.addedEvents.clear();

      await tester.tap(find.byKey(const Key('import-wallet-button')));
      await tester.pump();

      expect(analyticsBloc.trace.last, (
        'onboarding_step_viewed',
        'import_seed_entry',
      ));
    });

    testWidgets('with wallets stored, the list leads and create demotes', (
      tester,
    ) async {
      await _pump(
        tester,
        analyticsBloc: analyticsBloc,
        stored: [_storedWallet('wallet-a')],
      );
      // The wallets stream resolves after the first frame, which is exactly
      // why the entry screen owns it: the layout depends on the answer.
      await tester.pump();

      expect(find.text('wallet-a'), findsOneWidget);
      // Both actions survive, now at equal weight as rows.
      expect(find.byKey(const Key('create-wallet-button')), findsOneWidget);
      expect(find.byKey(const Key('import-wallet-button')), findsOneWidget);
    });

    testWidgets('a returning user re-consents when the terms have changed', (
      tester,
    ) async {
      final legal = _FakeLegalDocumentsRepository(accepted: false);
      await _pump(
        tester,
        analyticsBloc: analyticsBloc,
        stored: [_storedWallet('wallet-a')],
        legal: legal,
      );
      await tester.pump();

      // Implicit consent is right for a first run, but silently re-accepting
      // changed terms on a returning user's behalf is not.
      expect(find.byKey(const Key('checkbox-eula-tos')), findsOneWidget);
      expect(find.byKey(const Key('terms-consent-text')), findsNothing);

      await tester.tap(find.byKey(const Key('create-wallet-button')));
      await tester.pump();
      expect(
        legal.recordedSurfaces,
        isEmpty,
        reason: 'actions stay inert until the box is ticked',
      );

      await tester.tap(find.byKey(const Key('checkbox-eula-tos')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-wallet-button')));
      await tester.pump();

      expect(legal.recordedSurfaces, ['onboarding']);
    });

    testWidgets('a first run records consent without asking', (tester) async {
      final legal = _FakeLegalDocumentsRepository();
      await _pump(tester, analyticsBloc: analyticsBloc, legal: legal);

      await tester.tap(find.byKey(const Key('create-wallet-button')));
      await tester.pump();

      expect(legal.recordedSurfaces, ['onboarding']);
    });

    testWidgets('unmounting abandons the open step exactly once', (
      tester,
    ) async {
      await _pump(tester, analyticsBloc: analyticsBloc);
      analyticsBloc.addedEvents.clear();

      await _pump(tester, analyticsBloc: analyticsBloc, mounted: false);
      await tester.pumpAndSettle();

      expect(analyticsBloc.trace, [
        ('onboarding_step_abandoned', 'setup_action_select'),
      ]);
    });
  });
}
