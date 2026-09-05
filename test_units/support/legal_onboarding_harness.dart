import 'dart:convert';
import 'dart:io';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/bloc/platform/platform_bloc.dart';
import 'package:web_dex/bloc/settings/settings_bloc.dart';
import 'package:web_dex/bloc/settings/settings_state.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/model/stored_settings.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/legal_documents/legal_acceptance.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/constants.dart';

// Public BIP39 test vector, never a funded wallet.
const legalTestSeed =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
const legalTestPassword = 'Sample-key-123!';

class LegalTestStorage implements BaseStorage {
  final values = <String, dynamic>{};
  @override
  Future<dynamic> read(String key) async => values[key];
  @override
  Future<bool> write(String key, dynamic value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    values.remove(key);
    return true;
  }
}

class LegalFormWallets extends Fake implements WalletsRepository {
  String? uniquenessError;
  @override
  String? validateWalletName(String name) =>
      name.trim().isEmpty ? 'Enter a name' : null;
  @override
  Future<String?> validateWalletNameUniqueness(String name) async =>
      uniquenessError;
}

class LegalFormAuth extends Cubit<AuthBlocState> implements AuthBloc {
  LegalFormAuth() : super(AuthBlocState.initial());
  final events = <AuthBlocEvent>[];
  @override
  void add(AuthBlocEvent event) => events.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends Cubit<SettingsState> implements SettingsBloc {
  _Settings() : super(SettingsState.fromStored(StoredSettings.initial()));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SdkAuth extends Fake implements KomodoDefiLocalAuth {
  @override
  Future<List<KdfUser>> getUsers() async => [];
}

class _Sdk extends Fake implements KomodoDefiSdk {
  _Sdk(this.mnemonicValidator);
  @override
  final MnemonicValidator mnemonicValidator;
  @override
  KomodoDefiLocalAuth get auth => _SdkAuth();
}

class LegalEnglishLoader extends AssetLoader {
  const LegalEnglishLoader();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

Wallet legalTestWallet() => Wallet(
  id: 'sample-wallet',
  name: 'My wallet',
  config: WalletConfig(
    seedPhrase: '',
    type: WalletType.hdwallet,
    activatedCoins: [],
    hasBackup: true,
  ),
);

class LegalFormHarness {
  LegalFormHarness({bool updated = false}) {
    if (updated) {
      storage.values['legal_acceptance_v1'] = LegalAcceptance(
        termsVersion: kCurrentTermsVersion - 1,
        acceptedAt: DateTime.utc(2020),
        surface: 'old-form',
        documentShas: {},
      ).toJson();
    }
    repository = LegalDocumentsRepository(storage: storage);
    agreement = LegalAgreementBloc(repository)
      ..add(const LegalAgreementOpened());
  }
  final storage = LegalTestStorage();
  late final LegalDocumentsRepository repository;
  late final LegalAgreementBloc agreement;
  final wallets = LegalFormWallets();
  final auth = LegalFormAuth();
  final validator = MnemonicValidator();

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(800, 1100),
    double textScale = 1,
  }) async {
    await tester.runAsync(validator.init);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await agreement.close();
      await auth.close();
      repository.dispose();
    });
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('en'),
        saveLocale: false,
        path: 'assets/translations',
        assetLoader: const LegalEnglishLoader(),
        child: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<WalletsRepository>.value(value: wallets),
            RepositoryProvider<LegalDocumentsRepository>.value(
              value: repository,
            ),
            RepositoryProvider<KomodoDefiSdk>.value(value: _Sdk(validator)),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<LegalAgreementBloc>.value(value: agreement),
              BlocProvider<AuthBloc>.value(value: auth),
              BlocProvider<SettingsBloc>(create: (_) => _Settings()),
              BlocProvider<PlatformBloc>(create: (_) => PlatformBloc()),
            ],
            child: Builder(
              builder: (context) => MaterialApp(
                theme: theme.global.dark,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: SizedBox(width: 320, child: child)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> enterLegalField(
  WidgetTester tester,
  String key,
  String value,
) async {
  final field = find.byKey(Key(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

Future<void> tapLegalSubmit(WidgetTester tester, String key) async {
  final button = find.byKey(Key(key));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.pump();
}
