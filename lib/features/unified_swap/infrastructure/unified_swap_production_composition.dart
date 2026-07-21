import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:decimal/decimal.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/analytics/events/unified_swap_events.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_funding_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_model_limits.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_selection_models.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_quote_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';
import 'package:web_dex/router/state/unified_swap_section_state.dart';
import 'package:web_dex/shared/utils/kdf_wallet_authority.dart';

typedef UnifiedSwapCapabilitiesLoader =
    Future<kdf.TradeRouteCapabilitiesResult> Function({
      required TradeRouteManager manager,
      required List<String> tickers,
    });

typedef UnifiedSwapValuationSnapshotProvider =
    kdf.ValuationSnapshot? Function();

typedef UnifiedSwapClockValidityCheck = Future<bool> Function();

/// Emits only the approved coarse outcome schema and persists a bounded hash
/// set so terminal outcomes are not emitted again after app restart.
final class UnifiedSwapAnalyticsCoordinator {
  UnifiedSwapAnalyticsCoordinator({required AnalyticsBloc? analytics})
    : _analytics = analytics;

  static const _deduplicationKey = 'unified_swap_terminal_outcome_digests_v1';
  static const _maximumRetainedDigests = 256;

  final AnalyticsBloc? _analytics;
  Future<void> _pending = Future.value();

  void record(RouteExecutionProgress? progress) {
    if (_analytics == null || progress == null || !progress.isExecutable) {
      return;
    }
    final outcome = switch (progress.outcome) {
      RouteExecutionOutcome.completed => UnifiedSwapOutcomeCategory.completed,
      RouteExecutionOutcome.cancelled => UnifiedSwapOutcomeCategory.cancelled,
      RouteExecutionOutcome.failed => UnifiedSwapOutcomeCategory.failed,
      RouteExecutionOutcome.recovery =>
        UnifiedSwapOutcomeCategory.recoveryRequired,
      RouteExecutionOutcome.active ||
      RouteExecutionOutcome.attentionRequired ||
      RouteExecutionOutcome.unknown => null,
    };
    if (outcome == null || progress.stageCount > 17) return;
    _pending = _pending
        .then((_) => _recordOnce(progress, outcome))
        .onError((_, _) {});
  }

  Future<void> _recordOnce(
    RouteExecutionProgress progress,
    UnifiedSwapOutcomeCategory outcome,
  ) async {
    final digest = sha256
        .convert(
          utf8.encode('${progress.routeExecutionId}:${progress.outcome.name}'),
        )
        .toString();
    final preferences = await SharedPreferences.getInstance();
    final stored =
        preferences.getStringList(_deduplicationKey) ?? const <String>[];
    final retained = <String>[];
    final first = stored.length > _maximumRetainedDigests
        ? stored.length - _maximumRetainedDigests
        : 0;
    for (var index = first; index < stored.length; index++) {
      final value = stored[index];
      if (RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) retained.add(value);
    }
    if (retained.contains(digest)) return;
    final updated = <String>[...retained, digest];
    final bounded = updated.length <= _maximumRetainedDigests
        ? updated
        : updated.sublist(updated.length - _maximumRetainedDigests);
    await preferences.setStringList(_deduplicationKey, bounded);
    _analytics?.add(
      AnalyticsUnifiedSwapOutcomeEvent(
        routeSourceCategory: UnifiedSwapRouteSourceCategory.unknown,
        stageCount: progress.stageCount,
        durationBucket: UnifiedSwapDurationBucket.unknown,
        outcomeCategory: outcome,
      ),
    );
  }
}

/// The immutable product policy supplied to every wallet-scoped composition.
final class UnifiedSwapProductionPolicy {
  const UnifiedSwapProductionPolicy({
    this.slippageBps = unifiedSwapDefaultSlippageBps,
    this.quietRefreshMaximumDegradationBps =
        unifiedSwapQuietRefreshMaximumDegradationBps,
    this.networkFeeNumerator = 125,
    this.networkFeeDenominator = 100,
    this.consentLifetime = const Duration(minutes: 2),
    this.quoteDeadline = const Duration(seconds: 30),
    this.preparationDeadline = const Duration(seconds: 30),
    this.executionDeadlines = const KdfRouteExecutionDeadlines(),
  }) : assert(slippageBps >= 0 && slippageBps <= 10_000),
       assert(
         quietRefreshMaximumDegradationBps >= 0 &&
             quietRefreshMaximumDegradationBps <= 10_000,
       ),
       assert(networkFeeDenominator > 0),
       assert(networkFeeNumerator >= networkFeeDenominator);

  final int slippageBps;
  final int quietRefreshMaximumDegradationBps;
  final int networkFeeNumerator;
  final int networkFeeDenominator;
  final Duration consentLifetime;
  final Duration quoteDeadline;
  final Duration preparationDeadline;
  final KdfRouteExecutionDeadlines executionDeadlines;
}

/// A fresh, wallet-verified recovery quote request derived from KDF's durable
/// holding. It is not action authority: the customer must still obtain and
/// accept a newly prepared Review before its action identity can be submitted.
final class UnifiedSwapRecoveryDraft {
  UnifiedSwapRecoveryDraft({
    required this.routeExecutionId,
    required this.actionId,
    required this.expectedStateRevision,
    required this.intent,
    required this.recipientIsWalletOwned,
  }) {
    UnifiedSwapModelLimits.requireString(routeExecutionId, 'routeExecutionId');
    UnifiedSwapModelLimits.requireString(actionId, 'actionId');
    if (expectedStateRevision < 0) {
      throw RangeError.value(expectedStateRevision, 'expectedStateRevision');
    }
  }

  final String routeExecutionId;
  final String actionId;
  final int expectedStateRevision;
  final UnifiedSwapIntent intent;
  final bool recipientIsWalletOwned;
}

