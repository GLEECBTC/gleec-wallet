import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_preferences.dart';
import 'package:web_dex/shared/swap/swap_pricing.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

import 'swap_test_fixtures.dart';

/// Covers the form beside an open review on a wide screen while the swap it
/// reviews is starting. The form stays editable there, and each edit sends
/// what `SwapEntryView._edit` sends: a close of the review, then the edit.
void main() {
  late _GatedExecutor executor;
  late SwapExecutionRegistry registry;
  final clock = DateTime(2026, 9, 24, 12);

  setUp(() {
    executor = _GatedExecutor();
    registry = SwapExecutionRegistry(
      executors: [executor],
      inFlight: () async => const [],
    );
  });

  tearDown(() => registry.dispose());

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await pumpEventQueue(times: 30);
    }
  }

  /// A bloc with ETH for USDC priced, reviewed, and asked to start.
  Future<UnifiedSwapBloc> starting() async {
    final storage = MemoryStorage();
    final bloc =
        UnifiedSwapBloc(
            repository: UnifiedSwapRepository(
              sources: [
                FakeQuoteSource(
                  SwapLiquiditySource.routed,
                  respond: (request) => [
                    SwapQuoteAvailable(
                      quoteOf(
                        from: request.from,
                        to: request.to,
                        quotedAt: clock,
                      ),
                    ),
                  ],
                ),
              ],
              pricing: SwapPricingService(FakePriceSource({eth: d('3000')})),
            ),
            registry: registry,
            terms: SwapTermsRepository(
              walletKey: () async => 'w',
              storage: storage,
            ),
            preferences: SwapPreferences(
              walletKey: () async => 'w',
              storage: storage,
            ),
            spendableBalance: (_) async => d('2'),
            addressOf: (_) async => '0xaddress',
            resolveAsset: (ticker) => {eth.id: eth, usdc.id: usdc}[ticker],
            now: () => clock,
            debounce: Duration.zero,
            refreshInterval: const Duration(hours: 1),
          )
          ..add(const UnifiedSwapStarted())
          ..add(
            const UnifiedSwapIntentApplied(
              pay: 'ETH',
              receive: 'USDC-ERC20',
              amount: '1',
            ),
          );
    await settle();
    bloc.add(const UnifiedSwapReviewOpened());
    await settle();
    bloc.add(const UnifiedSwapStartRequested());
    await settle();
    expect(bloc.state.review!.status, SwapReviewStatus.starting);
    return bloc;
  }

  test(
    'an unconfirmed start stays on screen after the form is edited',
    () async {
      final bloc = await starting();

      // Switching sides from the form beside the panel.
      bloc
        ..add(const UnifiedSwapReviewClosed())
        ..add(const UnifiedSwapSidesSwitched());
      await settle();
      executor.gate.completeError(TimeoutException('lost'));
      await settle();

      // The swap may be running: the review must still say so, and must not
      // let the form start another.
      expect(bloc.state.view, UnifiedSwapView.review);
      expect(bloc.state.review?.status, SwapReviewStatus.unconfirmed);
      await bloc.close();
    },
  );

  test('a start in progress ignores a close on its own', () async {
    final bloc = await starting();

    bloc.add(const UnifiedSwapReviewClosed());
    await settle();
    expect(bloc.state.view, UnifiedSwapView.review);

    executor.gate.completeError(TimeoutException('lost'));
    await settle();
    expect(bloc.state.review?.status, SwapReviewStatus.unconfirmed);
    await bloc.close();
  });
}

/// An executor whose start waits until the test settles it.
class _GatedExecutor implements SwapExecutor {
  final Completer<void> gate = Completer<void>();

  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    await gate.future;
    throw StateError('unreachable');
  }

  @override
  Future<SwapExecutionHandle?> resume(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
