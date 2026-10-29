// The analyzer does not treat test_units as tests, so @visibleForTesting
// members read as violations here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/model/settings_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/backup_seed_notification.dart';
import 'package:web_dex/views/swap/swap_shell.dart';

import 'swap_accessibility_checks.dart';

class _EnglishAssetLoader extends AssetLoader {
  const _EnglishAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _AuthBloc extends Cubit<AuthBlocState> implements AuthBloc {
  _AuthBloc(super.initialState);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

KdfUser _notBackedUp() => KdfUser(
  walletId: WalletId.withPubkeyHash(
    'notice-wallet',
    const AuthOptions(derivationMethod: DerivationMethod.hdWallet),
    'notice-wallet-pubkey-hash',
  ),
  isBip39Seed: true,
  metadata: {'type': 'hdwallet', 'has_backup': false},
);

typedef _Layout = ({String name, Size size, bool dark, double textScale});

const List<_Layout> _layouts = [
  (name: '375 dark', size: Size(375, 812), dark: true, textScale: 1),
  (name: '390 dark', size: Size(390, 844), dark: true, textScale: 1),
  (name: '768 light', size: Size(768, 1024), dark: false, textScale: 1),
  (name: '1024 dark', size: Size(1024, 768), dark: true, textScale: 1),
  (name: '1440 light', size: Size(1440, 900), dark: false, textScale: 1),
  (name: '375 light 200%', size: Size(375, 812), dark: false, textScale: 2),
  (name: '1024 dark 200%', size: Size(1024, 768), dark: true, textScale: 2),
];

/// What the app's theme gives buttons by default: on a touch screen, padded
/// targets at standard density; on desktop, shrink-wrapped and compact.
typedef _Input = ({
  String name,
  MaterialTapTargetSize tapTargetSize,
  VisualDensity density,
});

const List<_Input> _inputs = [
  (
    name: 'touch',
    tapTargetSize: MaterialTapTargetSize.padded,
    density: VisualDensity.standard,
  ),
  (
    name: 'desktop',
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    density: VisualDensity.compact,
  ),
];

/// The swap shell for a wallet whose seed is not backed up, in the app's
/// own theme and font, in English.
Future<void> _pump(WidgetTester tester, _Layout layout, _Input input) async {
  final auth = _AuthBloc(AuthBlocState.loggedIn(_notBackedUp()));
  addTearDown(auth.close);
  tester.view.physicalSize = layout.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(resetScreenType);
  final base = layout.dark ? theme.global.dark : theme.global.light;
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'assets/translations',
      assetLoader: const _EnglishAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          theme: base.copyWith(
            materialTapTargetSize: input.tapTargetSize,
            visualDensity: input.density,
            textTheme: base.textTheme.apply(fontFamily: swapFont),
          ),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(layout.textScale)),
            child: app!,
          ),
          home: BlocProvider<AuthBloc>.value(
            value: auth,
            child: Scaffold(
              body: Builder(
                builder: (context) {
                  updateScreenType(context);
                  return SwapShell(
                    destinationBuilder: (d) => Text('body:${d.name}'),
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

final Finder _button = find.descendant(
  of: find.byType(BackupSeedNotification),
  matching: find.byType(ElevatedButton),
);

/// The part of the button that is drawn.
Finder get _pill =>
    find.descendant(of: _button, matching: find.byType(Material)).first;

/// Covers the seed backup notice's button against the swap surface's
/// accessibility checks, wherever the app's theme leaves its tap target.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await loadSwapFont();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  for (final input in _inputs) {
    group('The backup notice\'s button, ${input.name}', () {
      for (final layout in _layouts) {
        testWidgets('meets the swap accessibility checks at ${layout.name}', (
          tester,
        ) async {
          await _pump(tester, layout, input);

          expect(_button, findsOneWidget);
          await expectSwapAccessible(tester, largeText: layout.textScale > 1);
        });
      }

      testWidgets('keeps its 85 × 28 look inside a 48 dp target, which a tap '
          'beside the pill presses', (tester) async {
        final previous = routingState;
        routingState = RoutingState();
        addTearDown(() => routingState = previous);
        await _pump(tester, _layouts.first, input);

        final pill = tester.getRect(_pill);
        expect(pill.size, const Size(85, 28));
        expect(tester.getSemantics(_button).rect.size, const Size(85, 48));

        await tester.tapAt(Offset(pill.center.dx, pill.top - 8));
        await tester.pumpAndSettle();
        expect(
          routingState.settingsState.selectedMenu,
          SettingsMenuValue.security,
        );
      });
    });
  }
}
