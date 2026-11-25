// The analyzer does not treat test_units as tests, so test-only members
// read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';

/// Loads the English strings from disk, so tests need no asset bundle.
class WalletHomeEnglishLoader extends AssetLoader {
  const WalletHomeEnglishLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

class FakeWalletHomeAuth extends Cubit<AuthBlocState> implements AuthBloc {
  FakeWalletHomeAuth([AuthBlocState? state])
    : super(state ?? AuthBlocState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

KdfUser walletHomeUser({bool trezor = false}) => KdfUser(
  walletId: WalletId.withPubkeyHash(
    trezor ? 'trezor' : 'Savings',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    trezor ? 'trezor-pubkey-hash' : 'savings-pubkey-hash',
  ),
  isBip39Seed: !trezor,
  metadata: {'has_backup': true, if (trezor) 'type': 'trezor'},
);

Future<void> initWalletHomeLocalization() async {
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();
}

/// Pumps [child] in the dark theme, in English, with a sign-in of [auth], on
/// a phone unless [size] says otherwise.
Future<void> pumpWalletHome(
  WidgetTester tester,
  Widget child, {
  AuthBlocState? auth,
  bool reduceMotion = false,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const WalletHomeEnglishLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          theme: ThemeData.dark(),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
          home: BlocProvider<AuthBloc>(
            create: (_) => FakeWalletHomeAuth(auth),
            child: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
