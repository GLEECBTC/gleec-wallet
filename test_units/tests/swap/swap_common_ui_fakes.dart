// The analyzer does not treat test_units as tests, so
// SharedPreferences.setMockInitialValues reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// No public API loads or resets the package's global translations.
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';

import 'swap_accessibility_checks.dart';
import 'swap_test_fixtures.dart';

const swapAddress = '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91';

Map<String, dynamic> _readEnglish() =>
    jsonDecode(File('assets/translations/en.json').readAsStringSync())
        as Map<String, dynamic>;

final Map<String, dynamic> _english = _readEnglish();

class SwapEnglishLoader extends AssetLoader {
  const SwapEnglishLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      _readEnglish();
}

/// Loads English around each test of the enclosing group. Per test, not per
/// group: other suites reset the global strings after each of their tests.
void useEnglishCopy() {
  setUp(
    () => Localization.load(
      const Locale('en'),
      translations: Translations(_english),
    ),
  );
  tearDown(() => Localization.load(const Locale('en')));
}

const Object _default = Object();

/// A snapshot like [snapshotOf], with the fields it fixes settable too.
SwapExecutionSnapshot snap({
  String id = 'swap-1',
  SwapLiquiditySource source = SwapLiquiditySource.routed,
  SwapRouteKind routeKind = SwapRouteKind.sameChain,
  SwapProgressStage? stage = SwapProgressStage.confirming,
  SwapExecutionOutcome? outcome,
  SwapFundsMovement fundsMovement = SwapFundsMovement.sent,
  Object? from = _default,
  Object? to = _default,
  String fromTicker = 'ETH',
  String toTicker = 'USDC-ERC20',
  String? sell = '1',
  String? expected = '3000',
  String? minimum = '2985',
  String? toAddress = swapAddress,
  SwapApprovalRequirement? approval,
  bool approvalRemains = false,
  List<SwapRouteStage>? stages,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? delayedSince,
  SwapEvidence? evidence,
}) => SwapExecutionSnapshot(
  id: id,
  source: source,
  routeKind: routeKind,
  from: identical(from, _default) ? eth : from as AssetId?,
  fromTicker: fromTicker,
  to: identical(to, _default) ? usdc : to as AssetId?,
  toTicker: toTicker,
  sellAmount: sell == null ? null : d(sell),
  expectedReceive: expected == null ? null : d(expected),
  minimumReceive: minimum == null ? null : d(minimum),
  fromAddress: swapAddress,
  toAddress: toAddress,
  stage: outcome == null ? stage : null,
  outcome: outcome,
  fundsMovement: fundsMovement,
  canCancel: false,
  approval: approval,
  approvalRemains: approvalRemains,
  stages:
      stages ??
      [
        const SwapRouteStage(kind: SwapRouteStageKind.prepare),
        SwapRouteStage(kind: SwapRouteStageKind.send, asset: eth),
        SwapRouteStage(kind: SwapRouteStageKind.receive, asset: usdc),
      ],
  createdAt: createdAt,
  updatedAt: updatedAt,
  delayedSince: delayedSince,
  evidence: evidence ?? SwapEvidence(executionId: id),
);

/// Readies the enclosing group for [pumpSwapUi], resetting the global strings
/// after each test for the suites that assert keys.
void useSwapUi() {
  setUpAll(() async {
    await loadSwapFont();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  tearDown(() => Localization.load(const Locale('en')));
}

typedef SwapMedia = ({
  double textScale,
  bool boldText,
  bool reduceMotion,
  bool announces,
});

const SwapMedia swapDefaultMedia = (
  textScale: 1,
  boldText: false,
  reduceMotion: false,
  announces: false,
);

/// Pumps [child] in the app's English, font and theme. Pass [settle] false
/// for content that animates forever.
Future<void> pumpSwapUi(
  WidgetTester tester,
  Widget child, {
  bool dark = true,
  Size size = const Size(420, 900),
  SwapMedia media = swapDefaultMedia,
  bool settle = true,
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
      assetLoader: const SwapEnglishLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
            fontFamily: swapFont,
            // copyToClipBoard gives its snack bar a width once another test
            // leaves the global screen type on desktop; a fixed one asserts.
            snackBarTheme: const SnackBarThemeData(
              behavior: SnackBarBehavior.floating,
            ),
          ),
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(media.textScale),
              boldText: media.boldText,
              disableAnimations: media.reduceMotion,
              supportsAnnounce: media.announces,
            ),
            child: app!,
          ),
          home: Scaffold(body: child),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}