/// Production-only wallet adapter for Unified Swap.
///
/// This class is the only wallet layer that translates SDK [Asset] and
/// [PubkeyInfo] values into route identities. Every lookup is exact and
/// ambiguous ticker/address results are rejected. It never materializes a
/// provider transaction and exposes only KDF's Case-A quote/preparation path.
final class UnifiedSwapProductionComposition
    implements UnifiedSwapSelectionGateway {
  UnifiedSwapProductionComposition({
    required this.sdk,
    required this.manager,
    required this.config,
    required UnifiedSwapCapabilitiesLoader loadCapabilities,
    UnifiedSwapValuationSnapshotProvider? valuationSnapshot,
    UnifiedSwapClockValidityCheck? clockValidityCheck,
    this.tradingStatus,
    this.policy = const UnifiedSwapProductionPolicy(),
    DateTime Function()? now,
  }) : _loadCapabilities = loadCapabilities,
       _valuationSnapshot = valuationSnapshot,
       _clockValidityCheck = clockValidityCheck,
       _now = now ?? _utcNow {
    if (policy.consentLifetime <= Duration.zero ||
        policy.consentLifetime > const Duration(minutes: 5) ||
        policy.quoteDeadline <= Duration.zero ||
        policy.preparationDeadline <= Duration.zero ||
        !policy.executionDeadlines.isValid) {
      throw ArgumentError('Unified Swap production deadlines are invalid');
    }
  }

  final KomodoDefiSdk sdk;
  final TradeRouteManager manager;
  final UnifiedSwapConfig config;
  final TradingStatusService? tradingStatus;
  final UnifiedSwapProductionPolicy policy;
  final UnifiedSwapCapabilitiesLoader _loadCapabilities;
  final UnifiedSwapValuationSnapshotProvider? _valuationSnapshot;
  final UnifiedSwapClockValidityCheck? _clockValidityCheck;
  final DateTime Function() _now;

  Future<kdf.TradeRouteCapabilitiesResult>? _capabilitiesRequest;
  DateTime? _capabilitiesValidUntil;
  String? _capabilitiesRequestKey;

  KdfUnifiedSwapQuoteRepository quoteRepository(
    String walletId, {
    required Future<String?> Function() currentWalletId,
  }) {
    final client = TradeRouteManagerQuoteClient(manager);
    return KdfUnifiedSwapQuoteRepository(
      client: client,
      walletId: walletId,
      validateRecipient: ({required ticker, required address}) async => false,
      validateExactRecipient: _validateRecipient,
      preparationClient: client,
      preparationLimitsPolicy: _preparationLimits,
      expectedSourceAddress: expectedSourceAddress,
      eligibilityCheck: (intent) async {
        if (await currentWalletId() != walletId) return false;
        final before = await _currentSoftwareUser();
        if (before?.walletId.compoundId != walletId ||
            !await isIntentEligible(intent)) {
          return false;
        }
        final after = await _currentSoftwareUser();
        if (after?.walletId.compoundId != walletId) return false;
        return await currentWalletId() == walletId;
      },
      candidateEligibility: _candidateCanReachReview,
      valuationSnapshot: _valuationSnapshot,
      consentLifetime: policy.consentLifetime,
      quoteDeadline: policy.quoteDeadline,
      preparationDeadline: policy.preparationDeadline,
      now: _now,
    );
  }

  /// Builds the only customer-selectable inventory. Source choices are exact
  /// activated EVM software-key assets. Destination choices are exact SDK
  /// catalog identities advertised by a current executable KDF capability;
  /// they do not need to be activated.
  @override
  Future<UnifiedSwapSelectionInventory?> selectionInventory() async {
    final walletId = (await _currentSoftwareUser())?.walletId.compoundId;
    if (!config.canQuote || walletId == null) return null;
    final activated = await _activatedExactAssets();
    if (activated.isEmpty) return null;
    final capabilities = await _capabilities();
    if (capabilities == null) return null;

    final sources = <UnifiedSwapAssetOption>[];
    final destinations = <UnifiedSwapAssetOption>[];
    final pairs = <UnifiedSwapRoutePair>[];
    for (final record in capabilities.capabilities.where(
      _isExecutableCapability,
    )) {
      final sourceIdentity = _routeAsset(record.from);
      final destinationIdentity = _routeAsset(record.to);
      if (sourceIdentity == null ||
          destinationIdentity == null ||
          !sourceIdentity.isValidEvmV1) {
        continue;
      }
      final source = _singleAsset(activated, sourceIdentity);
      final destination = _catalogExactAsset(destinationIdentity);
      if (source == null || destination == null) continue;
      if (!_isCompliant(source) || !_isCompliant(destination)) continue;

      final sourceOption = UnifiedSwapAssetOption(
        identity: sourceIdentity,
        tokenTrust: _tokenTrust(source),
      );
      final destinationOption = UnifiedSwapAssetOption(
        identity: destinationIdentity,
        tokenTrust: _tokenTrust(destination),
      );
      _addUniqueOption(sources, sourceOption);
      _addUniqueOption(destinations, destinationOption);
      final pair = UnifiedSwapRoutePair(
        source: sourceIdentity,
        destination: destinationIdentity,
      );
      if (!pairs.contains(pair)) pairs.add(pair);
    }
    if (pairs.isEmpty) return null;
    _sortAssetOptions(sources);
    _sortAssetOptions(destinations);
    pairs.sort(_compareRoutePairs);
    if (!await _isSameSoftwareWallet(walletId)) return null;
    return UnifiedSwapSelectionInventory(
      sources: sources,
      destinations: destinations,
      pairs: pairs,
    );
  }

  @override
  Future<List<UnifiedSwapSourceAddressOption>> sourceAddressOptions(
    UnifiedSwapAssetIdentity source,
  ) async {
    final walletId = (await _currentSoftwareUser())?.walletId.compoundId;
    if (walletId == null) return const [];
    final inventory = await selectionInventory();
    if (inventory?.sourceOption(source) == null) return const [];
    final asset = await _activatedExactAsset(source);
    if (asset == null) return const [];
    try {
      final pubkeys = await sdk.pubkeys.refreshPubkeys(asset);
      final active = pubkeys.keys.where((key) => key.isActiveForSwap).toList();
      final options = <UnifiedSwapSourceAddressOption>[];
      for (final pubkey in pubkeys.keys) {
        final selection = active.length == 1 && identical(active.single, pubkey)
            ? const UnifiedSwapActiveSourceSelection()
            : pubkey.derivationPath == null
            ? null
            : UnifiedSwapHdPathSourceSelection(pubkey.derivationPath!);
        final balance = _smallestUnits(pubkey.balance.spendable, source);
        if (selection == null || balance == null) continue;
        options.add(
          UnifiedSwapSourceAddressOption(
            selection: selection,
            address: pubkey.address,
            balance: balance,
            isActive: active.length == 1 && identical(active.single, pubkey),
            label: _normalizedAddressLabel(pubkey.name),
          ),
        );
      }
      return await _isSameSoftwareWallet(walletId)
          ? List.unmodifiable(options)
          : const [];
    } on Object {
      return const [];
    }
  }

  @override
  Future<UnifiedSwapIntent?> selectSourceAsset(
    UnifiedSwapIntent current,
    UnifiedSwapAssetIdentity source,
  ) async {
    final walletId = (await _currentSoftwareUser())?.walletId.compoundId;
    if (walletId == null) return null;
    if (current.source.sameIdentity(source)) return null;
    final inventory = await selectionInventory();
    final sourceOption = inventory?.sourceOption(source);
    if (inventory == null || sourceOption == null) return null;
    final destinations = inventory.destinationsFor(source);
    if (destinations.isEmpty) return null;
    final destination = inventory.supportsPair(source, current.destination)
        ? inventory.destinationOption(current.destination)!
        : destinations.first;
    final sourceAsset = await _activatedExactAsset(source);
    final sourceAddress = sourceAsset == null
        ? null
        : await _activeAddress(sourceAsset);
    if (sourceAddress == null) return null;
    final recipient = await _recipientForSelection(
      destination: destination.identity,
      preferredRecipient: destination.identity.sameIdentity(current.destination)
          ? current.recipient
          : null,
      sourceAddress: sourceAddress.address,
    );
    if (recipient == null) return null;
    final next = UnifiedSwapIntent(
      revision: current.revision + 1,
      source: source,
      destination: destination.identity,
      sourceAmount: '0',
      sourceSelection: const UnifiedSwapActiveSourceSelection(),
      recipient: recipient,
      slippageBps: policy.slippageBps,
      sourceTokenTrust: sourceOption.tokenTrust,
      destinationTokenTrust: destination.tokenTrust,
    );
    return await _isSameSoftwareWallet(walletId) ? next : null;
  }

  @override
  Future<UnifiedSwapIntent?> selectDestinationAsset(
    UnifiedSwapIntent current,
    UnifiedSwapAssetIdentity destination,
  ) async {
    final walletId = (await _currentSoftwareUser())?.walletId.compoundId;
    if (walletId == null) return null;
    if (current.destination.sameIdentity(destination)) return null;
    final inventory = await selectionInventory();
    final destinationOption = inventory?.destinationOption(destination);
    if (inventory == null ||
        destinationOption == null ||
        !inventory.supportsPair(current.source, destination)) {
      return null;
    }
    final source = await _activatedExactAsset(current.source);
    final sourceAddress = source == null
        ? null
        : await _selectedAddress(source, current.sourceSelection);
    if (sourceAddress == null) return null;
    final recipient = await _recipientForSelection(
      destination: destination,
      preferredRecipient: current.recipient,
      sourceAddress: sourceAddress.address,
    );
    if (recipient == null) return null;
    final next = current.copyWith(
      revision: current.revision + 1,
      destination: destination,
      recipient: recipient,
      destinationTokenTrust: destinationOption.tokenTrust,
      unknownTokenConfirmed: false,
      externalRecipientConfirmed: false,
    );
    return await _isSameSoftwareWallet(walletId) ? next : null;
  }

  @override
  Future<UnifiedSwapIntent?> selectSourceAddress(
    UnifiedSwapIntent current,
    UnifiedSwapSourceSelection selection,
  ) async {
    final walletId = (await _currentSoftwareUser())?.walletId.compoundId;
    if (walletId == null) return null;
    if (selection == current.sourceSelection) return null;
    final options = await sourceAddressOptions(current.source);
    if (!options.any((option) => option.selection == selection)) return null;
    final next = current.copyWith(
      revision: current.revision + 1,
      sourceSelection: selection,
      externalRecipientConfirmed: false,
    );
    return await _isSameSoftwareWallet(walletId) ? next : null;
  }

  /// Produces wallet-owned defaults without requesting a quote. Legacy URL
  /// hints are untrusted and affect this one selection only after a ticker has
  /// a single exact eligible match. Invalid or ambiguous hints are ignored.
  Future<UnifiedSwapIntent?> initialIntent({
    UnifiedSwapLegacyHints legacyHints = const UnifiedSwapLegacyHints(),
  }) async {
    final walletId = (await _currentSoftwareUser())?.walletId.compoundId;
    if (walletId == null) return null;
    final inventory = await selectionInventory();
    if (inventory == null || inventory.isEmpty) return null;
    final preferredPairs = _preferredPairs(inventory, legacyHints);
    final activated = await _activatedExactAssets();
    for (final pair in preferredPairs) {
      final source = _singleAsset(activated, pair.source);
      final sourceOption = inventory.sourceOption(pair.source);
      final destinationOption = inventory.destinationOption(pair.destination);
      if (source == null || sourceOption == null || destinationOption == null) {
        continue;
      }
      final sourceAddress = await _activeAddress(source);
      if (sourceAddress == null ||
          _smallestUnits(sourceAddress.balance.spendable, pair.source) ==
              null) {
        continue;
      }
      final recipient = await _recipientForSelection(
        destination: pair.destination,
        sourceAddress: sourceAddress.address,
      );
      if (recipient == null) continue;
      final intent = UnifiedSwapIntent(
        revision: 0,
        source: pair.source,
        destination: pair.destination,
        sourceAmount: '0',
        sourceSelection: const UnifiedSwapActiveSourceSelection(),
        recipient: recipient,
        slippageBps: policy.slippageBps,
        sourceTokenTrust: sourceOption.tokenTrust,
        destinationTokenTrust: destinationOption.tokenTrust,
      );
      return await _isSameSoftwareWallet(walletId) ? intent : null;
    }
    return null;
  }

  Future<bool> isIntentEligible(UnifiedSwapIntent intent) async {
    if (!config.canQuote || intent.tokenFailure != null) return false;
    final user = await _currentSoftwareUser();
    if (user == null) return false;
    final activated = await _activatedExactAssets();
    final source = _singleAsset(activated, intent.source);
    final destination = _catalogExactAsset(intent.destination);
    if (source == null || destination == null) return false;
    if (!_isCompliant(source) || !_isCompliant(destination)) return false;
    if (!_tokenTrustMatches(source, intent.sourceTokenTrust) ||
        !_tokenTrustMatches(destination, intent.destinationTokenTrust)) {
      return false;
    }
    final capability = await _runtimeCapability(
      intent.source,
      intent.destination,
      intent.sourceSelection.kind,
    );
    final decision = const UnifiedSwapCapabilityPolicy().evaluate(
      UnifiedSwapCapabilityContext(
        authenticated: true,
        walletKind: _walletKind(user),
        source: intent.source,
        destination: intent.destination,
        sourceActivated: true,
        sourceCompliance: UnifiedSwapComplianceDecision.allowed,
        destinationCompliance: UnifiedSwapComplianceDecision.allowed,
        capability: capability,
      ),
      config: config,
      forExecution: false,
    );
    if (!decision.isAllowed) return false;

    final funding = await _freshFunding(source, intent.sourceSelection);
    if (funding == null) return false;
    final fundingDecision = unifiedSwapFundingDecision(
      source: intent.source,
      sourceAmount: intent.sourceAmount,
      sourceBalance: funding.sourceBalance,
      nativeGasAsset: funding.nativeGasAsset,
      nativeGasBalance: funding.nativeGasBalance,
      gasReserve: intent.source.kind == UnifiedSwapAssetKind.token ? '1' : '0',
      now: _now(),
    );
    if (!fundingDecision.isAllowed) {
      return false;
    }
    if (!await _validateRecipient(
      asset: intent.destination,
      address: intent.recipient,
    )) {
      return false;
    }
    final recipientIsOwned = await _isWalletOwnedDestinationAddress(
      destination: destination,
      identity: intent.destination,
      address: intent.recipient,
      activated: activated,
    );
    if (!recipientIsOwned && !intent.externalRecipientConfirmed) return false;
    return _isSameSoftwareWallet(user.walletId.compoundId);
  }

  Future<bool> isReviewEligible(RouteExecutionReview review) async {
    if (!config.canExecute ||
        !review.isExecutable ||
        !await _hasValidSystemClock()) {
      return false;
    }
    final user = await _currentSoftwareUser();
    if (user == null || user.walletId.compoundId != review.walletId) {
      return false;
    }
    final activated = await _activatedExactAssets();
    final source = _singleAsset(activated, review.source);
    final destination = _catalogExactAsset(review.destination);
    if (source == null || destination == null) return false;
    if (!await _refreshTradingEligibility(source, destination)) return false;
    final refreshedUser = await _currentSoftwareUser();
    if (refreshedUser == null ||
        refreshedUser.walletId.compoundId != review.walletId) {
      return false;
    }
    final capability = await _runtimeCapability(
      review.source,
      review.destination,
      review.sourceSelectorKind,
    );
    final decision = const UnifiedSwapCapabilityPolicy().evaluate(
      UnifiedSwapCapabilityContext(
        authenticated: true,
        walletKind: _walletKind(refreshedUser),
        source: review.source,
        destination: review.destination,
        sourceActivated: true,
        sourceCompliance: UnifiedSwapComplianceDecision.allowed,
        destinationCompliance: UnifiedSwapComplianceDecision.allowed,
        capability: capability,
      ),
      config: config,
      forExecution: true,
    );
    if (!decision.isAllowed ||
        !await _validateRecipient(
          asset: review.destination,
          address: review.recipient,
        )) {
      return false;
    }
    final funding = await _freshFunding(
      source,
      _selectionForKind(review.sourceSelectorKind),
      expectedAddress: review.resolvedSourceAddress,
    );
    final ownedSource = funding?.sourceAddress;
    if (ownedSource == null ||
        !_pubkeyMatchesSelector(ownedSource, review.sourceSelectorKind)) {
      return false;
    }
    final reserve = _reviewGasReserve(review, funding!.nativeGasAsset);
    if (reserve == null ||
        !unifiedSwapFundingDecision(
          source: review.source,
          sourceAmount: review.sourceAmount,
          sourceBalance: funding.sourceBalance,
          nativeGasAsset: funding.nativeGasAsset,
          nativeGasBalance: funding.nativeGasBalance,
          gasReserve: reserve,
          now: _now(),
        ).isAllowed) {
      return false;
    }
    final recipientIsOwned = await _isWalletOwnedDestinationAddress(
      destination: destination,
      identity: review.destination,
      address: review.recipient,
      activated: activated,
    );
    if (!recipientIsOwned && !review.externalRecipientConfirmed) return false;

    // Funding and recipient ownership both await mutable wallet services.
    // Sample clock health and the authenticated wallet together at the final
    // boundary, with no further asynchronous work before returning eligible.
    final finalChecks = await Future.wait<bool>([
      _hasValidSystemClock(),
      _currentSoftwareUser().then(
        (current) =>
            current != null && current.walletId.compoundId == review.walletId,
      ),
    ]);
    return finalChecks.every((value) => value);
  }

  /// Resolves recipient ownership without weakening chain-native validation.
  /// `null` means exact catalog identity or chain-native validation was
  /// unavailable. Destination activation is not an eligibility requirement.
  Future<bool?> recipientIsWalletOwned({
    required UnifiedSwapAssetIdentity asset,
    required String address,
  }) async {
    final walletId = (await _currentSoftwareUser())?.walletId.compoundId;
    if (walletId == null) return null;
    final destination = _catalogExactAsset(asset);
    if (destination == null ||
        !await _validateRecipient(asset: asset, address: address)) {
      return null;
    }
    final owned = await _isWalletOwnedDestinationAddress(
      destination: destination,
      identity: asset,
      address: address,
      activated: await _activatedExactAssets(),
    );
    return await _isSameSoftwareWallet(walletId) ? owned : null;
  }

  /// Re-reads the durable route and derives a new intent from its exact
  /// holding. Cached task progress is used only to bind the customer's click;
  /// every action/revision/holding value comes from the fresh KDF response.
  Future<UnifiedSwapRecoveryDraft?> recoveryDraft(
    RouteExecutionProgress progress, {
    required int intentRevision,
  }) async {
    if (!config.canExecute || intentRevision < 0 || !progress.isExecutable) {
      return null;
    }
    final observedAction = progress.pendingAction;
    if (observedAction == null ||
        observedAction.reason != RoutePendingActionReason.recoveryRequired ||
        !observedAction.allowedActions.contains(
          RouteExecutionActionKind.selectRecoveryRoute,
        )) {
      return null;
    }

    try {
      final details = await manager
          .getExecution(routeExecutionId: progress.routeExecutionId)
          .timeout(policy.executionDeadlines.control);
      final status = details.status;
      final action = status.pendingUserAction;
      final holding = status.actualHolding;
      if (details.routeExecutionId != progress.routeExecutionId ||
          !status.isExecutable ||
          status.stateRevision != progress.stateRevision ||
          action == null ||
          !action.isExecutable ||
          action.actionId != observedAction.actionId ||
          action.reason.knownValue !=
              kdf.PendingUserActionReason.recoveryRequired ||
          !action.allowedActions.any(
            (value) =>
                value.knownValue == kdf.AllowedUserAction.selectRecoveryRoute,
          ) ||
          holding == null ||
          !holding.isExecutable) {
        return null;
      }

      final sourceIdentity = _routeAsset(holding.asset);
      final destinationIdentity = _routeAsset(
        details.routeConsent.routeIntent.toAsset,
      );
      if (sourceIdentity == null ||
          destinationIdentity == null ||
          !sourceIdentity.isValidEvmV1) {
        return null;
      }
      final user = await _currentSoftwareUser();
      if (user == null) return null;
      final activated = await _activatedExactAssets();
      final source = _singleAsset(activated, sourceIdentity);
      final destination = _catalogExactAsset(destinationIdentity);
      if (source == null ||
          destination == null ||
          !_isCompliant(source) ||
          !_isCompliant(destination)) {
        return null;
      }
      final selection = await _sourceSelectionForAddress(
        source,
        holding.address,
      );
      if (selection == null ||
          !await _validateRecipient(
            asset: destinationIdentity,
            address: details.recipientAddress,
          )) {
        return null;
      }
      final recipientIsOwned = await _isWalletOwnedDestinationAddress(
        destination: destination,
        identity: destinationIdentity,
        address: details.recipientAddress,
        activated: activated,
      );
      final intent = UnifiedSwapIntent(
        revision: intentRevision,
        source: sourceIdentity,
        destination: destinationIdentity,
        sourceAmount: holding.amount,
        sourceSelection: selection,
        recipient: details.recipientAddress,
        slippageBps: policy.slippageBps,
        sourceTokenTrust: _tokenTrust(source),
        destinationTokenTrust: _tokenTrust(destination),
      );
      final capability = await _runtimeCapability(
        sourceIdentity,
        destinationIdentity,
        selection.kind,
      );
      if (!const UnifiedSwapCapabilityPolicy()
          .evaluate(
            UnifiedSwapCapabilityContext(
              authenticated: true,
              walletKind: _walletKind(user),
              source: sourceIdentity,
              destination: destinationIdentity,
              sourceActivated: true,
              sourceCompliance: UnifiedSwapComplianceDecision.allowed,
              destinationCompliance: UnifiedSwapComplianceDecision.allowed,
              capability: capability,
            ),
            config: config,
            forExecution: true,
          )
          .isAllowed) {
        return null;
      }
      final draft = UnifiedSwapRecoveryDraft(
        routeExecutionId: details.routeExecutionId,
        actionId: action.actionId,
        expectedStateRevision: status.stateRevision,
        intent: intent,
        recipientIsWalletOwned: recipientIsOwned,
      );
      return await _isSameSoftwareWallet(user.walletId.compoundId)
          ? draft
          : null;
    } on Object {
      return null;
    }
  }

  Future<String?> expectedSourceAddress(UnifiedSwapIntent intent) async {
    final walletId = (await _currentSoftwareUser())?.walletId.compoundId;
    if (walletId == null) return null;
    final asset = await _activatedExactAsset(intent.source);
    final address = asset == null
        ? null
        : await _selectedAddress(asset, intent.sourceSelection);
    return await _isSameSoftwareWallet(walletId) ? address?.address : null;
  }

  /// Resolves the only safe V1 Max value currently available from the SDK.
  ///
  /// ERC-20 Max is the exact selected-address token balance after proving the
  /// same address has a positive activated native-gas holding. Native Max is
  /// intentionally unavailable because the SDK's complete transaction-fee
  /// estimator is disabled; the wallet never guesses a reserve.
  Future<String?> maximumAmount(UnifiedSwapIntent intent) async {
    if (!config.canQuote ||
        intent.source.kind != UnifiedSwapAssetKind.token ||
        intent.tokenFailure != null) {
      return null;
    }
    final user = await _currentSoftwareUser();
    if (user == null) return null;
    final activated = await _activatedExactAssets();
    final source = _singleAsset(activated, intent.source);
    final destination = _catalogExactAsset(intent.destination);
    if (source == null ||
        destination == null ||
        !_isCompliant(source) ||
        !_isCompliant(destination) ||
        !_tokenTrustMatches(source, intent.sourceTokenTrust) ||
        !_tokenTrustMatches(destination, intent.destinationTokenTrust)) {
      return null;
    }
    final funding = await _freshFunding(source, intent.sourceSelection);
    if (funding == null) return null;
    final maximum = unifiedSwapMaximumSourceAmount(
      source: intent.source,
      sourceBalance: funding.sourceBalance,
      nativeGasAsset: funding.nativeGasAsset,
      nativeGasBalance: funding.nativeGasBalance,
      // Token Max may use the full token balance only after proving at least
      // one smallest native unit is available. Exact Review caps are checked
      // again before consent can execute.
      gasReserve: '1',
      now: _now(),
    );
    if (!maximum.isAvailable) return null;
    final capability = await _runtimeCapability(
      intent.source,
      intent.destination,
      intent.sourceSelection.kind,
    );
    final decision = const UnifiedSwapCapabilityPolicy().evaluate(
      UnifiedSwapCapabilityContext(
        authenticated: true,
        walletKind: _walletKind(user),
        source: intent.source,
        destination: intent.destination,
        sourceActivated: true,
        sourceCompliance: UnifiedSwapComplianceDecision.allowed,
        destinationCompliance: UnifiedSwapComplianceDecision.allowed,
        capability: capability,
      ),
      config: config,
      forExecution: false,
    );
    return decision.isAllowed &&
            await _isSameSoftwareWallet(user.walletId.compoundId)
        ? maximum.amount
        : null;
  }

  /// Performs the SDK's chain-native validation for an exact destination.
  Future<bool> validateRecipient({
    required UnifiedSwapAssetIdentity asset,
    required String address,
  }) => _validateRecipient(asset: asset, address: address);

  Future<bool> _validateRecipient({
    required UnifiedSwapAssetIdentity asset,
    required String address,
  }) async {
    final destination = _catalogExactAsset(asset);
    if (destination == null || address.trim() != address || address.isEmpty) {
      return false;
    }
    try {
      final validation = await sdk.addresses.validateAddress(
        asset: destination,
        address: address,
      );
      return validation.isValid;
    } on Object {
      return false;
    }
  }

  Future<List<kdf.PrepareExecutionStageLimits>?> _preparationLimits({
    required UnifiedSwapIntent intent,
    required kdf.TradeRouteCandidate candidate,
  }) async {
    if (!config.canExecute || !await isIntentEligible(intent)) return null;
    final limits = <kdf.PrepareExecutionStageLimits>[];
    for (final stage in candidate.stages) {
      if (stage is! kdf.ExternalLiquidityRouteStage) continue;
      final fees = stage.common.fees;
      if (fees.isEmpty || fees.any((fee) => !fee.isExecutable)) return null;
      final networkFees = fees
          .where((fee) => fee.feeTypeValue.knownValue == kdf.FeeType.network)
          .toList(growable: false);
      if (networkFees.isEmpty) return null;
      final networkAsset = networkFees.first.asset;
      if (networkAsset.assetKind != kdf.AssetKind.native ||
          networkFees.any((fee) => !_sameRouteAsset(fee.asset, networkAsset))) {
        return null;
      }
      var quotedNetworkFee = BigInt.zero;
      for (final fee in networkFees) {
        final amount = BigInt.tryParse(fee.amount);
        if (amount == null) return null;
        quotedNetworkFee += amount;
      }
      final nonNetworkLimitsByIdentity =
          <String, ({kdf.FeeType type, kdf.RouteAsset asset, BigInt amount})>{};
      for (final fee in fees) {
        final feeType = fee.feeTypeValue.knownValue;
        if (feeType == null) return null;
        if (feeType == kdf.FeeType.network) continue;
        final amount = BigInt.tryParse(fee.amount);
        if (amount == null) return null;
        final key = _feeIdentityKey(fee.feeTypeValue.rawValue, fee.asset);
        final existing = nonNetworkLimitsByIdentity[key];
        nonNetworkLimitsByIdentity[key] = (
          type: feeType,
          asset: fee.asset,
          amount: (existing?.amount ?? BigInt.zero) + amount,
        );
      }
      final nonNetworkLimits = nonNetworkLimitsByIdentity.values
          .map(
            (fee) => kdf.FeeLimit(
              feeType: fee.type,
              asset: fee.asset,
              maxAmount: fee.amount.toString(),
            ),
          )
          .toList(growable: false);
      final cap = _ceilingRatio(
        quotedNetworkFee,
        numerator: policy.networkFeeNumerator,
        denominator: policy.networkFeeDenominator,
      );
      limits.add(
        kdf.PrepareExecutionStageLimits(
          stageId: stage.common.stageId,
          maxExpectedReceiveDegradationBps:
              policy.quietRefreshMaximumDegradationBps,
          nonNetworkFeeLimits: nonNetworkLimits,
          maxTotalNetworkFee: kdf.FeeCap(
            asset: networkAsset,
            amount: cap.toString(),
          ),
        ),
      );
    }
    return limits;
  }

  Future<UnifiedSwapRuntimeCapability?> _runtimeCapability(
    UnifiedSwapAssetIdentity source,
    UnifiedSwapAssetIdentity destination,
    UnifiedSwapSourceSelectorKind sourceSelector,
  ) async {
    final result = await _capabilities(
      tickers: [source.ticker, destination.ticker],
    );
    if (result == null) return null;
    final matches = result.capabilities
        .where((record) {
          final from = _routeAsset(record.from);
          final to = _routeAsset(record.to);
          return from != null &&
              to != null &&
              from.sameIdentity(source) &&
              to.sameIdentity(destination);
        })
        .toList(growable: false);
    if (matches.length != 1) return null;
    final record = matches.single;
    final modes = record.supportedModeValues
        .map(
          (mode) => switch (mode.knownValue) {
            kdf.ExecutionMode.signOnly => UnifiedSwapExecutionMode.signOnly,
            kdf.ExecutionMode.signAndBroadcast =>
              UnifiedSwapExecutionMode.signAndBroadcast,
            null => UnifiedSwapExecutionMode.unknown,
          },
        )
        .toList(growable: false);
    return UnifiedSwapRuntimeCapability(
      source: source,
      destination: destination,
      routeSupported: record.routeSupported,
      sourceSelector: sourceSelector,
      executor: record.executor == 'evm_eoa_v1'
          ? UnifiedSwapExecutorKind.evmSoftwareKey
          : record.executor == null
          ? UnifiedSwapExecutorKind.unknown
          : UnifiedSwapExecutorKind.unsupported,
      supportedModes: modes,
      isUnknownVariant:
          !record.providerValue.isExecutable ||
          modes.contains(UnifiedSwapExecutionMode.unknown),
    );
  }

  Future<kdf.TradeRouteCapabilitiesResult?> _capabilities({
    List<String> tickers = const [],
  }) async {
    final now = _now();
    final normalizedTickers = tickers.toSet().toList(growable: false)..sort();
    final requestKey = normalizedTickers.join('\u0000');
    var request = _capabilitiesRequest;
    if (request == null ||
        _capabilitiesRequestKey != requestKey ||
        !(_capabilitiesValidUntil?.isAfter(now) ?? false)) {
      request = _loadCapabilities(
        manager: manager,
        tickers: normalizedTickers,
      ).timeout(policy.quoteDeadline);
      _capabilitiesRequest = request;
      _capabilitiesRequestKey = requestKey;
      _capabilitiesValidUntil = now.add(const Duration(seconds: 30));
    }
    try {
      final result = await request;
      final receivedAt = _now().toUtc();
      if (result.capabilities.length > 512 ||
          result.providerMetadataAt.isAfter(receivedAt) ||
          receivedAt.difference(result.providerMetadataAt) >
              const Duration(minutes: 5)) {
        return null;
      }
      return result;
    } on Object {
      if (identical(_capabilitiesRequest, request)) {
        _capabilitiesRequest = null;
        _capabilitiesRequestKey = null;
        _capabilitiesValidUntil = null;
      }
      return null;
    }
  }

  Future<bool> _hasValidSystemClock() async {
    final check = _clockValidityCheck;
    if (check == null) return false;
    try {
      return await check().timeout(policy.executionDeadlines.control);
    } on Object {
      return false;
    }
  }

  bool _candidateCanReachReview({
    required UnifiedSwapIntent intent,
    required kdf.TradeRouteCandidate candidate,
  }) {
    for (final stage in candidate.stages) {
      if (stage is! kdf.ExternalLiquidityRouteStage) continue;
      final from = stage.common.fromAsset;
      if (from.chainFamilyValue.knownValue == kdf.ChainFamily.evm &&
          intent.source.chainFamily == UnifiedSwapChainFamily.evm &&
          from.chainId == intent.source.chainId) {
        return true;
      }
    }
    return false;
  }

  Future<KdfUser?> _currentSoftwareUser() async {
    try {
      final user = await freshKdfCurrentUser(sdk);
      if (user == null ||
          user.walletId.authOptions.privKeyPolicy !=
              const kdf.PrivateKeyPolicy.contextPrivKey()) {
        return null;
      }
      return user;
    } on Object {
      return null;
    }
  }

  Future<bool> _isSameSoftwareWallet(String walletId) async =>
      (await _currentSoftwareUser())?.walletId.compoundId == walletId;

  UnifiedSwapWalletKind _walletKind(KdfUser user) => user.isHd
      ? UnifiedSwapWalletKind.softwareHd
      : UnifiedSwapWalletKind.softwareIguana;

  Future<List<_ActivatedExactAsset>> _activatedExactAssets() async {
    try {
      final assets = await sdk.assets.getActivatedAssets();
      final exact = <_ActivatedExactAsset>[];
      for (final asset in assets) {
        final identity = _assetIdentity(asset);
        if (identity != null) {
          exact.add(_ActivatedExactAsset(asset: asset, identity: identity));
        }
      }
      return List.unmodifiable(exact);
    } on Object {
      return const [];
    }
  }

  Future<Asset?> _activatedExactAsset(
    UnifiedSwapAssetIdentity identity,
  ) async => _singleAsset(await _activatedExactAssets(), identity);

  Asset? _singleAsset(
    List<_ActivatedExactAsset> assets,
    UnifiedSwapAssetIdentity identity,
  ) {
    final matches = assets
        .where((entry) => entry.identity.sameIdentity(identity))
        .toList(growable: false);
    return matches.length == 1 ? matches.single.asset : null;
  }

  bool _isCompliant(Asset asset) {
    final service = tradingStatus;
    if (service == null) return false;
    try {
      return service.isTradingEnabled && !service.isAssetBlocked(asset.id);
    } on Object {
      return false;
    }
  }

  Future<bool> _refreshTradingEligibility(
    Asset source,
    Asset destination,
  ) async {
    final service = tradingStatus;
    if (service == null) return false;
    try {
      final status = await service.refreshStatus().timeout(
        policy.executionDeadlines.control,
      );
      return status.tradingEnabled &&
          !status.isAssetBlocked(source.id) &&
          !status.isAssetBlocked(destination.id);
    } on Object {
      return false;
    }
  }

  bool _tokenTrustMatches(Asset asset, UnifiedSwapTokenTrust claimed) {
    return claimed == _tokenTrust(asset);
  }

  Future<PubkeyInfo?> _activeAddress(Asset asset) async {
    try {
      final pubkeys = await sdk.pubkeys.refreshPubkeys(asset);
      final matches = pubkeys.keys
          .where((key) => key.isActiveForSwap)
          .toList(growable: false);
      return matches.length == 1 ? matches.single : null;
    } on Object {
      return null;
    }
  }

  Future<PubkeyInfo?> _selectedAddress(
    Asset asset,
    UnifiedSwapSourceSelection selection,
  ) async {
    try {
      final pubkeys = await sdk.pubkeys.refreshPubkeys(asset);
      final matches = switch (selection) {
        UnifiedSwapActiveSourceSelection() => pubkeys.keys.where(
          (key) => key.isActiveForSwap,
        ),
        UnifiedSwapHdPathSourceSelection(:final derivationPath) =>
          pubkeys.keys.where((key) => key.derivationPath == derivationPath),
        UnifiedSwapHdAddressSourceSelection(
          :final accountId,
          :final chain,
          :final addressId,
        ) =>
          pubkeys.keys.where(
            (key) => _matchesHdAddress(
              key.derivationPath,
              accountId: accountId,
              chain: chain,
              addressId: addressId,
            ),
          ),
        UnifiedSwapUnknownSourceSelection() =>
          const Iterable<PubkeyInfo>.empty(),
      };
      final exact = matches.toList(growable: false);
      return exact.length == 1 ? exact.single : null;
    } on Object {
      return null;
    }
  }

  Future<bool> _isWalletOwnedAddress(Asset asset, String address) async {
    return await _walletOwnedAddress(asset, address) != null;
  }

  Future<PubkeyInfo?> _walletOwnedAddress(Asset asset, String address) async {
    try {
      final pubkeys = await sdk.pubkeys.refreshPubkeys(asset);
      final matches = pubkeys.keys.where(
        (key) => _sameWalletAddress(asset, key.address, address),
      );
      return matches.length == 1 ? matches.single : null;
    } on Object {
      return null;
    }
  }

  Future<UnifiedSwapSourceSelection?> _sourceSelectionForAddress(
    Asset asset,
    String address,
  ) async {
    try {
      final pubkeys = await sdk.pubkeys.refreshPubkeys(asset);
      final owned = pubkeys.keys
          .where((key) => _sameWalletAddress(asset, key.address, address))
          .toList(growable: false);
      if (owned.length != 1) return null;
      final active = pubkeys.keys
          .where((key) => key.isActiveForSwap)
          .toList(growable: false);
      if (active.length == 1 && identical(active.single, owned.single)) {
        return const UnifiedSwapActiveSourceSelection();
      }
      final path = owned.single.derivationPath;
      return path == null ? null : UnifiedSwapHdPathSourceSelection(path);
    } on Object {
      return null;
    }
  }

  Future<_FreshFunding?> _freshFunding(
    Asset source,
    UnifiedSwapSourceSelection? selection, {
    String? expectedAddress,
  }) async {
    final sourceIdentity = _assetIdentity(source);
    if (sourceIdentity == null) return null;
    try {
      final sourcePubkeys = await sdk.pubkeys.refreshPubkeys(source);
      final sourceMatches = selection == null
          ? sourcePubkeys.keys.where(
              (key) =>
                  expectedAddress != null &&
                  _sameWalletAddress(source, key.address, expectedAddress),
            )
          : _pubkeysForSelection(sourcePubkeys.keys, selection);
      final exactSource = sourceMatches.toList(growable: false);
      if (exactSource.length != 1 ||
          (expectedAddress != null &&
              !_sameWalletAddress(
                source,
                exactSource.single.address,
                expectedAddress,
              ))) {
        return null;
      }
      final sourceAmount = _smallestUnits(
        exactSource.single.balance.spendable,
        sourceIdentity,
      );
      if (sourceAmount == null) return null;
      final observedAt = _now();
      final sourceBalance = UnifiedSwapBalanceSnapshot(
        asset: sourceIdentity,
        amount: sourceAmount,
        observedAt: observedAt,
        validUntil: observedAt.add(_freshFundingLifetime),
      );
      if (sourceIdentity.kind == UnifiedSwapAssetKind.native) {
        return _FreshFunding(
          sourceAddress: exactSource.single,
          sourceBalance: sourceBalance,
          nativeGasAsset: sourceIdentity,
          nativeGasBalance: sourceBalance,
        );
      }

      final activated = await _activatedExactAssets();
      final nativeMatches = activated
          .where(
            (entry) =>
                entry.identity.chainFamily == UnifiedSwapChainFamily.evm &&
                entry.identity.chainId == sourceIdentity.chainId &&
                entry.identity.kind == UnifiedSwapAssetKind.native,
          )
          .toList(growable: false);
      if (nativeMatches.length != 1) return null;
      final nativePubkeys = await sdk.pubkeys.refreshPubkeys(
        nativeMatches.single.asset,
      );
      final addressMatches = nativePubkeys.keys
          .where(
            (key) => _sameWalletAddress(
              nativeMatches.single.asset,
              key.address,
              exactSource.single.address,
            ),
          )
          .toList(growable: false);
      if (addressMatches.length != 1) return null;
      final gasAmount = _smallestUnits(
        addressMatches.single.balance.spendable,
        nativeMatches.single.identity,
      );
      if (gasAmount == null) return null;
      final gasObservedAt = _now();
      return _FreshFunding(
        sourceAddress: exactSource.single,
        sourceBalance: sourceBalance,
        nativeGasAsset: nativeMatches.single.identity,
        nativeGasBalance: UnifiedSwapBalanceSnapshot(
          asset: nativeMatches.single.identity,
          amount: gasAmount,
          observedAt: gasObservedAt,
          validUntil: gasObservedAt.add(_freshFundingLifetime),
        ),
      );
    } on Object {
      return null;
    }
  }

  Future<bool> _isWalletOwnedDestinationAddress({
    required Asset destination,
    required UnifiedSwapAssetIdentity identity,
    required String address,
    required List<_ActivatedExactAsset> activated,
  }) async {
    final activeDestination = _singleAsset(activated, identity);
    if (activeDestination != null) {
      return _isWalletOwnedAddress(activeDestination, address);
    }
    if (identity.chainFamily != UnifiedSwapChainFamily.evm) return false;
    final checked = <AssetId>{};
    for (final entry in activated) {
      if (entry.identity.chainFamily != UnifiedSwapChainFamily.evm ||
          !checked.add(entry.asset.id)) {
        continue;
      }
      if (await _isWalletOwnedAddress(entry.asset, address)) return true;
    }
    return false;
  }

  Future<String?> _recipientForSelection({
    required UnifiedSwapAssetIdentity destination,
    required String sourceAddress,
    String? preferredRecipient,
  }) async {
    if (preferredRecipient != null &&
        await _validateRecipient(
          asset: destination,
          address: preferredRecipient,
        )) {
      return preferredRecipient;
    }
    if (destination.chainFamily == UnifiedSwapChainFamily.evm &&
        await _validateRecipient(asset: destination, address: sourceAddress)) {
      return sourceAddress;
    }
    final activatedDestination = await _activatedExactAsset(destination);
    final activeAddress = activatedDestination == null
        ? null
        : await _activeAddress(activatedDestination);
    if (activeAddress != null &&
        await _validateRecipient(
          asset: destination,
          address: activeAddress.address,
        )) {
      return activeAddress.address;
    }
    return null;
  }

  Asset? _catalogExactAsset(UnifiedSwapAssetIdentity identity) {
    try {
      final matches = sdk.assets.available.values
          .where((asset) => _assetMatchesIdentity(asset, identity))
          .toList(growable: false);
      return matches.length == 1 ? matches.single : null;
    } on Object {
      return null;
    }
  }

  String? _reviewGasReserve(
    RouteExecutionReview review,
    UnifiedSwapAssetIdentity nativeGasAsset,
  ) {
    final caps = review.networkFeeCaps
        .where(
          (cap) =>
              cap.asset.chainFamily == review.source.chainFamily &&
              cap.asset.chainId == review.source.chainId,
        )
        .toList(growable: false);
    if (caps.isEmpty ||
        caps.any((cap) => !cap.asset.sameIdentity(nativeGasAsset))) {
      return null;
    }
    var total = BigInt.zero;
    for (final cap in caps) {
      final amount = BigInt.tryParse(cap.maximumAmount);
      if (amount == null) return null;
      total += amount;
    }
    return total.toString();
  }

  List<UnifiedSwapRoutePair> _preferredPairs(
    UnifiedSwapSelectionInventory inventory,
    UnifiedSwapLegacyHints hints,
  ) {
    var pairs = List<UnifiedSwapRoutePair>.of(inventory.pairs);
    final source = _unambiguousTickerOption(
      inventory.sources,
      hints.sourceAsset,
    );
    if (source != null) {
      pairs = pairs
          .where((pair) => pair.source.sameIdentity(source.identity))
          .toList();
    }
    final destinations = pairs
        .map((pair) => inventory.destinationOption(pair.destination))
        .whereType<UnifiedSwapAssetOption>()
        .toList(growable: false);
    final destination = _unambiguousTickerOption(
      destinations,
      hints.destinationAsset,
    );
    if (destination != null) {
      pairs = pairs
          .where((pair) => pair.destination.sameIdentity(destination.identity))
          .toList();
    }
    final preferred = pairs.toSet();
    return List.unmodifiable([
      ...pairs,
      ...inventory.pairs.where((pair) => !preferred.contains(pair)),
    ]);
  }

  UnifiedSwapAssetOption? _unambiguousTickerOption(
    List<UnifiedSwapAssetOption> options,
    String? hint,
  ) {
    if (hint == null) return null;
    final normalized = hint.toUpperCase();
    final matches = options
        .where((option) => option.identity.ticker.toUpperCase() == normalized)
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }
}

