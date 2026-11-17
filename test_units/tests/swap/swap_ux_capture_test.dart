// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/execution/swap_execution_view.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

import '../../support/legal_documents_fixture.dart';
import 'swap_entry_ui_fakes.dart' as entry;
import 'swap_surface_ui_fakes.dart' as surface;
import 'swap_test_fixtures.dart';

const _captureKey = Key('swap-ux-capture');

/// Optional artifacts come from the actual Flutter widgets, with deterministic
/// execution fixtures. These are never evidence of a live funded swap.
Future<void> _capture(WidgetTester tester, String name) async {
  final directory = Platform.environment['SWAP_CAPTURE_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$directory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Widget _frame(Widget child, {bool light = false, double textScale = 1}) =>
    Builder(
      builder: (context) => Theme(
        data: Theme.of(context)
            .copyWith(brightness: light ? Brightness.light : Brightness.dark),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: true,
            textScaler: TextScaler.linear(textScale),
          ),
          child: RepaintBoundary(
            key: _captureKey,
            child: Builder(
              builder: (context) => ColoredBox(
                color: SwapPalette.of(context).canvas,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  entry.setUpSwapUi();
  setUpAll(() async {
    final loader = FontLoader('MaterialIcons');
    loader.addFont(
      Future.value(
        ByteData.sublistView(
          File('build/unit_test_assets/fonts/MaterialIcons-Regular.otf')
              .readAsBytesSync(),
        ),
      ),
    );
    await loader.load();
  });

  final ready = entry.swapPricedForm().copyWith(
    amountMode: SwapAmountMode.fiat,
    inputText: '3000',
    converted: (amount: d('1'), asset: eth, text: '3000'),
    payAddress: '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91',
    receiveAddress: '0x5520D7F51C8e3108FA2d9C6220bF4Aa8F9c17B91',
  );
  final quoted = entry.quoteWith(
    quoteOf(),
    fromAddress: ready.payAddress,
    toAddress: ready.receiveAddress,
  );
  final review = ready.copyWith(
    view: UnifiedSwapView.review,
    review: SwapReview(
      quote: quoted,
      status: SwapReviewStatus.ready,
      legalSnapshot: legalFixtureSnapshot(),
    ),
  );
  const failure = SwapQuoteFailure(
    source: SwapLiquiditySource.routed,
    kind: SwapQuoteFailureKind.serviceError,
    cause: SwapQuoteFailureCause.engine,
  );
  final states = <String, UnifiedSwapState>{
    'ready': ready,
    'slow': ready.copyWith(
      clearQuotes: true,
      clearSelectedId: true,
      evaluation: SwapEvaluationStatus.checking,
      quotesPending: true,
    ),
    'failed': ready.copyWith(
      clearQuotes: true,
      clearSelectedId: true,
      evaluation: SwapEvaluationStatus.failed,
      failure: failure,
      failures: const [failure],
    ),
    'review': review,
    'changed': review.copyWith(
      review: review.review!.copyWith(
        status: SwapReviewStatus.materialUpdate,
        previous: quoted,
        quote: entry.quoteWith(
          quoteOf(expected: '2950', guaranteed: '2935'),
          fromAddress: ready.payAddress,
          toAddress: ready.receiveAddress,
        ),
      ),
    ),
  };

  for (final layout in [
    (name: 'phone-dark', size: const Size(390, 844), light: false),
    (name: 'desktop-light', size: const Size(1280, 900), light: true),
  ]) {
    for (final state in states.entries) {
      testWidgets('renders ${layout.name} ${state.key} without layout errors', (
        tester,
      ) async {
        final bloc = entry.RecordingSwapBloc()..emit(state.value);
        final services = entry.FakeSwapServices();
        addTearDown(bloc.close);
        await entry.pumpSwapUi(
          tester,
          _frame(const SwapPage(), light: layout.light),
          bloc: bloc,
          services: services,
          size: layout.size,
          settle: false,
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await _capture(tester, '${layout.name}-${state.key}');
      });
    }

    for (final complete in [false, true]) {
      final name = complete ? 'receipt' : 'receiving';
      testWidgets('renders ${layout.name} $name from execution evidence', (
        tester,
      ) async {
        surface.useFreshRoutingState();
        final executor = FakeExecutor(SwapLiquiditySource.routed);
        final registry = testSwapRegistry(
          executors: [executor],
          inFlight: () async => const [],
        );
        final snapshot = snapshotOf(
          stage: SwapProgressStage.awaitingDelivery,
          sourceTxHash: '0xsource-transaction',
          outcome: complete ? completed() : null,
        );
        executor.resumable[snapshot.id] = FakeHandle(snapshot);
        final services = surface.SurfaceServices(registry);
        final bloc = surface.RecordingSwapBloc(registry);
        final shell = SwapShellController();
        addTearDown(() async {
          await bloc.close();
          await services.dispose();
          await registry.dispose();
          shell.dispose();
        });
        await surface.pumpSurface(
          tester,
          _frame(
            SwapExecutionView(
              id: snapshot.id,
              context: SwapExecutionContext.flow,
            ),
            light: layout.light,
          ),
          services: services,
          swap: bloc,
          shell: shell,
          size: layout.size,
        );
        expect(tester.takeException(), isNull);
        await _capture(tester, '${layout.name}-$name');
      });
    }
  }

  testWidgets('review return retains the exact input element and draft', (
    tester,
  ) async {
    final bloc = entry.RecordingSwapBloc()..emit(ready);
    addTearDown(bloc.close);
    await entry.pumpSwapUi(
      tester,
      _frame(const SwapPage()),
      bloc: bloc,
      services: entry.FakeSwapServices(),
      size: const Size(390, 844),
    );
    final input = tester.element(find.byType(EditableText));
    final controller = tester.widget<EditableText>(find.byType(EditableText));
    await entry.emitSwapState(tester, bloc, review);
    await entry.emitSwapState(tester, bloc, ready);
    expect(tester.element(find.byType(EditableText)), same(input));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller,
      same(controller.controller),
    );
    expect(controller.controller.text, '3000');
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone keyboard keeps both assets and the estimate visible', (
    tester,
  ) async {
    final bloc = entry.RecordingSwapBloc()..emit(ready);
    addTearDown(bloc.close);
    await entry.pumpSwapUi(
      tester,
      _frame(const SwapPage()),
      bloc: bloc,
      services: entry.FakeSwapServices(),
      size: const Size(390, 844),
    );
    final field = find.byKey(const Key('swap-amount'));
    await tester.showKeyboard(field);
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final action = find.byKey(const Key('swap-primary-action'));
    expect(action.hitTestable(), findsOneWidget);
    expect(find.text('ETH').hitTestable(), findsOneWidget);
    expect(find.text('USDC').hitTestable(), findsOneWidget);
    expect(find.text('3,000').hitTestable(), findsOneWidget);
    expect(tester.getBottomLeft(action).dy, lessThanOrEqualTo(508));
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'phone-dark-keyboard');
  });

  testWidgets('large text keeps review consent reachable by scrolling', (
    tester,
  ) async {
    final bloc = entry.RecordingSwapBloc()..emit(review);
    addTearDown(bloc.close);
    await entry.pumpSwapUi(
      tester,
      _frame(const SwapPage(), light: true, textScale: 2),
      bloc: bloc,
      services: entry.FakeSwapServices(),
      size: const Size(390, 844),
      textScale: 2,
    );
    expect(find.text('Confirm swap').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capture(tester, 'phone-light-large-review');
  });
}
