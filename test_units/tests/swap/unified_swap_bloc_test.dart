import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/shared/swap/swap_execution.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/unified_swap_repository.dart';

/// Covers the rules that stand between a user and a trade they did not agree
/// to.
///
/// The two that matter most are the pre-start re-price and the stale-answer
/// guard. Both are invisible in the type signatures and both fail silently if
/// broken — the swap simply executes against the wrong number.
void main() {
  AssetId assetOf(String id) => AssetId(
    id: id,
    name: id,
    symbol: AssetSymbol(assetConfigId: id),
    chainId: AssetChainId(chainId: 1),
    derivationPath: null,
    subClass: CoinSubClass.erc20,
  );

  final usdt = assetOf('USDT-PLG20');
  final usdc = assetOf('USDC-ERC20');

  SwapQuote quoteOf({
    required String guaranteed,
    SwapLiquiditySource source = SwapLiquiditySource.routed,
    String? expected,
    Object? payload,
  }) => SwapQuote(
    source: source,
    from: usdt,
    to: usdc,
    sellAmount: Decimal.parse('100'),
    expectedReceive: Decimal.parse(expected ?? guaranteed),
    guaranteedReceive: Decimal.parse(guaranteed),
    costs: const [],
    quotedAt: DateTime(2026),
    hasUndisclosedCosts: false,
    payload: payload,
  );

  UnifiedSwapBloc blocWith(
    _ProgrammableSource source, {
    Decimal? balance,
    _FakeExecutor? executor,
  }) => UnifiedSwapBloc(
    repository: UnifiedSwapRepository(sources: [source]),
    executors: [executor ?? _FakeExecutor()],
    spendableBalance: (_) async => balance,
  );

  /// Waits for a state matching [test], failing fast rather than hanging.
  ///
  /// A bare `firstWhere` on a bloc stream wedges the whole runner when the
  /// expected state never arrives.
  Future<UnifiedSwapState> waitFor(
    UnifiedSwapBloc bloc,
    bool Function(UnifiedSwapState) test,
  ) {
    if (test(bloc.state)) return Future.value(bloc.state);
    return bloc.stream
        .firstWhere(test)
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () => fail('no matching state arrived'),
        );
  }

  Future<void> fillForm(UnifiedSwapBloc bloc, {String amount = '100'}) async {
    bloc
      ..add(UnifiedSwapSellAssetChanged(usdt))
      ..add(UnifiedSwapReceiveAssetChanged(usdc))
      ..add(UnifiedSwapAmountChanged(amount));
    await waitFor(bloc, (s) => s.amountText == amount && s.sellAsset != null);
  }

  group('form validation', () {
    test('rejects an amount above the spendable balance', () async {
      final bloc = blocWith(
        _ProgrammableSource(),
        balance: Decimal.parse('50'),
      );
      addTearDown(bloc.close);

      await fillForm(bloc, amount: '100');
      final state = await waitFor(bloc, (s) => s.formError != null);

      expect(state.formError, UnifiedSwapFormError.amountExceedsBalance);
      expect(state.canRequestQuote, isFalse);
    });

    test('rejects a malformed amount without crashing', () async {
      final bloc = blocWith(_ProgrammableSource());
      addTearDown(bloc.close);

      await fillForm(bloc, amount: '12..3');
      final state = await waitFor(bloc, (s) => s.formError != null);

      expect(state.formError, UnifiedSwapFormError.amountMalformed);
    });

    test('rejects the same asset on both sides', () async {
      final bloc = blocWith(_ProgrammableSource());
      addTearDown(bloc.close);

      bloc
        ..add(UnifiedSwapSellAssetChanged(usdt))
        ..add(UnifiedSwapReceiveAssetChanged(usdt));

      final state = await waitFor(
        bloc,
        (s) => s.formError == UnifiedSwapFormError.sameAsset,
      );
      expect(state.canRequestQuote, isFalse);
    });

    test('clears the amount when the sides are reversed', () async {
      final bloc = blocWith(_ProgrammableSource());
      addTearDown(bloc.close);

      await fillForm(bloc);
      bloc.add(const UnifiedSwapSidesReversed());

      final state = await waitFor(bloc, (s) => s.sellAsset == usdc);
      // The amount was denominated in the old sell asset. Keeping it would
      // re-denominate the trade without telling anyone.
      expect(state.amountText, isEmpty);
      expect(state.receiveAsset, usdt);
    });
  });

  group('quoting', () {
    test(
      'discards a slow answer for a form the user has moved on from',
      () async {
        final source = _ProgrammableSource()
          ..gate = Completer<void>()
          ..priced = quoteOf(guaranteed: '99');
        final bloc = blocWith(source);
        addTearDown(bloc.close);

        await fillForm(bloc);
        bloc.add(const UnifiedSwapQuoteRequested());
        await waitFor(
          bloc,
          (s) => s.quoteStatus == UnifiedSwapQuoteStatus.loading,
        );

        // The user keeps typing while the first lookup is still out.
        bloc.add(const UnifiedSwapAmountChanged('250'));
        await waitFor(bloc, (s) => s.amountText == '250');

        source.gate!.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // The stale price must not land: it was quoted for 100, not 250.
        expect(bloc.state.selectedQuote, isNull);
        expect(bloc.state.quoteStatus, UnifiedSwapQuoteStatus.idle);
      },
    );

    test('separates an unsupported pair from a transient failure', () async {
      final source = _ProgrammableSource()
        ..rejection = SwapQuoteUnavailableReason.pairUnsupported;
      final bloc = blocWith(source);
      addTearDown(bloc.close);

      await fillForm(bloc);
      bloc.add(const UnifiedSwapQuoteRequested());

      final state = await waitFor(
        bloc,
        (s) =>
            s.quoteStatus != UnifiedSwapQuoteStatus.loading &&
            s.quoteStatus != UnifiedSwapQuoteStatus.idle,
      );
      // Retrying will never help, so the UI must not offer it.
      expect(state.quoteStatus, UnifiedSwapQuoteStatus.unsupported);
    });
  });

  group('pre-start re-price', () {
    test('stops for consent when the guaranteed amount drops', () async {
      final source = _ProgrammableSource()
        ..priced = quoteOf(guaranteed: '99', payload: _offer());
      final bloc = blocWith(source);
      addTearDown(bloc.close);

      await fillForm(bloc);
      bloc.add(const UnifiedSwapQuoteRequested());
      await waitFor(bloc, (s) => s.canReview);
      bloc.add(const UnifiedSwapReviewRequested());
      await waitFor(bloc, (s) => s.step == UnifiedSwapStep.confirm);

      // The price moves against the user between review and start.
      source.priced = quoteOf(guaranteed: '95', payload: _offer());
      bloc.add(const UnifiedSwapStartRequested());

      final state = await waitFor(bloc, (s) => s.repricedQuote != null);

      expect(state.step, UnifiedSwapStep.confirm);
      expect(state.repricedQuote!.guaranteedReceive, Decimal.parse('95'));
      expect(
        state.canStart,
        isFalse,
        reason: 'the user has not agreed to the new number yet',
      );
      expect(state.activeSwapUuid, isNull);
    });

    test('proceeds when the re-price is not worse', () async {
      final manager = _FakeExecutor();
      final source = _ProgrammableSource()
        ..priced = quoteOf(guaranteed: '99', payload: _offer());
      final bloc = blocWith(source, executor: manager);
      addTearDown(bloc.close);

      await fillForm(bloc);
      bloc.add(const UnifiedSwapQuoteRequested());
      await waitFor(bloc, (s) => s.canReview);
      bloc.add(const UnifiedSwapReviewRequested());
      await waitFor(bloc, (s) => s.step == UnifiedSwapStep.confirm);

      source.priced = quoteOf(guaranteed: '101', payload: _offer());
      bloc.add(const UnifiedSwapStartRequested());

      final state = await waitFor(bloc, (s) => s.activeSwapUuid != null);
      expect(state.step, UnifiedSwapStep.inProgress);
      expect(manager.startCount, 1);
    });

    test('accepting a re-price executes against the new number', () async {
      final manager = _FakeExecutor();
      final source = _ProgrammableSource()
        ..priced = quoteOf(guaranteed: '99', payload: _offer());
      final bloc = blocWith(source, executor: manager);
      addTearDown(bloc.close);

      await fillForm(bloc);
      bloc.add(const UnifiedSwapQuoteRequested());
      await waitFor(bloc, (s) => s.canReview);
      bloc.add(const UnifiedSwapReviewRequested());
      await waitFor(bloc, (s) => s.step == UnifiedSwapStep.confirm);

      source.priced = quoteOf(guaranteed: '95', payload: _offer());
      bloc.add(const UnifiedSwapStartRequested());
      await waitFor(bloc, (s) => s.repricedQuote != null);

      bloc.add(const UnifiedSwapRepriceAccepted());
      final state = await waitFor(bloc, (s) => s.activeSwapUuid != null);

      expect(state.selectedQuote!.guaranteedReceive, Decimal.parse('95'));
      expect(manager.startCount, 1);
    });

    test(
      'rejecting a re-price sends the user back without executing',
      () async {
        final manager = _FakeExecutor();
        final source = _ProgrammableSource()
          ..priced = quoteOf(guaranteed: '99', payload: _offer());
        final bloc = blocWith(source, executor: manager);
        addTearDown(bloc.close);

        await fillForm(bloc);
        bloc.add(const UnifiedSwapQuoteRequested());
        await waitFor(bloc, (s) => s.canReview);
        bloc.add(const UnifiedSwapReviewRequested());
        await waitFor(bloc, (s) => s.step == UnifiedSwapStep.confirm);

        source.priced = quoteOf(guaranteed: '95', payload: _offer());
        bloc.add(const UnifiedSwapStartRequested());
        await waitFor(bloc, (s) => s.repricedQuote != null);

        bloc.add(const UnifiedSwapRepriceRejected());
        final state = await waitFor(
          bloc,
          (s) => s.step == UnifiedSwapStep.fill,
        );

        expect(state.repricedQuote, isNull);
        expect(manager.startCount, 0);
      },
    );
  });

  group('execution', () {
    test('an atomic offer says so instead of silently doing nothing', () async {
      // The button spends money. Pressing it and having nothing happen is the
      // worst available outcome, so the unimplemented path is explicit.
      // Only a routed executor is registered, so an atomic quote has nothing
      // to execute it. The user must be told, not left with a dead button.
      final manager = _FakeExecutor();
      final source = _ProgrammableSource()
        ..priced = quoteOf(
          guaranteed: '99',
          source: SwapLiquiditySource.atomic,
        );
      final bloc = blocWith(source, executor: manager);
      addTearDown(bloc.close);

      await fillForm(bloc);
      bloc.add(const UnifiedSwapQuoteRequested());
      await waitFor(bloc, (s) => s.canReview);
      bloc.add(const UnifiedSwapReviewRequested());
      await waitFor(bloc, (s) => s.step == UnifiedSwapStep.confirm);
      bloc.add(const UnifiedSwapStartRequested());

      final state = await waitFor(bloc, (s) => s.startError != null);
      expect(state.step, UnifiedSwapStep.confirm);
      expect(manager.startCount, 0);
    });

    test('progress drives the step, and a refund is not a success', () async {
      final manager = _FakeExecutor();
      final source = _ProgrammableSource()
        ..priced = quoteOf(guaranteed: '99', payload: _offer());
      final bloc = blocWith(source, executor: manager);
      addTearDown(bloc.close);

      await fillForm(bloc);
      bloc.add(const UnifiedSwapQuoteRequested());
      await waitFor(bloc, (s) => s.canReview);
      bloc.add(const UnifiedSwapReviewRequested());
      await waitFor(bloc, (s) => s.step == UnifiedSwapStep.confirm);
      bloc.add(const UnifiedSwapStartRequested());
      await waitFor(bloc, (s) => s.step == UnifiedSwapStep.inProgress);
      // The bloc subscribes just after emitting the in-progress state, and the
      // fake's stream is broadcast, so an event pushed immediately would be
      // dropped for want of a listener.
      await Future<void>.delayed(const Duration(milliseconds: 20));

      manager.emit(
        const UnifiedSwapProgress(
          id: 'u',
          source: SwapLiquiditySource.routed,
          phase: SwapPhase.finished,
          canCancel: false,
        ),
      );

      final state = await waitFor(
        bloc,
        (s) => s.step == UnifiedSwapStep.complete,
      );
      // Reaching the complete step says the swap stopped, not that it worked.
      expect(state.progress!.isSuccess, isFalse);
    });
  });
}