const _freshFundingLifetime = Duration(seconds: 15);

final class _FreshFunding {
  const _FreshFunding({
    required this.sourceAddress,
    required this.sourceBalance,
    required this.nativeGasAsset,
    required this.nativeGasBalance,
  });

  final PubkeyInfo sourceAddress;
  final UnifiedSwapBalanceSnapshot sourceBalance;
  final UnifiedSwapAssetIdentity nativeGasAsset;
  final UnifiedSwapBalanceSnapshot? nativeGasBalance;
}

UnifiedSwapSourceSelection? _selectionForKind(
  UnifiedSwapSourceSelectorKind kind,
) => switch (kind) {
  UnifiedSwapSourceSelectorKind.active =>
    const UnifiedSwapActiveSourceSelection(),
  UnifiedSwapSourceSelectorKind.hd ||
  UnifiedSwapSourceSelectorKind.unknown => null,
};

Iterable<PubkeyInfo> _pubkeysForSelection(
  Iterable<PubkeyInfo> pubkeys,
  UnifiedSwapSourceSelection selection,
) => switch (selection) {
  UnifiedSwapActiveSourceSelection() => pubkeys.where(
    (key) => key.isActiveForSwap,
  ),
  UnifiedSwapHdPathSourceSelection(:final derivationPath) => pubkeys.where(
    (key) => key.derivationPath == derivationPath,
  ),
  UnifiedSwapHdAddressSourceSelection(
    :final accountId,
    :final chain,
    :final addressId,
  ) =>
    pubkeys.where(
      (key) => _matchesHdAddress(
        key.derivationPath,
        accountId: accountId,
        chain: chain,
        addressId: addressId,
      ),
    ),
  UnifiedSwapUnknownSourceSelection() => const <PubkeyInfo>[],
};

