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
        // Coin labels defer their first scroll; drain that delay after disposal.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      });
    }
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
