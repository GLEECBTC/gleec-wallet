// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/main.dart' as app;

import '../../common/widget_tester_pump_extension.dart';
import '../../helpers/accept_alpha_warning.dart';
import '../../helpers/restore_wallet.dart';

// These testnet-only entries have no logo in the published coin asset bundle.
// Keep this explicit: a newly missing production logo must fail this test.
const _unbrandedTestnetIcons = {'SCZEN', 'TRXT', 'TESTUSDT-TRC20'};

Future<void> testCoinIcons(WidgetTester tester) async {
  print('🔍 COIN ICONS: Starting coin icons test');

  final Finder walletTab = find.byKey(const Key('main-menu-wallet'));
  final Finder addAssetsButton = find.byKey(const Key('add-assets-button'));

  await tester.tap(walletTab);
  print('🔍 COIN ICONS: Tapped wallet tab');
  await tester.pumpAndSettle();

  await tester.tap(addAssetsButton);
  print('🔍 COIN ICONS: Tapped add assets button');
  await tester.pumpAndSettle();

  final listFinder = find.byKey(const Key('coins-manager-list'));
  final iconsFinder = find.descendant(
    of: listFinder,
    matching: find.byType(AssetIcon),
  );

  print('🔍 COIN ICONS: Starting icon verification loop');

  int pageCount = 0;
  final checkedAssets = <String>{};
  // Scroll down the list until we reach the end
  while (true) {
    pageCount++;
    print('🔍 COIN ICONS: Checking page $pageCount');

    // The manager loads its coin list asynchronously. An idle animation queue
    // does not mean those rows have arrived, especially on a cold Safari run.
    if (!tester.any(iconsFinder)) {
      await tester.pumpUntilFound(
        iconsFinder,
        timeout: const Duration(seconds: 30),
        describeTarget: 'coin icons on asset list page $pageCount',
      );
    }
    final coinIcons = iconsFinder.evaluate().toList();
    expect(
      coinIcons,
      isNotEmpty,
      reason: 'Asset list page $pageCount must contain icons',
    );

    // Snapshot image paths before awaiting bundle reads: live balance updates
    // may rebuild the rows while an asynchronous asset load is in flight.
    final assetPaths = coinIcons
        .map((iconElement) {
          // Protocol overlays use AssetIcon.ofTicker and have no AssetId. Their
          // public parent supplies the network ticker instead.
          final iconFinder = find.byWidget(iconElement.widget);
          final imageFinder = find.descendant(
            of: iconFinder,
            matching: find.byType(Image),
          );
          final asset = (iconElement.widget as AssetIcon).assetId?.id;
          final protocol = find
              .ancestor(
                of: iconFinder,
                matching: find.byType(AssetProtocolIcon),
              )
              .evaluate()
              .map(
                (element) =>
                    (element.widget as AssetProtocolIcon).protocolTicker,
              )
              .firstOrNull;
          final id = asset ?? protocol;
          expect(
            id,
            isNotNull,
            reason: 'Every icon must identify its asset/network',
          );
          final symbol = AssetSymbol.symbolFromConfigId(id!).toLowerCase();
          final assetPath = '$coinsAssetsPath/coin_icons/png/$symbol.png';
          final images = tester
              .widgetList<Image>(imageFinder)
              .map((w) => w.image);
          final genericFallback = find.descendant(
            of: iconFinder,
            matching: find.byIcon(Icons.monetization_on_outlined),
          );

          // Known unbranded testnets may use the SDK's documented CDN/generic
          // fallback. Every other asset and network badge must keep its image.
          if (_unbrandedTestnetIcons.contains(id)) {
            expect(
              images.any(
                    (image) =>
                        image is NetworkImage &&
                        image.url ==
                            'https://gleecbtc.github.io/coins/icons/$symbol.png',
                  ) ||
                  genericFallback.evaluate().length == 1,
              isTrue,
              reason:
                  '$id must display its CDN logo or explicit generic fallback',
            );
            return null;
          }
          expect(
            images.whereType<AssetImage>().map((image) => image.keyName),
            contains(assetPath),
            reason: 'Icon for $id must display its bundled image $assetPath',
          );
          expect(
            genericFallback,
            findsNothing,
            reason: 'Bundled icon for $id failed',
          );
          return assetPath;
        })
        .whereType<String>()
        .toList();

    for (final assetPath in assetPaths) {
      if (!checkedAssets.add(assetPath)) continue;
      final assetExists = await canLoadAsset(assetPath);
      print('🔍 COIN ICONS: Checking $assetPath: ${assetExists ? "✓" : "✗"}');
      expect(assetExists, true, reason: 'Asset $assetPath does not exist');
    }

    // Check the final page before terminating, including the short-list case.
    final scrollable = tester.widget<ListView>(listFinder);
    final position = scrollable.controller!.position;
    if (position.pixels >= position.maxScrollExtent) break;
    final previousPosition = position.pixels;

    // Scroll the list
    await tester.drag(listFinder, const Offset(0, -500));
    print('🔍 COIN ICONS: Scrolled to next page');
    await tester.pumpAndSettle();
    expect(
      position.pixels,
      greaterThan(previousPosition),
      reason: 'The asset list must advance until every icon has been checked',
    );
  }

  print('🔍 COIN ICONS: Completed verification of all coin icons');
}

Future<bool> canLoadAsset(String assetPath) async {
  bool assetExists = true;
  try {
    final data = await rootBundle.load(assetPath);
    assetExists = data.lengthInBytes > 0;
  } catch (e) {
    print('🔍 ASSET CHECK: Failed to load asset: $assetPath');
    assetExists = false;
  }
  return assetExists;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Run coin icons tests:', (WidgetTester tester) async {
    print('🔍 MAIN: Starting coin icons test suite');
    tester.testTextInput.register();
    await app.main();
    await tester.pumpAndSettle();

    print('🔍 MAIN: Accepting alpha warning');
    await acceptAlphaWarning(tester);

    await restoreWalletToTest(tester);
    print('🔍 MAIN: Wallet restored');

    await testCoinIcons(tester);
    await tester.pumpAndSettle();

    print('🔍 MAIN: Coin icons tests completed successfully');
  }, semanticsEnabled: false);
}