bool _pubkeyMatchesSelector(
  PubkeyInfo pubkey,
  UnifiedSwapSourceSelectorKind kind,
) => switch (kind) {
  UnifiedSwapSourceSelectorKind.active => pubkey.isActiveForSwap,
  UnifiedSwapSourceSelectorKind.hd => pubkey.derivationPath != null,
  UnifiedSwapSourceSelectorKind.unknown => false,
};

bool _sameWalletAddress(Asset asset, String left, String right) =>
    asset.protocol is Erc20Protocol
    ? _isExactEvmAddress(left) &&
          _isExactEvmAddress(right) &&
          left.toLowerCase() == right.toLowerCase()
    : left == right;

bool _isExactEvmAddress(String value) =>
    RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value);

final class _ActivatedExactAsset {
  const _ActivatedExactAsset({required this.asset, required this.identity});

  final Asset asset;
  final UnifiedSwapAssetIdentity identity;
}

UnifiedSwapAssetIdentity? _assetIdentity(Asset asset) {
  if (asset.protocol is! Erc20Protocol) return null;
  final chainId = asset.id.chainId.formattedChainId;
  final decimals = asset.id.chainId.decimals;
  if (!RegExp(r'^[1-9][0-9]*$').hasMatch(chainId) || decimals == null) {
    return null;
  }
  final contract = asset.protocol.contractAddress;
  final identity = UnifiedSwapAssetIdentity(
    ticker: asset.id.id,
    chainFamily: UnifiedSwapChainFamily.evm,
    chainId: chainId,
    kind: contract == null
        ? UnifiedSwapAssetKind.native
        : UnifiedSwapAssetKind.token,
    decimals: decimals,
    contractAddress: contract,
  );
  return identity.isValidEvmV1 ? identity : null;
}

