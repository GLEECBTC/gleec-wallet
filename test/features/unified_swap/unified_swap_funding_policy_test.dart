import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_funding_policy.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 12);

  test('native Max leaves the exact reserve and honors one-unit edges', () {
    final balance = _balance(_eth, '1000', now);
    final maximum = unifiedSwapMaximumSourceAmount(
      source: _eth,
      sourceBalance: balance,
      nativeGasAsset: _eth,
      nativeGasBalance: null,
      gasReserve: '100',
      now: now,
    );
    expect(maximum, const UnifiedSwapMaximumAmount.available('900'));

    expect(
      unifiedSwapFundingDecision(
        source: _eth,
        sourceAmount: '900',
        sourceBalance: balance,
        nativeGasAsset: _eth,
        nativeGasBalance: null,
        gasReserve: '100',
        now: now,
      ).isAllowed,
      isTrue,
    );
    expect(
      unifiedSwapFundingDecision(
        source: _eth,
        sourceAmount: '901',
        sourceBalance: balance,
        nativeGasAsset: _eth,
        nativeGasBalance: null,
        gasReserve: '100',
        now: now,
      ),
      const UnifiedSwapFundingDecision.denied(
        maximumSourceAmount: '900',
        denial: UnifiedSwapFundingDenial.insufficientSourceBalance,
      ),
    );
  });

  test('token Max requires a separate fresh native gas balance', () {
    final tokenBalance = _balance(_usdc, '25', now);
    expect(
      unifiedSwapMaximumSourceAmount(
        source: _usdc,
        sourceBalance: tokenBalance,
        nativeGasAsset: _polygon,
        nativeGasBalance: _balance(_polygon, '10', now),
        gasReserve: '10',
        now: now,
      ),
      const UnifiedSwapMaximumAmount.available('25'),
    );
    expect(
      unifiedSwapFundingDecision(
        source: _usdc,
        sourceAmount: '1',
        sourceBalance: tokenBalance,
        nativeGasAsset: _polygon,
        nativeGasBalance: _balance(_polygon, '10', now),
        gasReserve: '10',
        now: now,
      ).isAllowed,
      isTrue,
      reason: 'one smallest token unit is valid at the exact gas boundary',
    );
    expect(
      unifiedSwapMaximumSourceAmount(
        source: _usdc,
        sourceBalance: tokenBalance,
        nativeGasAsset: _polygon,
        nativeGasBalance: _balance(_polygon, '9', now),
        gasReserve: '10',
        now: now,
      ).denial,
      UnifiedSwapFundingDenial.insufficientGasBalance,
    );
  });

  test('stale and future balance observations fail closed', () {
    final stale = UnifiedSwapBalanceSnapshot(
      asset: _usdc,
      amount: '25',
      observedAt: now.subtract(const Duration(minutes: 2)),
      validUntil: now,
    );
    expect(
      unifiedSwapMaximumSourceAmount(
        source: _usdc,
        sourceBalance: stale,
        nativeGasAsset: _polygon,
        nativeGasBalance: _balance(_polygon, '10', now),
        gasReserve: '10',
        now: now,
      ).denial,
      UnifiedSwapFundingDenial.staleSourceBalance,
    );

    final futureGas = UnifiedSwapBalanceSnapshot(
      asset: _polygon,
      amount: '10',
      observedAt: now.add(const Duration(seconds: 1)),
      validUntil: now.add(const Duration(minutes: 1)),
    );
    expect(
      unifiedSwapFundingDecision(
        source: _usdc,
        sourceAmount: '1',
        sourceBalance: _balance(_usdc, '25', now),
        nativeGasAsset: _polygon,
        nativeGasBalance: futureGas,
        gasReserve: '10',
        now: now,
      ).denial,
      UnifiedSwapFundingDenial.staleGasBalance,
    );
  });

  test('exact identity and same-chain gas requirements reject mismatches', () {
    final wrongContract = UnifiedSwapAssetIdentity(
      ticker: _usdc.ticker,
      chainFamily: _usdc.chainFamily,
      chainId: _usdc.chainId,
      kind: _usdc.kind,
      decimals: _usdc.decimals,
      contractAddress: '0x2222222222222222222222222222222222222222',
    );
    expect(
      unifiedSwapMaximumSourceAmount(
        source: _usdc,
        sourceBalance: _balance(wrongContract, '25', now),
        nativeGasAsset: _polygon,
        nativeGasBalance: _balance(_polygon, '10', now),
        gasReserve: '10',
        now: now,
      ).denial,
      UnifiedSwapFundingDenial.sourceBalanceIdentityMismatch,
    );
    expect(
      unifiedSwapMaximumSourceAmount(
        source: _usdc,
        sourceBalance: _balance(_usdc, '25', now),
        nativeGasAsset: _eth,
        nativeGasBalance: _balance(_eth, '10', now),
        gasReserve: '10',
        now: now,
      ).denial,
      UnifiedSwapFundingDenial.invalidGasAssetIdentity,
    );
  });

  test('zero and non-canonical source amounts never become executable', () {
    final balance = _balance(_eth, '1000', now);
    for (final amount in ['0', '01', '-1', '1.0']) {
      expect(
        unifiedSwapFundingDecision(
          source: _eth,
          sourceAmount: amount,
          sourceBalance: balance,
          nativeGasAsset: _eth,
          nativeGasBalance: null,
          gasReserve: '100',
          now: now,
        ).denial,
        UnifiedSwapFundingDenial.invalidSourceAmount,
      );
    }
  });
}

UnifiedSwapBalanceSnapshot _balance(
  UnifiedSwapAssetIdentity asset,
  String amount,
  DateTime now,
) => UnifiedSwapBalanceSnapshot(
  asset: asset,
  amount: amount,
  observedAt: now.subtract(const Duration(seconds: 5)),
  validUntil: now.add(const Duration(minutes: 1)),
);

const _eth = UnifiedSwapAssetIdentity(
  ticker: 'ETH',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '1',
  kind: UnifiedSwapAssetKind.native,
  decimals: 18,
);

const _polygon = UnifiedSwapAssetIdentity(
  ticker: 'POL',
  chainFamily: UnifiedSwapChainFamily.evm,
  chainId: '137',
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
