import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_quote_failure.dart';

import 'swap_test_fixtures.dart';

/// Covers the value types swaps are described with: what makes two of them
/// equal, and the questions a finished swap answers about itself.
void main() {
  group('a failure', () {
    SwapExecutionFailure full() => SwapExecutionFailure(
      reason: SwapFailureReason.insufficientBalance,
      nextStep: SwapNextStep.fixAndRetry,
      retryable: true,
      shortfallAsset: eth,
      shortfallTicker: 'ETH',
      shortfallAvailable: d('0.1'),
      shortfallRequired: d('0.2'),
      freshQuote: quoteOf(),
      noRouteReasons: const ['thin'],
      detail: 'InsufficientBalance: short',
    );

    test('equals another with the same facts', () {
      expect(full(), full());
      expect(full().hashCode, full().hashCode);
    });

    test('differs when any fact differs', () {
      const base = SwapExecutionFailure(
        reason: SwapFailureReason.internal,
        nextStep: SwapNextStep.retry,
      );
      final variants = [
        const SwapExecutionFailure(
          reason: SwapFailureReason.unknown,
          nextStep: SwapNextStep.retry,
        ),
        const SwapExecutionFailure(
          reason: SwapFailureReason.internal,
          nextStep: SwapNextStep.none,
        ),
        const SwapExecutionFailure(
          reason: SwapFailureReason.internal,
          nextStep: SwapNextStep.retry,
          retryable: true,
        ),
        SwapExecutionFailure(
          reason: SwapFailureReason.internal,
          nextStep: SwapNextStep.retry,
          shortfallAsset: eth,
        ),
        const SwapExecutionFailure(
          reason: SwapFailureReason.internal,
          nextStep: SwapNextStep.retry,
          shortfallTicker: 'ETH',
        ),
        SwapExecutionFailure(
          reason: SwapFailureReason.internal,
          nextStep: SwapNextStep.retry,
          shortfallAvailable: d('1'),
        ),
        SwapExecutionFailure(
          reason: SwapFailureReason.internal,
          nextStep: SwapNextStep.retry,
          shortfallRequired: d('1'),
        ),
        SwapExecutionFailure(
          reason: SwapFailureReason.internal,
          nextStep: SwapNextStep.retry,
          freshQuote: quoteOf(),
        ),
        const SwapExecutionFailure(
          reason: SwapFailureReason.internal,
          nextStep: SwapNextStep.retry,
          noRouteReasons: ['x'],
        ),
        const SwapExecutionFailure(
          reason: SwapFailureReason.internal,
          nextStep: SwapNextStep.retry,
          detail: 'x',
        ),
      ];
      for (final variant in variants) {
        expect(variant, isNot(base));
      }
      expect(base.retryable, isFalse);
      expect(base.noRouteReasons, isEmpty);
    });
  });

  group('an outcome', () {
    test('is a success only when completed', () {
      for (final kind in SwapOutcomeKind.values) {
        expect(
          SwapExecutionOutcome(kind: kind).isSuccess,
          kind == SwapOutcomeKind.completed,
          reason: kind.name,
        );
      }
    });

    test('equals another with the same delivery and failure', () {
      expect(completed(), completed());
      expect(completed(), isNot(completed(amount: '1')));
      expect(
        const SwapExecutionOutcome(
          kind: SwapOutcomeKind.partialOtherToken,
          receivedSymbol: 'axlUSDC',
        ),
        isNot(
          const SwapExecutionOutcome(kind: SwapOutcomeKind.partialOtherToken),
        ),
      );
      expect(
        failed(SwapFailureReason.internal),
        isNot(failed(SwapFailureReason.unknown)),
      );
    });
  });

  group('a finished swap', () {
    SwapExecutionSnapshot ended(
      SwapOutcomeKind kind, {
      SwapFundsMovement movement = SwapFundsMovement.none,
      bool approvalRemains = false,
    }) => snapshotOf(
      outcome: SwapExecutionOutcome(kind: kind),
      fundsMovement: movement,
      approvalRemains: approvalRemains,
    );

    test('needs attention when it did not deliver what was asked', () {
      expect(ended(SwapOutcomeKind.partialBelowMinimum).needsAttention, isTrue);
      expect(ended(SwapOutcomeKind.partialOtherToken).needsAttention, isTrue);
      expect(ended(SwapOutcomeKind.completed).needsAttention, isFalse);
      expect(ended(SwapOutcomeKind.refunded).needsAttention, isFalse);
      expect(ended(SwapOutcomeKind.noMatch).needsAttention, isFalse);
    });

    test('a cancellation needs attention only for a permission left', () {
      expect(ended(SwapOutcomeKind.cancelled).needsAttention, isFalse);
      expect(
        ended(SwapOutcomeKind.cancelled, approvalRemains: true).needsAttention,
        isTrue,
      );
    });

    test('a failure needs attention once anything may have moved', () {
      for (final movement in SwapFundsMovement.values) {
        expect(
          ended(SwapOutcomeKind.failed, movement: movement).needsAttention,
          movement != SwapFundsMovement.none,
          reason: movement.name,
        );
      }
      expect(
        ended(SwapOutcomeKind.failed, approvalRemains: true).needsAttention,
        isTrue,
      );
    });

    test('a running swap needs attention only when the user must act', () {
      for (final stage in SwapProgressStage.values) {
        expect(
          snapshotOf(stage: stage).needsAttention,
          stage == SwapProgressStage.actionRequired,
          reason: stage.name,
        );
        expect(snapshotOf(stage: stage).isTerminal, isFalse);
        expect(snapshotOf(stage: stage).isSuccess, isFalse);
      }
    });
  });

  group('evidence', () {
    test('gas records compare by every field', () {
      final gas = SwapGasSpent(
        ticker: 'ETH',
        asset: eth,
        amount: d('0.01'),
        txHash: '0x1',
      );
      expect(
        gas,
        SwapGasSpent(
          ticker: 'ETH',
          asset: eth,
          amount: d('0.01'),
          txHash: '0x1',
        ),
      );
      expect(gas, isNot(SwapGasSpent(ticker: 'ETH', amount: d('0.01'))));
    });

    test('two records of the same swap compare by content', () {
      expect(
        const SwapEvidence(executionId: 'x', sourceTxHash: '0x1'),
        const SwapEvidence(executionId: 'x', sourceTxHash: '0x1'),
      );
      expect(
        const SwapEvidence(executionId: 'x', rawState: 'Finished'),
        isNot(const SwapEvidence(executionId: 'x')),
      );
    });
  });

  group('a quote failure', () {
    test('is transient only for kinds a later retry may cure', () {
      const transient = {
        SwapQuoteFailureKind.rateLimited,
        SwapQuoteFailureKind.serviceError,
        SwapQuoteFailureKind.timeout,
        SwapQuoteFailureKind.unknown,
      };
      for (final kind in SwapQuoteFailureKind.values) {
        expect(
          SwapQuoteFailure(
            source: SwapLiquiditySource.routed,
            kind: kind,
          ).isTransient,
          transient.contains(kind),
          reason: kind.name,
        );
      }
    });

    test('is permanent only for pairs this source can never price', () {
      const permanent = {
        SwapQuoteFailureKind.pairUnsupported,
        SwapQuoteFailureKind.notConfigured,
        SwapQuoteFailureKind.tradingBlocked,
      };
      for (final kind in SwapQuoteFailureKind.values) {
        expect(
          SwapQuoteFailure(
            source: SwapLiquiditySource.atomic,
            kind: kind,
          ).isPermanent,
          permanent.contains(kind),
          reason: kind.name,
        );
      }
    });

    test('equals another with the same facts, and differs on any one', () {
      SwapQuoteFailure of({
        SwapLiquiditySource source = SwapLiquiditySource.routed,
        SwapQuoteFailureKind kind = SwapQuoteFailureKind.noRoute,
        String? detail,
        DateTime? retryAt,
        List<String> reasons = const [],
        String? requestId,
      }) => SwapQuoteFailure(
        source: source,
        kind: kind,
        asset: eth,
        minimum: d('1'),
        maximum: d('9'),
        reasons: reasons,
        providerRequestId: requestId,
        detail: detail,
        retryAt: retryAt,
      );

      expect(of(), of());
      expect(of(source: SwapLiquiditySource.atomic), isNot(of()));
      expect(of(kind: SwapQuoteFailureKind.timeout), isNot(of()));
      expect(of(detail: 'x'), isNot(of()));
      expect(of(retryAt: DateTime(2026)), isNot(of()));
      expect(of(reasons: ['thin']), isNot(of()));
      expect(of(requestId: 'req'), isNot(of()));
      expect(of().reasons, isEmpty);
    });

    test('a result carries either a price or the reason there is none', () {
      final quote = quoteOf();
      const failure = SwapQuoteFailure(
        source: SwapLiquiditySource.routed,
        kind: SwapQuoteFailureKind.rateLimited,
      );
      final results = <SwapQuoteResult>[
        SwapQuoteAvailable(quote),
        const SwapQuoteRejected(failure),
      ];

      expect((results.first as SwapQuoteAvailable).quote, same(quote));
      expect((results.last as SwapQuoteRejected).failure, same(failure));
    });
  });
}