bool _assetMatchesIdentity(Asset asset, UnifiedSwapAssetIdentity identity) {
  final evm = _assetIdentity(asset);
  if (evm != null) return evm.sameIdentity(identity);
  if (asset.protocol is! UtxoProtocol ||
      identity.chainFamily != UnifiedSwapChainFamily.utxo ||
      identity.kind != UnifiedSwapAssetKind.native ||
      identity.contractAddress != null ||
      asset.id.id != identity.ticker ||
      asset.id.chainId.decimals != identity.decimals) {
    return false;
  }
  final reviewedChainId = switch (asset.id.id) {
    'BTC' => 'bitcoin-mainnet',
    'KMD' => 'komodo-mainnet',
    _ => null,
  };
  return reviewedChainId == identity.chainId;
}

UnifiedSwapTokenTrust _tokenTrust(Asset asset) => asset.protocol.isCustomToken
    ? UnifiedSwapTokenTrust.unknown
    : UnifiedSwapTokenTrust.trusted;

void _addUniqueOption(
  List<UnifiedSwapAssetOption> options,
  UnifiedSwapAssetOption option,
) {
  if (!options.any(
    (existing) => existing.identity.sameIdentity(option.identity),
  )) {
    options.add(option);
  }
}

void _sortAssetOptions(List<UnifiedSwapAssetOption> options) {
  options.sort((left, right) {
    final ticker = left.identity.ticker.compareTo(right.identity.ticker);
    if (ticker != 0) return ticker;
    final family = left.identity.chainFamily.name.compareTo(
      right.identity.chainFamily.name,
    );
    if (family != 0) return family;
    final chain = left.identity.chainId.compareTo(right.identity.chainId);
    if (chain != 0) return chain;
    return (left.identity.contractAddress ?? '').compareTo(
      right.identity.contractAddress ?? '',
    );
  });
}

