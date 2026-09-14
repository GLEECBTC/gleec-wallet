import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_bloc.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_event.dart';
import 'package:web_dex/bloc/security_settings/private_key_export_state.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_state.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_asset_section.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_flow_listener.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_export_password_dialog.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/private_key_show.dart';
import 'package:web_dex/views/settings/widgets/security_settings/private_key_settings/widgets/private_key_export_key_tile.dart';
import 'package:web_dex/views/wallet/coin_details/receive/qr_code_address.dart';

import '../../services/security/private_key_export_test_support.dart';
import '../../support/contrast.dart';
import '../../support/contrast_widget.dart';

void main() => testPrivateKeyExportFlow();

void testPrivateKeyExportFlow() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Private key export screen lifecycle', () {
    late FakePrivateKeyExportService service;
    late PrivateKeyExportBloc bloc;
    late SecuritySettingsBloc navigation;
    var ownsBloc = false;

    tearDown(() async {
      if (!ownsBloc && !bloc.isClosed) await bloc.close();
      await navigation.close();
      await service.changes.close();
    });

    Future<void> pump(
      WidgetTester tester, {
      bool pending = false,
      bool ownExportBloc = false,
      ThemeData? appTheme,
    }) async {
      ownsBloc = ownExportBloc;
      service = FakePrivateKeyExportService();
      if (pending) service.pendingExport = Completer<PrivateKeyExportResult>();
      bloc = PrivateKeyExportBloc(
        service: service,
        delivery: FakePrivateKeyExportDelivery(),
      );
      navigation = SecuritySettingsBloc(
        SecuritySettingsState.initialState(),
        kdfSdk: null,
      );
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          startLocale: const Locale('en'),
          saveLocale: false,
          path: 'assets/translations',
          assetLoader: const _ExportTestTranslations(),
          child: Builder(
            builder: (context) => MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              // Both slots get the same object so the result cannot depend on
              // the ambient platform brightness, and the animation is zeroed
              // so Theme.of never returns an interpolated mid-transition
              // colour to a contrast assertion.
              theme: appTheme,
              darkTheme: appTheme,
              themeAnimationDuration: Duration.zero,
              home: MultiBlocProvider(
                providers: [
                  if (ownExportBloc)
                    BlocProvider<PrivateKeyExportBloc>(create: (_) => bloc)
                  else
                    BlocProvider.value(value: bloc),
                  BlocProvider.value(value: navigation),
                ],
                child: const Scaffold(
                  body: PrivateKeyExportFlowListener(
                    child: SingleChildScrollView(child: PrivateKeyShow()),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> ready(WidgetTester tester, {ThemeData? appTheme}) async {
      await pump(tester, appTheme: appTheme);
      bloc.add(PrivateKeyExportRequested());
      await tester.pumpAndSettle();
      expect(bloc.state.phase, PrivateKeyExportPhase.awaitingPassword);
      expect(find.byType(PrivateKeyExportPasswordDialog), findsOneWidget);
      bloc.add(
        PrivateKeyExportPasswordSubmitted(
          bloc.state.operationId,
          SensitiveString(exportPasswordSentinel),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PrivateKeyExportPasswordDialog), findsNothing);
      expect(bloc.state.phase, PrivateKeyExportPhase.ready);
    }

    testWidgets('shows TRON unavailable and no raw key by default', (
      tester,
    ) async {
      await ready(tester);
      expect(
        find.textContaining('TRON and TRC20 tokens is temporarily unavailable'),
        findsNWidgets(2),
      );
      expect(find.textContaining('addresses 0–10'), findsOneWidget);
      expect(
        find.textContaining('The key could not be retrieved'),
        findsOneWidget,
      );
      expect(find.text(exportKeySentinel), findsNothing);
      // Asserted through the BLoC rather than by casting the button to a
      // concrete widget type: `canDeliver` is what actually gates delivery,
      // and the previous `ActionChip` cast turned a presentational change
      // into a failing test that said nothing about behaviour.
      expect(bloc.state.canDeliver, isFalse);
      expect(find.byKey(const Key('private-key-export-copy')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('unlocking exposes no key controls for TRON assets', (
      tester,
    ) async {
      await ready(tester);
      bloc.add(const PrivateKeyExportVisibilityChanged(true));
      await tester.pumpAndSettle();
      for (final asset in ['TRX', 'USDT-TRC20']) {
        final section = find.byWidgetPredicate(
          (widget) =>
              widget is PrivateKeyExportAssetSection &&
              widget.outcome.assetId.id == asset,
        );
        expect(section, findsOneWidget);
        expect(
          find.descendant(
            of: section,
            matching: find.byType(PrivateKeyExportKeyTile),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: section, matching: find.text('Unavailable')),
          findsOneWidget,
        );
      }
      expect(find.byType(PrivateKeyExportKeyTile), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'authentication epoch removes an open QR and displayed results',
      (tester) async {
        await ready(tester);
        bloc.add(const PrivateKeyExportVisibilityChanged(true));
        await tester.pumpAndSettle();
        bloc.add(PrivateKeyExportQrRequested(exportTestAsset('BTC'), 0));
        await tester.pumpAndSettle();
        expect(find.byType(QRCodeAddress), findsOneWidget);
        expect(find.text(exportKeySentinel), findsOneWidget);
        service.current = false;
        service.changes.add(null);
        await tester.pumpAndSettle();
        expect(find.byType(QRCodeAddress), findsNothing);
        expect(find.text(exportKeySentinel), findsNothing);
        expect(bloc.state.result, isNull);
        expect(navigation.state.step, SecuritySettingsStep.securityMain);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'cancel during fetch closes only its prompt and ignores late keys',
      (tester) async {
        await pump(tester, pending: true);
        bloc.add(PrivateKeyExportRequested());
        await tester.pumpAndSettle();
        bloc.add(
          PrivateKeyExportPasswordSubmitted(
            bloc.state.operationId,
            SensitiveString(exportPasswordSentinel),
          ),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const Key('private-key-export-password-cancel')),
        );
        await tester.pumpAndSettle();
        expect(find.byType(PrivateKeyExportPasswordDialog), findsNothing);
        service.pendingExport!.complete(exportTestResult());
        await tester.pumpAndSettle();
        expect(bloc.state.result, isNull);
        expect(navigation.state.step, SecuritySettingsStep.securityMain);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'disposing its owner clears the prompt and rejects late export results',
      (tester) async {
        await pump(tester, pending: true, ownExportBloc: true);
        bloc.add(PrivateKeyExportRequested());
        await tester.pumpAndSettle();
        bloc.add(
          PrivateKeyExportPasswordSubmitted(
            bloc.state.operationId,
            SensitiveString(exportPasswordSentinel),
          ),
        );
        await tester.pump();
        // Match production ownership: removing the host disposes its BLoC
        // and the listener removes any separately owned password route.
        await tester.pumpWidget(const SizedBox.shrink());
        expect(bloc.state.result, isNull);
        expect(bloc.state.phase, PrivateKeyExportPhase.idle);
        service.pendingExport!.complete(exportTestResult());
        await tester.pumpAndSettle();
        expect(find.byType(PrivateKeyExportPasswordDialog), findsNothing);
        expect(find.text(exportKeySentinel), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    // The notices on this screen are the reported bug: they follow Material's
    // contract (surfaceContainer behind onSurface) while the app themes use
    // onSurface as the page background, so the body text is painted in the
    // canvas colour. Nothing caught it because every other test here pumps a
    // bare MaterialApp with no theme and asserts only that strings are present.
    //
    // Both cases unmount the tree before asserting. A failing assertion that
    // leaves the tree mounted deadlocks this group's tearDown against the
    // fake service's synchronous broadcast controller, and a regression guard
    // that hangs the runner instead of failing is worth very little.
    // Every notice, every run of text inside it, in both live themes. The
    // screen paints these on tinted containers, so the assertion composites
    // the whole painted stack rather than trusting a declared colour.
    const restingNotices = [
      'private-key-export-notice-security',
      'private-key-export-notice-coverage',
    ];

    for (final entry in {
      'light': theme.global.light,
      'dark': theme.global.dark,
    }.entries) {
      final themeName = entry.key;
      final themeData = entry.value;

      testWidgets('notices stay legible in the $themeName theme', (
        tester,
      ) async {
        await ready(tester, appTheme: themeData);

        // Unlock so the clipboard caution - which only appears once copying
        // is possible - is on screen and covered too.
        bloc.add(const PrivateKeyExportVisibilityChanged(true));
        await tester.pumpAndSettle();

        final violations = <String>[];
        for (final noticeKey in [
          ...restingNotices,
          'private-key-export-notice-copy',
        ]) {
          final notice = find.byKey(Key(noticeKey));
          expect(notice, findsOneWidget, reason: 'missing $noticeKey');

          final texts = find.descendant(
            of: notice,
            matching: find.byType(Text),
          );
          final count = tester.widgetList<Text>(texts).length;
          expect(count, greaterThan(0), reason: '$noticeKey has no text');

          for (var i = 0; i < count; i++) {
            final text = texts.at(i);
            final foreground = resolvedTextColor(tester, text);
            final background = resolvedBackgroundBehind(tester, text);
            final ratio = contrastRatio(foreground, background);
            if (ratio < wcagAaNormalText) {
              violations.add(
                '$noticeKey[$i]: ${describeColor(foreground)} on '
                '${describeColor(background)} is '
                '${ratio.toStringAsFixed(2)}:1',
              );
            }
          }
        }

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(
          violations,
          isEmpty,
          reason:
              '$themeName theme: notice text below the 4.5:1 AA bar\n'
              '${violations.join("\n")}',
        );
      });

      testWidgets('the reveal gate reads against the page in $themeName', (
        tester,
      ) async {
        await ready(tester, appTheme: themeData);

        final gate = tester.widget<Container>(
          find
              .ancestor(
                of: find.byKey(const Key('private-key-export-visibility')),
                matching: find.byType(Container),
              )
              .last,
        );
        final background = (gate.decoration! as BoxDecoration).color!;
        final ratio = contrastRatio(
          background,
          themeData.scaffoldBackgroundColor,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        // Not a standards figure - WCAG says nothing about a container
        // against its page, and a 3:1 bar would rule out every tinted surface
        // Material itself ships. This is only a "not effectively the same
        // colour" guard: it catches the collapsed light ramp that painted a
        // white box on a #FBFBFB page at 1.03:1, while leaving room for a
        // deliberately subtle tint.
        expect(
          ratio,
          greaterThanOrEqualTo(1.05),
          reason:
              '$themeName theme: the reveal gate '
              '${describeColor(background)} is indistinguishable from the '
              'page ${describeColor(themeData.scaffoldBackgroundColor)} '
              '(${ratio.toStringAsFixed(2)}:1)',
        );
      });
    }
  });
}

class _ExportTestTranslations extends AssetLoader {
  const _ExportTestTranslations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(File('$path/en.json').readAsStringSync())
          as Map<String, dynamic>;
}
