// The analyzer does not treat test_units as tests, so Bloc.emit's
// @visibleForTesting reads as a violation here.
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/review/swap_review_view.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import 'swap_entry_ui_fakes.dart';
import 'swap_test_fixtures.dart';

/// Covers the review's frame: the status badge, the one action each status
/// allows, the ways back, the permission asked for and the routing
/// provider's terms.
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
    final busy = switch (state.review?.status) {
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

  group('the status badge', () {
    for (final (status, badge) in [
      (SwapReviewStatus.ready, 'Ready to review'),
      (SwapReviewStatus.revalidating, 'Checking latest quote'),
      (SwapReviewStatus.revalidationFailed, "Couldn't refresh quote"),
      (SwapReviewStatus.expired, 'Quote expired'),
      (SwapReviewStatus.materialUpdate, 'Quote updated'),
      (SwapReviewStatus.starting, 'Starting'),
    ]) {
      testWidgets('reads "$badge" while ${status.name}', (tester) async {
        await pump(tester, reviewing(status));
        expect(badges(tester), [badge]);
      });
    }

    for (final status in [
      SwapReviewStatus.rejected,
      SwapReviewStatus.unconfirmed,
    ]) {
      testWidgets('is left out once ${status.name}, for the callout to say', (
        tester,
      ) async {
        await pump(tester, reviewing(status));
        expect(badges(tester), isEmpty);
      });
    }
  });

  group('the footer', () {
    for (final (status, label) in [
      (SwapReviewStatus.ready, 'Start swap'),
      (SwapReviewStatus.materialUpdate, 'Accept updated quote'),
      (SwapReviewStatus.expired, 'Refresh quote'),
      (SwapReviewStatus.revalidationFailed, 'Try again'),
      (SwapReviewStatus.rejected, 'Try again'),
    ]) {
      // The bloc decides: re-price in place, or re-price and start.
      testWidgets('offers "$label" while ${status.name}, asking the bloc to '
          'go on', (tester) async {
        await pump(tester, reviewing(status));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        expect(swap.events, [const UnifiedSwapStartRequested()]);
      });
    }

    for (final (status, label) in [
      (SwapReviewStatus.revalidating, 'Checking…'),
      (SwapReviewStatus.starting, 'Start swap'),
    ]) {
      testWidgets('waits on "$label" while ${status.name}', (tester) async {
        await pump(tester, reviewing(status));

        expect(swapButtonEnabled(tester, find.text(label)), isFalse);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
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

      expect(find.text('No token approval needed'), findsOneWidget);
      expect(
        find.text("You'll only sign the swap request when you start."),
        findsOneWidget,
      );
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
        find.text('Approve 1,250 USDC for this swap only — never unlimited.'),
        findsOneWidget,
      );
      expect(find.text('Approve exactly 1,250 USDC & start'), findsOneWidget);
    });

    testWidgets('a reset first says so, and the button continues with it', (
      tester,
    ) async {
      await pump(
        tester,
        reviewing(SwapReviewStatus.ready, quote: approving(reset: true)),
      );

      expect(find.text('Reset, then exact approval'), findsOneWidget);
      expect(
        find.text(
          'Reset the current permission, then approve 1,250 USDC for this '
          'swap only — never unlimited.',
        ),
        findsOneWidget,
      );
      expect(find.text('Continue with reset'), findsOneWidget);
    });
  });

  group('the routing provider\'s terms', () {
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

      expect(
        find.textContaining(
          'By starting, you agree to the',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text('LI.FI Terms of Service'), findsOneWidget);

      await tester.tap(find.byKey(const Key('swap-terms-link')));
      await tester.pumpAndSettle();
      expect(launched, [SwapTermsRepository.termsUrl]);
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

  testWidgets('the summary shows each address as the wallet reports it', (
    tester,
  ) async {
    final ready = reviewing(SwapReviewStatus.ready);
    await pump(tester, ready);
    expect(find.text('Ethereum'), findsNWidgets(2));

    final withPay = ready.copyWith(
      payAddress: '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91',
    );
    await emitSwapState(tester, swap, withPay);
    expect(find.text('Ethereum · 0x5520…7B91'), findsOneWidget);
    expect(find.text('Ethereum'), findsOneWidget);

    await emitSwapState(
      tester,
      swap,
      withPay.copyWith(
        receiveAddress: '0x80A1c2d4E5f60718293a4B5c6D7e8F9012A342F0',
      ),
    );
    expect(find.text('Ethereum · 0x80A1…42F0'), findsOneWidget);
  });

  testWidgets('with no review open there is nothing to show', (tester) async {
    await pump(tester, swapPricedForm());
    expect(find.text('Review swap'), findsNothing);
  });
}