RoutedSwapOffer _offer() => RoutedSwapOffer(
  from: AssetId(
    id: 'USDT-PLG20',
    name: 'USDT',
    symbol: AssetSymbol(assetConfigId: 'USDT-PLG20'),
    chainId: AssetChainId(chainId: 137),
    derivationPath: null,
    subClass: CoinSubClass.erc20,
  ),
  to: AssetId(
    id: 'USDC-ERC20',
    name: 'USDC',
    symbol: AssetSymbol(assetConfigId: 'USDC-ERC20'),
    chainId: AssetChainId(chainId: 1),
    derivationPath: null,
    subClass: CoinSubClass.erc20,
  ),
  sellAmount: Decimal.parse('100'),
  expectedReceive: Decimal.parse('100'),
  guaranteedReceive: Decimal.parse('99'),
  toolName: 'Test Bridge',
  isCrossChain: true,
  costs: const [],
  quotedAt: DateTime(2026),
  mayRequireApproval: true,
  provider: 'lifi',
);

/// A source whose answer the test controls, including its timing.
class _ProgrammableSource implements SwapQuoteSource {
  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  SwapQuote? priced;
  SwapQuoteUnavailableReason? rejection;

  /// When set, the next lookup blocks until completed.
  Completer<void>? gate;

  @override
  Future<Set<AssetId>> tradableAssets() async => const {};

