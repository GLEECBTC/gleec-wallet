import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_state.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/platform/platform_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_bloc.dart';
import 'package:web_dex/bloc/taker_form/taker_event.dart';
import 'package:web_dex/bloc/taker_form/taker_state.dart';
import 'package:web_dex/blocs/maker_form_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/legal_documents/legal_acceptance.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/widgets/connect_wallet/connect_wallet_button.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_wrapper.dart';

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

class _TakerBloc extends Cubit<TakerState> implements TakerBloc {
  _TakerBloc() : super(TakerState.initial());

  final List<TakerEvent> events = [];

  @override
  void add(TakerEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MakerForm extends Fake implements MakerFormBloc {
  int reInits = 0;

  @override
  Future<void> reInitForm() async => reInits++;
}

class _AuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _AuthBloc() : super(AuthBlocState.initial());

  @override
  void add(AuthBlocEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CoinsBloc extends Cubit<CoinsState> implements CoinsBloc {
  _CoinsBloc() : super(CoinsState.initial());

  @override
  void add(CoinsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AnalyticsBloc extends Cubit<AnalyticsState> implements AnalyticsBloc {
  _AnalyticsBloc() : super(AnalyticsState.initial());

  @override
  void add(AnalyticsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Wallets extends Fake implements WalletsRepository {
  @override
  List<Wallet>? get wallets => const [];

  @override
  Stream<List<Wallet>> watchWallets() => Stream.value(const []);

  @override
  Future<List<Wallet>> refreshWallets() async => const [];

  @override
  String? validateWalletName(String name) => null;
}

class _LegalDocuments extends Fake implements LegalDocumentsRepository {
  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<void> refreshConsentDocuments() async {}

  @override
  Future<LegalConsentSnapshot> loadConsentSnapshot() async =>
      LegalConsentSnapshot(documents: {}, documentShas: {});

  @override
  Future<bool> hasAcceptedCurrentTerms({
    LegalConsentSnapshot? snapshot,
  }) async => true;

  @override
  Future<LegalAcceptance?> readAcceptance() async => null;
}

final _wallet = Wallet(
  id: 'wallet-a',
  name: 'Wallet A',
  config: WalletConfig(
    seedPhrase: '',
    activatedCoins: const [],
    hasBackup: true,
    type: WalletType.hdwallet,
  ),
);

void main() {
  group('Connect wallet', () {
    late _TakerBloc taker;
    late _MakerForm maker;

    setUp(() {
      taker = _TakerBloc();
      maker = _MakerForm();
    });
    tearDown(() => taker.close());

    // The dialog opens on the root navigator, so everything it reads sits
    // above the app.
    Future<WalletsManagerWrapper> open(WidgetTester tester) async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          saveLocale: false,
          path: 'assets/translations',
          assetLoader: const _EmptyAssetLoader(),
          child: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<WalletsRepository>.value(value: _Wallets()),
              RepositoryProvider<LegalDocumentsRepository>.value(
                value: _LegalDocuments(),
              ),
              RepositoryProvider<MakerFormBloc>.value(value: maker),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<TakerBloc>.value(value: taker),
                BlocProvider<AuthBloc>(create: (_) => _AuthBloc()),
                BlocProvider<CoinsBloc>(create: (_) => _CoinsBloc()),
                BlocProvider<PlatformBloc>(create: (_) => PlatformBloc()),
                BlocProvider<AnalyticsBloc>(create: (_) => _AnalyticsBloc()),
              ],
              child: Builder(
                builder: (context) => MaterialApp(
                  locale: context.locale,
                  supportedLocales: context.supportedLocales,
                  localizationsDelegates: context.localizationDelegates,
                  home: const Scaffold(
                    body: ConnectWalletButton(
                      eventType: WalletsManagerEventType.header,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('connect-wallet-header')));
      await tester.pumpAndSettle();
      return tester.widget<WalletsManagerWrapper>(
        find.byType(WalletsManagerWrapper),
      );
    }

    testWidgets('the button opens the wallet manager', (tester) async {
      final manager = await open(tester);

      expect(manager.eventType, WalletsManagerEventType.header);
      expect(find.byKey(const Key('create-wallet-button')), findsOneWidget);
    });

    testWidgets('signing in resets the trading forms, then closes', (
      tester,
    ) async {
      final manager = await open(tester);

      manager.onSuccess!(_wallet);
      await tester.pumpAndSettle();

      expect(taker.events, [isA<TakerReInit>()]);
      expect(maker.reInits, 1);
      expect(find.byType(WalletsManagerWrapper), findsNothing);
    });

    testWidgets('cancelling closes without resetting anything', (tester) async {
      final manager = await open(tester);

      manager.onCancel!();
      await tester.pumpAndSettle();

      expect(taker.events, isEmpty);
      expect(maker.reInits, 0);
      expect(find.byType(WalletsManagerWrapper), findsNothing);
    });
  });
}
