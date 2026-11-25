// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_view.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/common/swap_legal_notice.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import '../../support/legal_documents_fixture.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_common_ui_fakes.dart' as common;
import 'swap_test_fixtures.dart';

/// Covers the review's frame: the status badge, the one action each status
/// allows, the ways back, the permission asked for and the routing
/// provider's terms.
///
/// Copy is looked up by key wherever it is not the point of the test, so a
/// reworded string does not read as a broken review.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpSwapUi();

  late RecordingSwapBloc swap;
  late FakeSwapServices services;

  setUp(() {
    swap = RecordingSwapBloc();
    services = FakeSwapServices();
  });

  tearDown(() => swap.close());

  UnifiedSwapState reviewing(
    SwapReviewStatus status, {
    SwapQuote? quote,
    bool termsRequired = false,
  }) => swapPricedForm().copyWith(
    view: UnifiedSwapView.review,
    review: SwapReview(
      legalSnapshot: legalFixtureSnapshot(),
      quote: quote ?? quoteOf(),
      status: status,
      termsRequired: termsRequired,
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    UnifiedSwapState state, {
    bool inPanel = false,
    SwapShellController? shell,
    Size size = const Size(420, 1600),
  }) async {
    swap.emit(state);
    final busy =
        state.tradingStatusLoading ||
        switch (state.review?.status) {
          SwapReviewStatus.revalidating || SwapReviewStatus.starting => true,
          _ => false,
        };
    await pumpSwapUi(
      tester,
      SwapReviewView(inPanel: inPanel),
      bloc: swap,
      services: services,
      shell: shell,
      size: size,
      settle: !busy,
    );
  }

  List<String> badges(WidgetTester tester) => [
    for (final badge in tester.widgetList<SwapBadge>(find.byType(SwapBadge)))
      badge.label,
  ];

  final back = find.byTooltip('Back');

  group('availability', () {
    testWidgets('checking never claims a confirmed restriction', (
      tester,
    ) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready)
            .copyWith(tradingEnabled: false, tradingStatusLoading: true),
      );
      expect(find.text('swapAvailabilityChecking'.tr()), findsNWidgets(2));
      expect(find.textContaining('your location'), findsNothing);
      final button = tester.widget<SwapButton>(
        find.byKey(const Key('swap-start')),
      );
      expect(button.busy, isTrue);
      expect(button.onPressed, isNull);
    });

    testWidgets('an unavailable check offers retry without location copy', (
      tester,
    ) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready)
            .copyWith(tradingEnabled: false, tradingStatusUnavailable: true),
      );
      expect(find.text('swapAvailabilityUnavailable'.tr()), findsOneWidget);
      expect(find.textContaining('your location'), findsNothing);
      expect(
        swapButtonEnabled(tester, find.text(LocaleKeys.tryAgain.tr())),
        isTrue,
      );
    });
  });

  group('the status badge', () {
    for (final (status, badge) in [
      (SwapReviewStatus.ready, LocaleKeys.swapReviewReady),
      (SwapReviewStatus.revalidating, LocaleKeys.swapReviewChecking),
      (SwapReviewStatus.starting, LocaleKeys.swapReviewStartingBadge),
    ]) {
      testWidgets('names the quiet status ${status.name}', (tester) async {
        await pump(tester, reviewing(status));
        expect(badges(tester), [badge.tr()]);
      });
    }

    // One signal: a status the user must act on is a callout, and a badge
    // over it said the same thing twice.
    for (final status in [
      SwapReviewStatus.revalidationFailed,
      SwapReviewStatus.expired,
      SwapReviewStatus.materialUpdate,
      SwapReviewStatus.rejected,
      SwapReviewStatus.unconfirmed,
    ]) {
      testWidgets('is left out once ${status.name}, for the callout to say', (
        tester,
      ) async {
        await pump(tester, reviewing(status));
        expect(badges(tester), isEmpty);
        expect(find.byType(SwapCallout), findsOneWidget);
      });
    }
  });

  group('the footer', () {
    for (final (status, label, commits) in [
      (SwapReviewStatus.ready, 'swapConfirmSwap', true),
      (SwapReviewStatus.materialUpdate, LocaleKeys.swapAcceptUpdated, true),
      (SwapReviewStatus.expired, LocaleKeys.swapCtaRefresh, false),
      (SwapReviewStatus.revalidationFailed, LocaleKeys.tryAgain, false),
      (SwapReviewStatus.rejected, LocaleKeys.tryAgain, false),
    ]) {
      // The bloc decides: re-price in place, or re-price and start.
      testWidgets('offers its action while ${status.name}, asking the bloc '
          'to go on', (tester) async {
        await pump(tester, reviewing(status));
        // An action that commits funds is armed a moment after it appears;
        // a retry is not held back.
        if (commits) await tester.pump(swapCommitArmingDelay);
        await tester.tap(find.text(label.tr()));
        await tester.pumpAndSettle();

        expect(swap.events, [const UnifiedSwapStartRequested()]);
      });
    }

    for (final (status, label) in [
      (SwapReviewStatus.revalidating, LocaleKeys.swapCtaChecking),
      (SwapReviewStatus.starting, LocaleKeys.swapCtaStarting),
    ]) {
      testWidgets('waits, busy, while ${status.name}', (tester) async {
        await pump(tester, reviewing(status));

        final button = tester.widget<SwapButton>(
          find.byKey(const Key('swap-start')),
        );
        expect(button.label, label.tr());
        expect(button.busy, isTrue);
        expect(button.onPressed, isNull);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.pump(swapCommitArmingDelay);
        await tester.tap(find.byKey(const Key('swap-start')));
        expect(swap.events, isEmpty);
      });
    }

    testWidgets('after a start that was not confirmed, points to Activity', (
      tester,
    ) async {
      final shell = SwapShellController();
      addTearDown(shell.dispose);
      await pump(tester, reviewing(SwapReviewStatus.unconfirmed), shell: shell);

      await tester.tap(find.text('View in Activity'));
      await tester.pumpAndSettle();
      expect(swap.events, [const UnifiedSwapResetRequested()]);
      expect(shell.destination, SwapDestination.activity);
    });
  });

  group('back', () {
    testWidgets('and Escape both return to the form', (tester) async {
      await pump(tester, reviewing(SwapReviewStatus.ready));

      await tester.tap(back);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(swap.events, [
        const UnifiedSwapReviewClosed(),
        const UnifiedSwapReviewClosed(),
      ]);
    });

    for (final status in [
      SwapReviewStatus.starting,
      SwapReviewStatus.unconfirmed,
    ]) {
      testWidgets('is unavailable while the start is ${status.name}', (
        tester,
      ) async {
        await pump(tester, reviewing(status));

        await tester.tap(back);
        expect(swap.events, isEmpty);
        expect(
          tester.getSemantics(back),
          isSemantics(label: 'Back', isButton: true, isEnabled: false),
        );
      });
    }
  });

  group('the permission', () {
    SwapQuote approving({required bool reset}) => quoteOf(
      from: usdc,
      to: eth,
      sell: '1250',
      expected: '0.41',
      guaranteed: '0.4',
      approval: SwapApprovalRequirement(
        asset: usdc,
        exactAmount: d('1250'),
        resetsFirst: reset,
      ),
    );

    testWidgets('none needed says only the swap is signed', (tester) async {
      await pump(tester, reviewing(SwapReviewStatus.ready));

      expect(
        find.text(LocaleKeys.swapPermissionNoneTitle.tr()),
        findsOneWidget,
      );
      expect(find.text(LocaleKeys.swapPermissionNoneBody.tr()), findsOneWidget);
      expect(find.byKey(const Key('swap-start')), findsOneWidget);
    });

    testWidgets('an exact approval names the amount on the button', (
      tester,
    ) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready, quote: approving(reset: false)),
      );

      expect(
        find.text(LocaleKeys.swapPermissionExactBody.tr(args: ['1,250 USDC'])),
        findsOneWidget,
      );
      // The amount approved is on the button that approves it.
      expect(
        tester.widget<SwapButton>(find.byKey(const Key('swap-start'))).label,
        LocaleKeys.swapStartApprove.tr(args: ['1,250 USDC']),
      );
      expect(find.textContaining('1,250 USDC'), findsNWidgets(3));
    });

    testWidgets('a reset first says so, and the button continues with it', (
      tester,
    ) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready, quote: approving(reset: true)),
      );

      expect(
        find.text(LocaleKeys.swapPermissionResetTitle.tr()),
        findsOneWidget,
      );
      expect(
        find.text(LocaleKeys.swapPermissionResetBody.tr(args: ['1,250 USDC'])),
        findsOneWidget,
      );
      expect(find.text(LocaleKeys.swapStartReset.tr()), findsOneWidget);
    });
  });

  group('the routing provider\'s terms', () {
    testWidgets('the three documents are links in one swap style, each a '
        'full touch target, in both themes', (tester) async {
      for (final dark in [true, false]) {
        await common.pumpSwapUi(
          tester,
          SwapLegalConsentNotice(
            review: reviewing(SwapReviewStatus.ready).review!,
          ),
          dark: dark,
        );
        expect(find.byType(SwapLinkButton), findsNWidgets(3));
        final links = tester.widgetList<TextButton>(find.byType(TextButton));
        expect(links, hasLength(3));
        for (final link in links) {
          expect(link.onPressed, isNotNull);
          expect(
            link.style?.foregroundColor?.resolve({}),
            (dark ? SwapPalette.dark : SwapPalette.light).brandHover,
          );
        }
        final boxes = [
          for (final link in find.byType(SwapLinkButton).evaluate())
            tester.getRect(find.byWidget(link.widget)),
        ];
        for (final box in boxes) {
          expect(box.height, greaterThanOrEqualTo(48));
          expect(box.width, greaterThanOrEqualTo(48));
        }
        // One edge: the first label starts where the text above it would.
        expect(
          tester
              .getTopLeft(
                find.text(LocaleKeys.swapTermsLinkLabel.tr(args: ['LI.FI'])),
              )
              .dx,
          tester.getTopLeft(find.byType(SwapLegalConsentNotice)).dx,
        );
      }
    });

    testWidgets('are presented on a first routed swap, and the link opens '
        'them', (tester) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launched = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'launch') {
          launched.add((call.arguments as Map)['url'] as String);
        }
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready, termsRequired: true),
      );

      expect(find.text(LocaleKeys.swapLegalConsentNotice.tr()), findsOneWidget);
      expect(
        find.text(LocaleKeys.swapTermsLinkLabel.tr(args: ['LI.FI'])),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('swap-terms-link')));
      await tester.pumpAndSettle();
      expect(launched, isEmpty);
      expect(
        tester
            .widget<LegalDocumentView>(find.byType(LegalDocumentView))
            .document,
        LegalDocumentType.lifiTerms,
      );
    });

    testWidgets('legal text remains readable without an external browser', (
      tester,
    ) async {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready, termsRequired: true),
      );

      await tester.tap(find.byKey(const Key('swap-terms-link')));
      await tester.pumpAndSettle();

      expect(find.byType(LegalDocumentView), findsOneWidget);
      expect(find.text("Couldn't open the link"), findsNothing);
    });

    testWidgets('are not presented for an order-book swap', (tester) async {
      await pump(
        tester,
        reviewing(
          SwapReviewStatus.ready,
          termsRequired: true,
          quote: quoteOf(
            source: SwapLiquiditySource.atomic,
            routeKind: SwapRouteKind.direct,
            order: null,
          ),
        ),
      );

      expect(find.byKey(const Key('swap-terms-link')), findsNothing);
    });
  });

  group('the layout', () {
    testWidgets('in the side panel fills the panel', (tester) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready),
        inPanel: true,
        size: const Size(1024, 1200),
      );

      expect(tester.getTopLeft(back).dx, 18);
      expect(tester.getSize(find.byKey(const Key('swap-start'))).width, 992);
    });

    testWidgets('on its own keeps to the reading column', (tester) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready),
        size: const Size(1024, 1200),
      );

      expect(tester.getTopLeft(back).dx, (1024 - 576) / 2 + 16);
      expect(tester.getSize(find.byKey(const Key('swap-start'))).width, 544);
    });
  });

  testWidgets('the summary names each network, and the destination once', (
    tester,
  ) async {
    const mine = '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91';
    const other = '0x80A1c2d4E5f60718293a4B5c6D7e8F9012A342F0';
    final destination = find.byKey(const Key('swap-review-destination'));
    String label() => tester.widget<SwapLinkButton>(destination).label;

    final ready = reviewing(SwapReviewStatus.ready)
        .copyWith(clearPayAddress: true, clearReceiveAddress: true);
    await pump(tester, ready);
    expect(find.text('Ethereum'), findsNWidgets(2));
    expect(destination, findsNothing);

    // The source alone is not where anything lands; it stays under Route.
    final withPay = ready.copyWith(payAddress: mine);
    await emitSwapState(tester, swap, withPay);
    expect(find.text('Ethereum'), findsNWidgets(2));
    expect(destination, findsNothing);
    expect(find.textContaining('5520'), findsNothing);

    // One address pays and receives: said once, not under each amount.
    await emitSwapState(tester, swap, withPay.copyWith(receiveAddress: mine));
    expect(find.text('Ethereum'), findsNWidgets(2));
    expect(
      label(),
      'swapReviewSameWallet'.tr(args: ['0x5520\u2060…\u20607B91']),
    );
    expect(find.textContaining('5520').evaluate().length, lessThan(2));

    await emitSwapState(tester, swap, withPay.copyWith(receiveAddress: other));
    expect(label(), 'swapReviewToWallet'.tr(args: ['0x80A1\u2060…\u206042F0']));
    await tester.tap(destination);
    await tester.pumpAndSettle();
    expect(find.text(other), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('with no review open there is nothing to show', (tester) async {
    await pump(tester, swapPricedForm());
    expect(find.text('Review swap'), findsNothing);
  });
}