  @override
  Future<SwapQuoteResult> quote({
    required AssetId from,
    required AssetId to,
    required Decimal amount,
  }) async {
    if (gate != null) await gate!.future;
    final rejected = rejection;
    if (rejected != null) {
      return SwapQuoteRejected(
        SwapQuoteUnavailable(source: source, reason: rejected),
      );
    }
    final offer = priced;
    if (offer == null) {
      return SwapQuoteRejected(
        SwapQuoteUnavailable(
          source: source,
          reason: SwapQuoteUnavailableReason.noLiquidity,
        ),
      );
    }
    return SwapQuoteAvailable(offer);
  }
}

/// A routed manager that records starts and lets the test push progress.
class _FakeExecutor implements SwapExecutor {
  @override
  SwapLiquiditySource get source => SwapLiquiditySource.routed;

  final _controller = StreamController<UnifiedSwapProgress>.broadcast();
  int startCount = 0;

  void emit(UnifiedSwapProgress progress) => _controller.add(progress);

  @override
  Future<SwapExecutionHandle> start(SwapQuote quote) async {
    startCount++;
    return _FakeHandle(_controller.stream);
  }
}

class _FakeHandle implements SwapExecutionHandle {
  _FakeHandle(this.progress);

  @override
  final Stream<UnifiedSwapProgress> progress;

  @override
  String get id => 'fake-uuid';

  @override
  Future<void> cancel() async {}
}
