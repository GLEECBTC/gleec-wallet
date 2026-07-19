import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 12);

  test('product thresholds and token handling are exact and fail closed', () {
    expect(unifiedSwapDefaultSlippageBps, 50);
    expect(
      unifiedSwapTokenDecision(UnifiedSwapTokenTrust.suspicious),
      UnifiedSwapTokenDecision.blocked,
    );
    expect(
      unifiedSwapTokenDecision(UnifiedSwapTokenTrust.unknown),
      UnifiedSwapTokenDecision.confirmationRequired,
    );

    final below = unifiedSwapRiskWarnings(
      priceImpactBps: 299,
      expectedReceive: '10000',
      minimumReceive: '9901',
      authoritativeLowLiquidity: false,
    );
    expect(below.highPriceImpact, isFalse);
    expect(below.lowLiquidity, isFalse);

    final atThreshold = unifiedSwapRiskWarnings(
      priceImpactBps: 300,
      expectedReceive: '10000',
      minimumReceive: '9900',
      authoritativeLowLiquidity: false,
    );
    expect(atThreshold.highPriceImpact, isTrue);
    expect(atThreshold.lowLiquidity, isTrue);
  });

  test('quiet refresh permits at most 25 bps and respects every old cap', () {
    final consented = _snapshot(
      now,
      expected: '10000',
      minimum: '9900',
      requiredFee: '20',
      feeLimit: '25',
      requiredGas: '5',
      gasCap: '8',
    );
    final exactlyQuiet = _snapshot(
      now,
      expected: '9975',
      minimum: '9900',
      requiredFee: '25',
      feeLimit: '999',
      requiredGas: '8',
      gasCap: '999',
    );
    expect(
      unifiedSwapRefreshDecision(
        consented: consented,
        replacement: exactlyQuiet,
        now: now,
      ),
      UnifiedSwapRefreshDecision.quiet,
    );

    final overFeeCap = _snapshot(
      now,
      expected: '10000',
      minimum: '9900',
      requiredFee: '26',
      feeLimit: '999',
      requiredGas: '8',
      gasCap: '999',
    );
    expect(
      unifiedSwapRefreshDecision(
        consented: consented,
        replacement: overFeeCap,
        now: now,
      ),
      UnifiedSwapRefreshDecision.explicitConsentRequired,
    );
  });

  test(
    'topology, tool, identity, or address change requires a fresh quote',
    () {
      final consented = _snapshot(now);
      final changed = _snapshot(
        now,
        structure: _structure(
          recipient: '0x3333333333333333333333333333333333333333',
        ),
      );
      expect(
        unifiedSwapRefreshDecision(
          consented: consented,
          replacement: changed,
          now: now,
        ),
        UnifiedSwapRefreshDecision.freshQuoteRequired,
      );
    },
  );

  test('best-net-return copy requires comparable fresh wallet valuations', () {
    UnifiedSwapValuationProof proof(String currency, DateTime validUntil) =>
        UnifiedSwapValuationProof(
          currency: currency,
          observedAt: now.subtract(const Duration(seconds: 5)),
          validUntil: validUntil,
          netMinimumReceive: '10.25',
        );

    expect(
      canClaimUnifiedSwapBestNetReturn(
        valuations: [
          proof('USD', now.add(const Duration(minutes: 1))),
          proof('USD', now.add(const Duration(minutes: 1))),
        ],
        now: now,
      ),
      isTrue,
    );
    expect(
      canClaimUnifiedSwapBestNetReturn(
        valuations: [
          proof('USD', now.add(const Duration(minutes: 1))),
          proof('EUR', now.add(const Duration(minutes: 1))),
        ],
        now: now,
      ),
      isFalse,
    );
    expect(
      canClaimUnifiedSwapBestNetReturn(
        valuations: [
          proof('USD', now.subtract(const Duration(seconds: 1))),
          proof('USD', now.add(const Duration(minutes: 1))),
        ],
        now: now,
      ),
      isFalse,
    );
  });
}

UnifiedSwapRefreshSnapshot _snapshot(
  DateTime now, {
  UnifiedSwapRouteStructure? structure,
  String expected = '10000',
  String minimum = '9900',
  String requiredFee = '20',
  String feeLimit = '25',
  String requiredGas = '5',
  String gasCap = '8',
}) => UnifiedSwapRefreshSnapshot(
  structure: structure ?? _structure(),
  expectedReceive: expected,
  minimumReceive: minimum,
  requiredNonNetworkFees: {'provider:USDC:137': requiredFee},
  consentedNonNetworkFeeLimits: {'provider:USDC:137': feeLimit},
  requiredNetworkFees: {'stage-1:ETH:1': requiredGas},
  consentedNetworkFeeCaps: {'stage-1:ETH:1': gasCap},
  expiresAt: now.add(const Duration(minutes: 1)),
);

UnifiedSwapRouteStructure _structure({
  String recipient = '0x2222222222222222222222222222222222222222',
}) => UnifiedSwapRouteStructure(
  topology: 'external',
  source: _eth,
  destination: _usdc,
  sourceSelectorFingerprint: 'active',
  resolvedSourceAddress: '0x1111111111111111111111111111111111111111',
  recipient: recipient,
  stageKinds: const ['external_liquidity'],
  selectedTools: const ['bridge:a', 'exchange:b'],
);

const _eth = UnifiedSwapAssetIdentity(
  ticker: 'ETH',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '1',
  kind: UnifiedSwapAssetKind.native,
  decimals: 18,
);

const _usdc = UnifiedSwapAssetIdentity(
  ticker: 'USDC',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '137',
  kind: UnifiedSwapAssetKind.token,
  decimals: 6,
  contractAddress: '0x1111111111111111111111111111111111111111',
);
