import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_simple_import.dart';

class _FakeSdk extends Fake implements KomodoDefiSdk {
  _FakeSdk(this.mnemonicValidator);
  @override
  final MnemonicValidator mnemonicValidator;
}

class _FakeAuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _FakeAuthBloc() : super(AuthBlocState.initial());
  @override
  void add(AuthBlocEvent event) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsState extends Fake implements SettingsState {
  @override
  bool get weakPasswordsAllowed => false;
}

class _FakeSettingsBloc extends Cubit<SettingsState> implements SettingsBloc {
  _FakeSettingsBloc() : super(_FakeSettingsState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWalletsRepository extends Fake implements WalletsRepository {
  @override
  String? validateWalletName(String name) => null;
  @override
  Future<String?> validateWalletNameUniqueness(String name) async => null;
}

class _EmptyAssetLoader extends AssetLoader {
  const _EmptyAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {};
}

void main() {
  setUpAll(() async {
    // The analyzer does not recognize the test_units directory as test code.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('import becomes enabled when matching passwords are entered', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final validator = MnemonicValidator();
    await validator.init();
    final sdk = _FakeSdk(validator);
    final auth = _FakeAuthBloc();
    final settings = _FakeSettingsBloc();
    final wallets = _FakeWalletsRepository();
    addTearDown(auth.close);
    addTearDown(settings.close);
    var imports = 0;

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const _EmptyAssetLoader(),
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: MultiRepositoryProvider(
              providers: [
                RepositoryProvider<KomodoDefiSdk>.value(value: sdk),
                RepositoryProvider<WalletsRepository>.value(value: wallets),
              ],
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<AuthBloc>.value(value: auth),
                  BlocProvider<SettingsBloc>.value(value: settings),
                ],
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: WalletSimpleImport(
                      onImport:
                          ({
                            required name,
                            required password,
                            required walletConfig,
                            required rememberMe,
                          }) => imports++,
                      onUploadFiles:
                          ({required fileName, required fileData}) {},
                      onCancel: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const Key('confirm-seed-button'));
    final password = find.byKey(const Key('create-password-field'));
    final confirmation = find.byKey(const Key('create-password-field-confirm'));
    await tester.enterText(find.byKey(const Key('name-wallet-field')), 'test');
    await tester.enterText(
      find.byKey(const Key('import-seed-field')),
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(password, findsOneWidget);
    expect(tester.widget<UiPrimaryButton>(button).onPressed, isNull);

    await tester.enterText(password, 'Y7!m9pQ2rV4#sT6z');
    await tester.enterText(confirmation, 'Y7!m9pQ2rV4#sT6z');
    await tester.pumpAndSettle();
    expect(tester.widget<UiPrimaryButton>(button).onPressed, isNotNull);

    await tester.enterText(confirmation, 'different-password');
    await tester.pumpAndSettle();
    expect(tester.widget<UiPrimaryButton>(button).onPressed, isNull);

    await tester.enterText(confirmation, 'Y7!m9pQ2rV4#sT6z');
    await tester.pumpAndSettle();
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(imports, 1);
  });
}