int _compareRoutePairs(UnifiedSwapRoutePair left, UnifiedSwapRoutePair right) {
  final source = _compareAssetIdentity(left.source, right.source);
  return source != 0
      ? source
      : _compareAssetIdentity(left.destination, right.destination);
}

int _compareAssetIdentity(
  UnifiedSwapAssetIdentity left,
  UnifiedSwapAssetIdentity right,
) {
  final ticker = left.ticker.compareTo(right.ticker);
  if (ticker != 0) return ticker;
  final family = left.chainFamily.name.compareTo(right.chainFamily.name);
  if (family != 0) return family;
  final chain = left.chainId.compareTo(right.chainId);
  if (chain != 0) return chain;
  return (left.contractAddress ?? '').compareTo(right.contractAddress ?? '');
}

String? _normalizedAddressLabel(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

UnifiedSwapAssetIdentity? _routeAsset(kdf.RouteAsset asset) {
  final identity = UnifiedSwapAssetIdentity(
    ticker: asset.ticker,
    chainFamily: switch (asset.chainFamilyValue.knownValue) {
      kdf.ChainFamily.evm => UnifiedSwapChainFamily.evm,
      kdf.ChainFamily.tvm => UnifiedSwapChainFamily.tron,
      kdf.ChainFamily.utxo => UnifiedSwapChainFamily.utxo,
      kdf.ChainFamily.svm => UnifiedSwapChainFamily.solana,
      kdf.ChainFamily.sui => UnifiedSwapChainFamily.sui,
      kdf.ChainFamily.mvm => UnifiedSwapChainFamily.other,
      null => UnifiedSwapChainFamily.unknown,
    },
    chainId: asset.chainId,
    kind: switch (asset.assetKindValue.knownValue) {
      kdf.AssetKind.native => UnifiedSwapAssetKind.native,
      kdf.AssetKind.token => UnifiedSwapAssetKind.token,
      null => UnifiedSwapAssetKind.unknown,
    },
    decimals: asset.decimals,
    contractAddress: asset.contractAddress,
    rawChainFamilyDiscriminator: asset.chainFamilyValue.isKnown
        ? null
        : asset.chainFamilyValue.rawValue,
    rawKindDiscriminator: asset.assetKindValue.isKnown
        ? null
        : asset.assetKindValue.rawValue,
  );
  return identity.chainFamily == UnifiedSwapChainFamily.unknown ||
          identity.kind == UnifiedSwapAssetKind.unknown
      ? null
      : identity;
}

bool _isExecutableCapability(kdf.CapabilityRecord record) =>
    record.isExecutable &&
    record.executor == 'evm_eoa_v1' &&
    record.supportedModeValues.any(
      (mode) => mode.knownValue == kdf.ExecutionMode.signAndBroadcast,
    );

bool _sameRouteAsset(kdf.RouteAsset left, kdf.RouteAsset right) =>
    left.ticker == right.ticker &&
    left.chainFamilyValue.rawValue == right.chainFamilyValue.rawValue &&
    left.chainId == right.chainId &&
    left.assetKindValue.rawValue == right.assetKindValue.rawValue &&
    _routeContractIdentity(left) == _routeContractIdentity(right) &&
    left.decimals == right.decimals;

String _feeIdentityKey(String feeType, kdf.RouteAsset asset) => jsonEncode([
  feeType,
  asset.ticker,
  asset.chainFamilyValue.rawValue,
  asset.chainId,
  asset.assetKindValue.rawValue,
  _routeContractIdentity(asset),
  asset.decimals,
]);

String? _routeContractIdentity(kdf.RouteAsset asset) {
  final value = asset.contractAddress;
  if (asset.chainFamilyValue.knownValue == kdf.ChainFamily.evm &&
      value != null &&
      RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value)) {
    return value.toLowerCase();
  }
  return value;
}

