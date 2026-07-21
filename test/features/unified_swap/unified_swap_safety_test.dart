import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/analytics/events/unified_swap_events.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';
import 'package:web_dex/router/state/unified_swap_section_state.dart';

void main() {
  group('Unified Swap safety defaults', () {
    test('quote and init switches fail closed independently', () {
      const disabled = UnifiedSwapConfig();
      const quoteOnly = UnifiedSwapConfig(quoteEnabled: true);
      const initOnly = UnifiedSwapConfig(initEnabled: true);
      const enabled = UnifiedSwapConfig(quoteEnabled: true, initEnabled: true);

      expect(disabled.canQuote, isFalse);
      expect(disabled.canExecute, isFalse);
      expect(quoteOnly.canQuote, isTrue);
      expect(quoteOnly.canExecute, isFalse);
      expect(initOnly.canQuote, isFalse);
      expect(initOnly.canExecute, isFalse);
      expect(enabled.canExecute, isTrue);
    });

    test('route state replaces detail and ID in one notification', () {
      final state = UnifiedSwapSectionState();
      var notifications = 0;
      state.addListener(() => notifications++);

      state.replace(
        const UnifiedSwapRouteState.activityDetails(
          '550e8400-e29b-41d4-a716-446655440000',
        ),
      );

      expect(notifications, 1);
      expect(state.value.destination, UnifiedSwapDestination.activityDetails);
      expect(
        state.value.routeExecutionId,
        '550e8400-e29b-41d4-a716-446655440000',
      );
    });
  });

  group('Unified Swap analytics privacy', () {
    test('emits only the approved coarse dimensions', () {
      final event = UnifiedSwapOutcomeEventData(
        routeSourceCategory: UnifiedSwapRouteSourceCategory.composite,
        stageCount: 3,
        durationBucket: UnifiedSwapDurationBucket.thirtySecondsToTwoMinutes,
        outcomeCategory: UnifiedSwapOutcomeCategory.recoveryRequired,
      );

      expect(event.parameters, {
        'route_source_category': 'composite',
        'stage_count': 3,
        'duration_bucket': 'thirtySecondsToTwoMinutes',
        'outcome_category': 'recoveryRequired',
      });
      expect(
        event.parameters.keys,
        isNot(
          containsAll([
            'asset',
            'amount',
            'address',
            'hash',
            'provider',
            'route_id',
          ]),
        ),
      );
    });

    test('rejects impossible stage counts', () {
      expect(
        () => UnifiedSwapOutcomeEventData(
          routeSourceCategory: UnifiedSwapRouteSourceCategory.unknown,
          stageCount: 18,
          durationBucket: UnifiedSwapDurationBucket.unknown,
          outcomeCategory: UnifiedSwapOutcomeCategory.unknown,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Unified Swap capability policy', () {
    const source = UnifiedSwapAssetIdentity(
      ticker: 'ETH',
      chainFamily: UnifiedSwapChainFamily.evm,
      chainId: '1',
      kind: UnifiedSwapAssetKind.native,
      decimals: 18,
    );
    const destination = UnifiedSwapAssetIdentity(
      ticker: 'USDC',
      chainFamily: UnifiedSwapChainFamily.evm,
      chainId: '137',
      kind: UnifiedSwapAssetKind.token,
      decimals: 6,
      contractAddress: '0x1111111111111111111111111111111111111111',
    );
    const capability = UnifiedSwapRuntimeCapability(
      source: source,
      destination: destination,
      routeSupported: true,
      sourceSelector: UnifiedSwapSourceSelectorKind.hd,
      executor: UnifiedSwapExecutorKind.evmSoftwareKey,
      supportedModes: [UnifiedSwapExecutionMode.signAndBroadcast],
    );
    const allowedContext = UnifiedSwapCapabilityContext(
      authenticated: true,
      walletKind: UnifiedSwapWalletKind.softwareHd,
      source: source,
      destination: destination,
      sourceActivated: true,
      sourceCompliance: UnifiedSwapComplianceDecision.allowed,
      destinationCompliance: UnifiedSwapComplianceDecision.allowed,
      capability: capability,
    );
    const policy = UnifiedSwapCapabilityPolicy();

    test('allows quoting but not execution when init switch is off', () {
      const config = UnifiedSwapConfig(quoteEnabled: true);

      expect(
        policy
            .evaluate(allowedContext, config: config, forExecution: false)
            .isAllowed,
        isTrue,
      );
      expect(
        policy
            .evaluate(allowedContext, config: config, forExecution: true)
            .denial,
        UnifiedSwapCapabilityDenial.initDisabled,
      );
    });

    test('unknown capability and compliance values fail closed', () {
      const unknownCapability = UnifiedSwapRuntimeCapability(
        source: source,
        destination: destination,
        routeSupported: true,
        sourceSelector: UnifiedSwapSourceSelectorKind.hd,
        executor: UnifiedSwapExecutorKind.evmSoftwareKey,
        supportedModes: [UnifiedSwapExecutionMode.signAndBroadcast],
        isUnknownVariant: true,
      );
      const unknownContext = UnifiedSwapCapabilityContext(
        authenticated: true,
        walletKind: UnifiedSwapWalletKind.softwareHd,
        source: source,
        destination: destination,
        sourceActivated: true,
        sourceCompliance: UnifiedSwapComplianceDecision.unknown,
        destinationCompliance: UnifiedSwapComplianceDecision.allowed,
        capability: unknownCapability,
      );

      expect(
        policy
            .evaluate(
              unknownContext,
              config: const UnifiedSwapConfig(
                quoteEnabled: true,
                initEnabled: true,
              ),
              forExecution: true,
            )
            .denial,
        UnifiedSwapCapabilityDenial.sourceBlocked,
      );
    });

    test('requires exact capability identity', () {
      const mismatchedDestination = UnifiedSwapAssetIdentity(
        ticker: 'USDC',
        chainFamily: UnifiedSwapChainFamily.evm,
        chainId: '137',
        kind: UnifiedSwapAssetKind.token,
        decimals: 18,
        contractAddress: '0x1111111111111111111111111111111111111111',
      );
      const context = UnifiedSwapCapabilityContext(
        authenticated: true,
        walletKind: UnifiedSwapWalletKind.softwareIguana,
        source: source,
        destination: mismatchedDestination,
        sourceActivated: true,
        sourceCompliance: UnifiedSwapComplianceDecision.allowed,
        destinationCompliance: UnifiedSwapComplianceDecision.allowed,
        capability: capability,
      );

      expect(
        policy
            .evaluate(
              context,
              config: const UnifiedSwapConfig(
                quoteEnabled: true,
                initEnabled: true,
              ),
              forExecution: true,
            )
            .denial,
        UnifiedSwapCapabilityDenial.capabilityIdentityMismatch,
      );
    });
  });
}
