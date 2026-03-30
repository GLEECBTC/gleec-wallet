import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_event.dart';
import 'package:web_dex/bloc/analytics/analytics_state.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/wallets_manager/wallets_manager_events_factory.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallets_manager.dart';

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

class _FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _FakeAuthBloc(super.initialState);

  @override
  void add(AuthBlocEvent event) {}

  void emitState(AuthBlocState newState) => emit(newState);

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

  @override
  void add(AnalyticsEvent event) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

KdfUser _buildTrezorUser(String walletName) {
  return KdfUser(
    walletId: WalletId.fromName(
      walletName,
      const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    ),
    isBip39Seed: true,
    metadata: const {
      'type': 'trezor',
      'has_backup': true,
      'activated_coins': <String>[],
    },
  );
}

Future<void> _pumpWalletsManager(
  WidgetTester tester, {
  required _FakeAuthBloc authBloc,
  required _FakeCoinsBloc coinsBloc,
  required _FakeAnalyticsBloc analyticsBloc,
  required VoidCallback onClose,
  required void Function(Wallet) onSuccess,
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
        builder: (context) {
          return MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: MultiBlocProvider(
              providers: [
                BlocProvider<AuthBloc>.value(value: authBloc),
                BlocProvider<CoinsBloc>.value(value: coinsBloc),
                BlocProvider<AnalyticsBloc>.value(value: analyticsBloc),
              ],
              child: Scaffold(
                body: WalletsManager(
                  eventType: WalletsManagerEventType.wallet,
                  walletType: WalletType.trezor,
                  close: onClose,
                  onSuccess: onSuccess,
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('trezor branch propagates success callback from WalletsManager', (
    tester,
  ) async {
    final authBloc = _FakeAuthBloc(AuthBlocState.loading());
    final coinsBloc = _FakeCoinsBloc();
    final analyticsBloc = _FakeAnalyticsBloc();
    addTearDown(authBloc.close);
    addTearDown(coinsBloc.close);
    addTearDown(analyticsBloc.close);

    var closeCalls = 0;
    var successCalls = 0;
    Wallet? successWallet;

    await _pumpWalletsManager(
      tester,
      authBloc: authBloc,
      coinsBloc: coinsBloc,
      analyticsBloc: analyticsBloc,
      onClose: () => closeCalls++,
      onSuccess: (wallet) {
        successCalls++;
        successWallet = wallet;
      },
    );

    authBloc.emitState(AuthBlocState.loggedIn(_buildTrezorUser('wallet-x')));
    await tester.pump();

    expect(successCalls, 1);
    expect(successWallet, isNotNull);
    expect(successWallet!.name, 'wallet-x');
    expect(closeCalls, 0);
  });
}