bool _matchesHdAddress(
  String? derivationPath, {
  required int accountId,
  required UnifiedSwapHdChain chain,
  required int addressId,
}) {
  if (derivationPath == null || chain == UnifiedSwapHdChain.unknown) {
    return false;
  }
  final segments = derivationPath.split('/');
  if (segments.length < 4) return false;
  final parsedAddress = int.tryParse(segments.last.replaceAll("'", ''));
  final parsedChain = int.tryParse(
    segments[segments.length - 2].replaceAll("'", ''),
  );
  final parsedAccount = int.tryParse(
    segments[segments.length - 3].replaceAll("'", ''),
  );
  final expectedChain = chain == UnifiedSwapHdChain.external ? 0 : 1;
  return parsedAccount == accountId &&
      parsedChain == expectedChain &&
      parsedAddress == addressId;
}

String? _smallestUnits(Decimal amount, UnifiedSwapAssetIdentity asset) {
  if (amount < Decimal.zero || asset.decimals < 0) return null;
  final shifted = amount.shift(asset.decimals);
  if (!shifted.isInteger) return null;
  return shifted.toBigInt().toString();
}

BigInt _ceilingRatio(
  BigInt value, {
  required int numerator,
  required int denominator,
}) {
  if (numerator <= 0 || denominator <= 0) {
    throw ArgumentError('Fee ratio must be positive');
  }
  final divisor = BigInt.from(denominator);
  return (value * BigInt.from(numerator) + divisor - BigInt.one) ~/ divisor;
}

DateTime _utcNow() => DateTime.now().toUtc();
