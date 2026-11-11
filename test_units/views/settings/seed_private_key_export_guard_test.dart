import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/mm2/mm2_api/rpc/show_priv_key/show_priv_key_request.dart';
import 'package:web_dex/mm2/mm2_api/rpc/show_priv_key/show_priv_key_response.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/services/wallet_access/unlock_coordinator.dart';
import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/views/common/wallet_password_dialog/password_dialog_content.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_settings_main_page.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_settings_page.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/seed_show.dart';

import '../../tests/utils/test_util.dart';
import '../../helpers/runtime_auth_fixture.dart';

const _seed = 'synthetic recovery phrase';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final method in [DerivationMethod.iguana, DerivationMethod.hdWallet]) {
    for (final includeSupported in [true, false]) {
      testWidgets('seed backup excludes TRON keys for ${method.name} '
          '${includeSupported ? 'mixed' : 'TRON-only'} wallets', (
        tester,
      ) async {
        final tron = _coin('TRX', CoinSubClass.trx);
        final coins = [
          tron,
          _coin('TRX-TEST', CoinSubClass.trx),
          _coin('USDT-TRC20', CoinSubClass.trc20, parentId: tron.id),
          // The protocol guard must also cover an unresolved token parent.
          _coin('CUSTOM-TRC20', CoinSubClass.trc20),
          if (includeSupported) ...[
            _coin('KMD', CoinSubClass.smartChain),
            _coin('ETH', CoinSubClass.erc20),
            _coin('SIA', CoinSubClass.sia),
          ],
        ];
        final user = KdfUser(
          walletId: WalletId.withPubkeyHash(
            'synthetic wallet',
            AuthOptions(derivationMethod: method),
            'synthetic-wallet-hash',
          ),
          isBip39Seed: true,
          metadata: {
            'type': method == DerivationMethod.hdWallet ? 'hdwallet' : 'iguana',
            'has_backup': false,
          },
        );
        final authBloc = _AuthBloc(AuthBlocState.loggedIn(user));
        final coinsBloc = _CoinsBloc(
          CoinsState.initial().copyWith(
            walletCoins: {for (final coin in coins) coin.abbr: coin},
          ),
        );
        final api = _Api();
        addTearDown(authBloc.close);
        addTearDown(coinsBloc.close);
        final oldSize = Size(screenWidth, screenHeight);
        addTearDown(() async {
          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(size: oldSize),
              child: Builder(
                builder: (context) {
                  updateScreenType(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1;

        await tester.pumpWidget(
          EasyLocalization(
            supportedLocales: const [Locale('en')],
            startLocale: const Locale('en'),
            saveLocale: false,
            path: 'assets/translations',
            assetLoader: const _Translations(),
            child: Builder(
              builder: (context) => MultiRepositoryProvider(
                providers: [
                  RepositoryProvider<KomodoDefiSdk>.value(
                    value: _Sdk(_Auth(user)),
                  ),
                  RepositoryProvider<Mm2Api>.value(value: api),
                ],
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider<AuthBloc>.value(value: authBloc),
                    BlocProvider<CoinsBloc>.value(value: coinsBloc),
                  ],
                  child: MaterialApp(
                    locale: context.locale,
                    supportedLocales: context.supportedLocales,
                    localizationsDelegates: context.localizationDelegates,
                    home: Builder(
                      builder: (context) {
                        updateScreenType(context);
                        return Scaffold(
                          body: SecuritySettingsPage(onBackPressed: () {}),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final mainPage = find.byType(SecuritySettingsMainPage);
        tester
            .widget<SecuritySettingsMainPage>(mainPage)
            .onViewSeedPressed(tester.element(mainPage));
        await tester.pumpAndSettle();
        tester
            .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
            .onSuccess('synthetic password');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        final seedView = tester.widget<SeedShow>(find.byType(SeedShow));
        expect(seedView.seedPhrase, _seed);
        final expectedCoins = includeSupported ? ['KMD', 'ETH'] : <String>[];
        expect(api.requestedCoins, expectedCoins);
        expect(seedView.privKeys.keys.map((coin) => coin.abbr), expectedCoins);
        expect(
          seedView.privKeys.values,
          expectedCoins.map((coin) => 'synthetic-$coin-key'),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final interruption in ['lock', 'pause', 'wallet switch']) {
    for (final boundary in ['before dispatch', 'late result']) {
      testWidgets('seed settings reject $interruption at mnemonic $boundary', (
        tester,
      ) async {
        final user = _guardedUser();
        final authBloc = _AuthBloc(AuthBlocState.loggedIn(user));
        final auth = _GuardedAuth(user);
        final access = _Access(user.walletId);
        final api = _GuardedApi();
        final delay = Completer<void>();
        if (boundary == 'before dispatch') {
          auth.beforeDispatch = delay.future;
        } else {
          auth.beforeResult = delay.future;
        }
        addTearDown(authBloc.close);
        addTearDown(access.unlockCoordinator.dispose);
        await _pumpGuardedSettings(
          tester,
          authBloc: authBloc,
          auth: auth,
          access: access,
          api: api,
        );
        await _authorizeSeed(tester);
        expect(auth.mnemonicCalls, 1);
        expect(access.captures, 1);
        if (interruption == 'lock') {
          access.unlockCoordinator.lock();
        } else if (interruption == 'pause') {
          access.unlockCoordinator.background();
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        } else {
          final replacement = _guardedUser('replacement-hash');
          auth.replace(replacement);
          authBloc.updateUser(replacement);
          access.unlockCoordinator.attachWallet(
            'replacement',
            requiresAuthentication: true,
            authenticated: true,
          );
        }
        delay.complete();
        await tester.pumpAndSettle();
        expect(auth.mnemonicDispatches, boundary == 'before dispatch' ? 0 : 1);
        expect(api.requestedCoins, isEmpty);
        expect(find.byType(SeedShow), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final boundary in ['before dispatch', 'late result']) {
    testWidgets('seed settings reject lock at private-key $boundary', (
      tester,
    ) async {
      final user = _guardedUser();
      final authBloc = _AuthBloc(AuthBlocState.loggedIn(user));
      final auth = _GuardedAuth(user);
      final access = _Access(user.walletId);
      final api = _GuardedApi();
      final delay = Completer<void>();
      if (boundary == 'before dispatch') {
        api.beforeDispatch = delay.future;
      } else {
        api.beforeResult = delay.future;
      }
      addTearDown(authBloc.close);
      addTearDown(access.unlockCoordinator.dispose);
      await _pumpGuardedSettings(
        tester,
        authBloc: authBloc,
        auth: auth,
        access: access,
        api: api,
      );
      await _authorizeSeed(tester);
      expect(api.calls, 1);
      access.unlockCoordinator.lock();
      delay.complete();
      await tester.pumpAndSettle();
      expect(
        api.requestedCoins,
        boundary == 'before dispatch' ? isEmpty : ['KMD'],
      );
      expect(find.byType(SeedShow), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Coin _coin(String id, CoinSubClass subClass, {AssetId? parentId}) {
  final coin = setCoin(coinAbbr: id);
  return coin.copyWith(
    id: coin.id.copyWith(subClass: subClass, parentId: parentId),
  );
}

class _AuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _AuthBloc(super.initialState);

  void updateUser(KdfUser user) => emit(AuthBlocState.loggedIn(user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CoinsBloc extends Cubit<CoinsState> implements CoinsBloc {
  _CoinsBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sdk extends Fake implements KomodoDefiSdk {
  _Sdk(this.auth);

  @override
  final KomodoDefiLocalAuth auth;

  @override
  final MnemonicValidator mnemonicValidator = _SeedValidator();
}

class _SeedValidator extends MnemonicValidator {
  @override
  bool validateBip39(String input) => false;
}

class _Auth extends Fake
    with RuntimeAuthFixture
    implements KomodoDefiLocalAuth {
  _Auth(this.user);

  final KdfUser user;

  @override
  Stream<int> get authGenerationChanges => const Stream.empty();

  @override
  Future<KdfUser?> get currentUser async => user;

  @override
  Future<Mnemonic> getMnemonicPlainText(String password) async =>
      Mnemonic.plaintext(_seed);
}

class _Api extends Fake implements Mm2Api {
  final requestedCoins = <String>[];

  @override
  Future<ShowPrivKeyResponse?> showPrivKey(ShowPrivKeyRequest request) async {
    requestedCoins.add(request.coin);
    return ShowPrivKeyResponse(
      coin: request.coin,
      privKey: 'synthetic-${request.coin}-key',
    );
  }
}

class _Translations extends AssetLoader {
  const _Translations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

KdfUser _guardedUser([String hash = 'guarded-hash']) => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'guarded wallet',
    const AuthOptions(derivationMethod: DerivationMethod.iguana),
    hash,
  ),
  isBip39Seed: true,
  metadata: const {'type': 'iguana', 'recovery_evidence': 'none'},
);

class _Access extends Fake implements WalletAccessService {
  _Access(this.walletId) {
    unlockCoordinator.attachWallet(
      'guarded-entry',
      requiresAuthentication: true,
      authenticated: true,
    );
  }
  final WalletId walletId;
  int captures = 0;
  @override
  final unlockCoordinator = WalletUnlockCoordinator(
    operationGate: WalletOperationGate(),
  );
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<WalletAccessStatus> status({WalletId? walletId}) async =>
      const WalletAccessStatus(
        entryId: 'guarded-entry',
        protection: CredentialProtection.authenticationBound,
        hasManagedCredential: true,
        requiresAuthentication: true,
      );
  @override
  Future<WalletAccessStatus> statusForWallet(Wallet wallet) => status();
  @override
  Future<CredentialCapabilities> capabilities() async =>
      const CredentialCapabilities(
        available: true,
        protection: CredentialProtection.authenticationBound,
      );
  @override
  void Function() captureSensitiveOperation(WalletId walletId) {
    expectSync(walletId, this.walletId);
    captures++;
    return unlockCoordinator.operationGate.capture().ensureCurrent;
  }
}

class _GuardedAuth extends _Auth {
  _GuardedAuth(super.user) : activeUser = user;
  KdfUser activeUser;
  Future<void>? beforeDispatch;
  Future<void>? beforeResult;
  int mnemonicCalls = 0;
  int mnemonicDispatches = 0;
  void replace(KdfUser user) {
    activeUser = user;
    runtimeSessions.observe(user);
  }

  @override
  Future<KdfUser?> get currentUser async => activeUser;
  @override
  Future<Mnemonic> getMnemonicPlainText(String password) async {
    mnemonicCalls++;
    await beforeDispatch;
    RpcDispatchGuard.ensureCurrent('get_mnemonic');
    mnemonicDispatches++;
    await beforeResult;
    return Mnemonic.plaintext(_seed);
  }
}

class _GuardedApi extends _Api {
  Future<void>? beforeDispatch;
  Future<void>? beforeResult;
  int calls = 0;
  @override
  Future<ShowPrivKeyResponse?> showPrivKey(ShowPrivKeyRequest request) async {
    calls++;
    await beforeDispatch;
    RpcDispatchGuard.ensureCurrent('show_priv_key');
    final response = await super.showPrivKey(request);
    await beforeResult;
    return response;
  }
}

Future<void> _authorizeSeed(WidgetTester tester) async {
  final main = find.byType(SecuritySettingsMainPage);
  unawaited(
    tester
            .widget<SecuritySettingsMainPage>(main)
            .onViewSeedPressed(tester.element(main))
        as Future<void>,
  );
  await tester.pumpAndSettle();
  tester
      .widget<PasswordDialogContent>(find.byType(PasswordDialogContent))
      .onSuccess('synthetic password');
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pumpAndSettle();
}

Future<void> _pumpGuardedSettings(
  WidgetTester tester, {
  required _AuthBloc authBloc,
  required _GuardedAuth auth,
  required _Access access,
  required _GuardedApi api,
}) async {
  final oldSize = Size(screenWidth, screenHeight);
  final coin = _coin('KMD', CoinSubClass.smartChain);
  final coins = _CoinsBloc(
    CoinsState.initial().copyWith(walletCoins: {coin.abbr: coin}),
  );
  addTearDown(coins.close);
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: oldSize),
        child: Builder(
          builder: (context) {
            updateScreenType(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MultiRepositoryProvider(
          providers: [
            RepositoryProvider<KomodoDefiSdk>.value(value: _Sdk(auth)),
            RepositoryProvider<Mm2Api>.value(value: api),
            RepositoryProvider<WalletAccessService>.value(value: access),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<AuthBloc>.value(value: authBloc),
              BlocProvider<CoinsBloc>.value(value: coins),
            ],
            child: MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: Builder(
                builder: (context) {
                  updateScreenType(context);
                  return Scaffold(
                    body: SingleChildScrollView(
                      child: SecuritySettingsPage(onBackPressed: () {}),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
