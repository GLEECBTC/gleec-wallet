import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/system_health/system_clock_repository.dart';
import 'package:web_dex/bloc/trading_status/trading_status_service.dart';
import 'package:web_dex/features/unified_swap/application/route_activity_bloc.dart';
import 'package:web_dex/features/unified_swap/application/route_execution_bloc.dart';
import 'package:web_dex/features/unified_swap/application/unified_swap_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_route_activity_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_route_execution_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_quote_repository.dart';
import 'package:web_dex/features/unified_swap/infrastructure/kdf_unified_swap_review_coordinator.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_production_composition.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_sensitive_dialog.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/router/state/unified_swap_section_state.dart';
import 'package:web_dex/shared/utils/kdf_wallet_authority.dart';

typedef UnifiedSwapCurrentWalletId = Future<String?> Function();
typedef UnifiedSwapQuoteRepositoryFactory =
    KdfUnifiedSwapQuoteRepository Function({
      required String walletId,
      required TradeRouteManager manager,
      required UnifiedSwapCurrentWalletId currentWalletId,
    });
typedef UnifiedSwapInitialIntentResolver =
    Future<UnifiedSwapIntent?> Function();

/// Resolves the app's shared SDK without making router/widget tests depend on
/// production composition. Missing or uninitialized SDK state fails closed.
class UnifiedSwapSdkScope extends StatelessWidget {
  const UnifiedSwapSdkScope({
    required this.child,
    this.config = const UnifiedSwapConfig(),
    this.capabilitiesLoader,
    this.quoteRepositoryFactory,
    this.executionEligibilityCheck,
    this.routeExecutionId,
    super.key,
  });

  final Widget child;
  final UnifiedSwapConfig config;
  final UnifiedSwapCapabilitiesLoader? capabilitiesLoader;
  final UnifiedSwapQuoteRepositoryFactory? quoteRepositoryFactory;
  final UnifiedSwapExecutionEligibilityCheck? executionEligibilityCheck;
  final UnifiedSwapRouteExecutionIdFactory? routeExecutionId;

  @override
  Widget build(BuildContext context) {
    try {
      final sdk = RepositoryProvider.of<KomodoDefiSdk>(context);
      final coinsBloc = _maybeRepository<CoinsBloc>(context);
      final clockRepository = _maybeRepository<SystemClockRepository>(context);
      final production = UnifiedSwapProductionComposition(
        sdk: sdk,
        manager: sdk.tradeRoutes,
        config: config,
        loadCapabilities: capabilitiesLoader ?? _loadCapabilities,
        valuationSnapshot: () => _valuationSnapshot(sdk, coinsBloc?.state),
        clockValidityCheck: () =>
            clockRepository?.isSystemClockValid(failClosed: true) ??
            Future<bool>.value(false),
        tradingStatus: _maybeRepository<TradingStatusService>(context),
      );
      final analytics = UnifiedSwapAnalyticsCoordinator(
        analytics: _maybeRepository<AnalyticsBloc>(context),
      );
      final coinsRepository = _maybeRepository<CoinsRepo>(context);
      final scoped = UnifiedSwapWalletScope(
        key: ObjectKey(sdk),
        currentWalletId: () => freshKdfCurrentWalletId(sdk),
        walletIds: sdk.auth.watchCurrentUser().map(
          (user) => user?.walletId.compoundId,
        ),
        manager: sdk.tradeRoutes,
        quoteRepositoryFactory:
            quoteRepositoryFactory ??
            ({required walletId, required manager, required currentWalletId}) =>
                production.quoteRepository(
                  walletId,
                  currentWalletId: currentWalletId,
                ),
        initialIntentResolver: () {
          final hints = routingState.unifiedSwapState.value.legacyHints;
          return production.initialIntent(
            legacyHints: UnifiedSwapLegacyHints(
              sourceAsset: hints.sourceAsset,
              destinationAsset: hints.destinationAsset,
            ),
          );
        },
        initialIntentRefreshes: coinsRepository?.enabledAssetsChanges.stream
            .where((coin) => coin.isActive)
            .map<void>((_) {}),
        analyticsCoordinator: analytics,
        executionEligibilityCheck:
            executionEligibilityCheck ?? production.isReviewEligible,
        executionDeadlines: production.policy.executionDeadlines,
        routeExecutionId: routeExecutionId,
        child: child,
      );
      return MultiRepositoryProvider(
        providers: [
          RepositoryProvider<UnifiedSwapProductionComposition>.value(
            value: production,
          ),
          RepositoryProvider<UnifiedSwapProductionPolicy>.value(
            value: production.policy,
          ),
          RepositoryProvider<UnifiedSwapCapabilityPolicy>.value(
            value: const UnifiedSwapCapabilityPolicy(),
          ),
          RepositoryProvider<UnifiedSwapAnalyticsCoordinator>.value(
            value: analytics,
          ),
        ],
        child: scoped,
      );
    } on Object {
      return child;
    }
  }
}

/// Owns wallet-scoped Activity and execution state while keeping the SDK's
/// [TradeRouteManager] shared. Replacing or signing out a wallet destroys every
/// local review/task binding, rebuilds Activity from KDF, and never disposes or
/// cancels a backend route.
class UnifiedSwapWalletScope extends StatefulWidget {
  const UnifiedSwapWalletScope({
    required this.currentWalletId,
    required this.walletIds,
    required this.manager,
    required this.child,
    this.quoteRepositoryFactory,
    this.initialIntentResolver,
    this.initialIntentRefreshes,
    this.analyticsCoordinator,
    this.executionEligibilityCheck,
    this.executionDeadlines = const KdfRouteExecutionDeadlines(),
    this.routeExecutionId,
    super.key,
  });

  final UnifiedSwapCurrentWalletId currentWalletId;
  final Stream<String?> walletIds;
  final TradeRouteManager manager;
  final Widget child;
  final UnifiedSwapQuoteRepositoryFactory? quoteRepositoryFactory;
  final UnifiedSwapInitialIntentResolver? initialIntentResolver;
  final Stream<void>? initialIntentRefreshes;
  final UnifiedSwapAnalyticsCoordinator? analyticsCoordinator;
  final UnifiedSwapExecutionEligibilityCheck? executionEligibilityCheck;
  final KdfRouteExecutionDeadlines executionDeadlines;
  final UnifiedSwapRouteExecutionIdFactory? routeExecutionId;

  @override
  State<UnifiedSwapWalletScope> createState() => _UnifiedSwapWalletScopeState();
}

class _UnifiedSwapWalletScopeState extends State<UnifiedSwapWalletScope> {
  final UnifiedSwapSensitiveDialogController _sensitiveDialogController =
      UnifiedSwapSensitiveDialogController();
  StreamSubscription<String?>? _walletSubscription;
  StreamSubscription<void>? _initialIntentRefreshSubscription;
  RouteActivityBloc? _activityBloc;
  RouteExecutionBloc? _executionBloc;
  UnifiedSwapBloc? _quoteBloc;
  KdfRouteExecutionRepository? _executionRepository;
  KdfUnifiedSwapReviewCoordinator? _reviewCoordinator;
  int _identityGeneration = 0;
  int _walletGeneration = 0;
  String? _walletId;
  Future<void>? _intentSeedTask;
  bool _intentSeedAgain = false;
  bool _intentSeeded = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final initialGeneration = _identityGeneration;
    unawaited(
      widget
          .currentWalletId()
          .then((walletId) {
            if (mounted && _identityGeneration == initialGeneration) {
              _queueWallet(walletId);
            }
          })
          .onError((_, _) {
            if (mounted && _identityGeneration == initialGeneration) {
              _queueWallet(null);
            }
          }),
    );
    _walletSubscription = widget.walletIds.listen(
      (walletId) {
        if (_disposed || !mounted) return;
        _identityGeneration++;
        _queueWallet(walletId);
      },
      onError: (_, _) {
        if (_disposed || !mounted) return;
        _identityGeneration++;
        _queueWallet(null);
      },
      onDone: () {
        if (_disposed || !mounted) return;
        _identityGeneration++;
        _queueWallet(null);
      },
    );
    _initialIntentRefreshSubscription = widget.initialIntentRefreshes?.listen(
      (_) => _requestIntentSeed(),
      onError: (_, _) {},
    );
  }

  void _queueWallet(String? walletId) {
    if (_disposed || !mounted) return;
    _sensitiveDialogController.invalidate();
    final generation = ++_walletGeneration;
    unawaited(
      _replaceWallet(_normalizedWalletId(walletId), generation).onError((_, _) {
        if (mounted && generation == _walletGeneration) {
          setState(() {
            _walletId = null;
            _activityBloc = null;
            _executionBloc = null;
            _quoteBloc = null;
            _executionRepository = null;
            _reviewCoordinator = null;
          });
        }
      }),
    );
  }

  Future<void> _replaceWallet(String? walletId, int generation) async {
    final oldActivityBloc = _activityBloc;
    final oldExecutionBloc = _executionBloc;
    final oldQuoteBloc = _quoteBloc;
    final oldExecutionRepository = _executionRepository;
    _activityBloc = null;
    _executionBloc = null;
    _quoteBloc = null;
    _executionRepository = null;
    _reviewCoordinator = null;
    _walletId = null;
    _intentSeedAgain = false;
    _intentSeeded = false;

    RouteActivityBloc? activityBloc;
    RouteExecutionBloc? executionBloc;
    UnifiedSwapBloc? quoteBloc;
    KdfRouteExecutionRepository? executionRepository;
    KdfUnifiedSwapReviewCoordinator? reviewCoordinator;
    Future<String?> scopedCurrentWalletId() async {
      if (!mounted || generation != _walletGeneration) return null;
      final currentWalletId = _normalizedWalletId(
        await widget.currentWalletId(),
      );
      if (!mounted || generation != _walletGeneration) return null;
      return currentWalletId;
    }

    try {
      if (!mounted || generation != _walletGeneration) return;
      if (walletId != null) {
        final activityRepository = KdfRouteActivityRepository(
          manager: widget.manager,
          walletId: walletId,
          currentWalletId: scopedCurrentWalletId,
        );
        executionRepository = KdfRouteExecutionRepository(
          walletId: walletId,
          manager: widget.manager,
          currentWalletId: scopedCurrentWalletId,
          executionEligibilityCheck: widget.executionEligibilityCheck,
          deadlines: widget.executionDeadlines,
        );
        activityBloc = RouteActivityBloc(repository: activityRepository)
          ..add(RouteActivityWalletChanged(walletId));
        final quoteRepository = widget.quoteRepositoryFactory?.call(
          walletId: walletId,
          manager: widget.manager,
          currentWalletId: scopedCurrentWalletId,
        );
        if (quoteRepository != null) {
          quoteBloc = UnifiedSwapBloc(quoteRepository: quoteRepository)
            ..add(UnifiedSwapWalletChanged(walletId));
          reviewCoordinator = KdfUnifiedSwapReviewCoordinator(
            quoteRepository: quoteRepository,
            executionRepository: executionRepository,
            routeExecutionId: widget.routeExecutionId,
          );
        }
        executionBloc = RouteExecutionBloc(
          repository: executionRepository,
          acceptanceCoordinator: reviewCoordinator,
        )..add(RouteExecutionWalletChanged(walletId));
      }
      if (!mounted || generation != _walletGeneration) {
        await activityBloc?.close();
        await executionBloc?.close();
        await quoteBloc?.close();
        executionRepository?.dispose();
        return;
      }
      setState(() {
        _walletId = walletId;
        _activityBloc = activityBloc;
        _executionBloc = executionBloc;
        _quoteBloc = quoteBloc;
        _executionRepository = executionRepository;
        _reviewCoordinator = reviewCoordinator;
      });
      _requestIntentSeed();
    } catch (_) {
      await activityBloc?.close();
      await executionBloc?.close();
      await quoteBloc?.close();
      executionRepository?.dispose();
      rethrow;
    } finally {
      await oldActivityBloc?.close();
      await oldExecutionBloc?.close();
      await oldQuoteBloc?.close();
      oldExecutionRepository?.dispose();
    }
  }

  void _requestIntentSeed() {
    final bloc = _quoteBloc;
    if (bloc == null ||
        _walletId == null ||
        widget.initialIntentResolver == null ||
        _intentSeeded ||
        bloc.state.intent != null) {
      return;
    }
    if (_intentSeedTask != null) {
      _intentSeedAgain = true;
      return;
    }
    final generation = _walletGeneration;
    late final Future<void> task;
    task = _seedIntent(bloc, generation);
    _intentSeedTask = task;
    unawaited(
      task.whenComplete(() {
        if (!identical(_intentSeedTask, task)) return;
        _intentSeedTask = null;
        if (_intentSeedAgain) {
          _intentSeedAgain = false;
          _requestIntentSeed();
        }
      }),
    );
  }

  Future<void> _seedIntent(UnifiedSwapBloc bloc, int generation) async {
    try {
      final intent = await widget.initialIntentResolver?.call();
      if (!mounted ||
          generation != _walletGeneration ||
          !identical(_quoteBloc, bloc) ||
          intent == null) {
        return;
      }
      _intentSeeded = true;
      _intentSeedAgain = false;
      bloc.add(UnifiedSwapIntentSeeded(intent));
    } on Object {
      // Missing or changing wallet dependencies leave the entry state inert.
    }
  }

  Future<void> _disposeWalletBindings() async {
    final activityBloc = _activityBloc;
    final executionBloc = _executionBloc;
    final quoteBloc = _quoteBloc;
    final executionRepository = _executionRepository;
    _activityBloc = null;
    _executionBloc = null;
    _quoteBloc = null;
    _executionRepository = null;
    _reviewCoordinator = null;
    _walletId = null;
    await activityBloc?.close();
    await executionBloc?.close();
    await quoteBloc?.close();
    executionRepository?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _identityGeneration++;
    _walletGeneration++;
    _sensitiveDialogController.invalidate();
    unawaited(_walletSubscription?.cancel());
    unawaited(_initialIntentRefreshSubscription?.cancel());
    unawaited(_disposeWalletBindings());
    _sensitiveDialogController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activityBloc = _activityBloc;
    final executionBloc = _executionBloc;
    if (activityBloc == null || executionBloc == null) {
      return UnifiedSwapSensitiveDialogScope(
        controller: _sensitiveDialogController,
        child: widget.child,
      );
    }
    final quoteBloc = _quoteBloc;
    final reviewCoordinator = _reviewCoordinator;
    Widget walletChild = widget.child;
    final analytics = widget.analyticsCoordinator;
    if (analytics != null) {
      walletChild = BlocListener<RouteExecutionBloc, RouteExecutionState>(
        bloc: executionBloc,
        listenWhen: (previous, current) =>
            previous.progress?.routeExecutionId !=
                current.progress?.routeExecutionId ||
            previous.progress?.outcome != current.progress?.outcome,
        listener: (_, state) => analytics.record(state.progress),
        child: walletChild,
      );
    }
    Widget child = MultiBlocProvider(
      key: ValueKey<int>(
        Object.hash('unified-swap-wallet-scope', _walletId, _walletGeneration),
      ),
      providers: [
        BlocProvider<RouteActivityBloc>.value(value: activityBloc),
        BlocProvider<RouteExecutionBloc>.value(value: executionBloc),
        if (quoteBloc != null)
          BlocProvider<UnifiedSwapBloc>.value(value: quoteBloc),
      ],
      child: walletChild,
    );
    if (reviewCoordinator != null) {
      child = RepositoryProvider<KdfUnifiedSwapReviewCoordinator>.value(
        value: reviewCoordinator,
        child: child,
      );
    }
    return UnifiedSwapSensitiveDialogScope(
      controller: _sensitiveDialogController,
      child: child,
    );
  }
}

String? _normalizedWalletId(String? walletId) {
  final value = walletId?.trim();
  return value == null || value.isEmpty ? null : value;
}

Future<kdf.TradeRouteCapabilitiesResult> _loadCapabilities({
  required TradeRouteManager manager,
  required List<String> tickers,
}) => manager.capabilities(tickers: tickers);

T? _maybeRepository<T>(BuildContext context) {
  try {
    return context.read<T>();
  } on Object {
    return null;
  }
}

kdf.ValuationSnapshot? _valuationSnapshot(
  KomodoDefiSdk sdk,
  CoinsState? state,
) {
  if (state == null) return null;
  final now = DateTime.timestamp().toUtc();
  final prices = <kdf.AssetValuationPrice>[];
  DateTime? oldestObservation;
  for (final cexPrice in state.prices.values) {
    final price = cexPrice.price;
    if (price == null || price <= Decimal.zero) continue;
    final asset = sdk.assets.available[cexPrice.assetId];
    if (asset == null || asset.protocol is! Erc20Protocol) continue;
    final chainId = asset.id.chainId.formattedChainId;
    final decimals = asset.id.chainId.decimals;
    if (decimals == null || !RegExp(r'^[1-9][0-9]*$').hasMatch(chainId)) {
      continue;
    }
    final contract = (asset.protocol as Erc20Protocol).contractAddress;
    final observedAt = cexPrice.lastUpdated.toUtc();
    if (observedAt.isAfter(now)) continue;
    oldestObservation =
        oldestObservation == null || observedAt.isBefore(oldestObservation)
        ? observedAt
        : oldestObservation;
    prices.add(
      kdf.AssetValuationPrice(
        asset: kdf.RouteAsset(
          ticker: asset.id.id,
          chainFamily: kdf.ChainFamily.evm,
          chainId: chainId,
          assetKind: contract == null
              ? kdf.AssetKind.native
              : kdf.AssetKind.token,
          contractAddress: contract,
          decimals: decimals,
        ),
        price: price.toString(),
        observedAt: observedAt,
      ),
    );
  }
  if (prices.isEmpty || oldestObservation == null) return null;
  final validUntil = oldestObservation.add(const Duration(minutes: 5));
  if (!validUntil.isAfter(now)) return null;
  return kdf.ValuationSnapshot(
    currency: kdf.ValuationCurrency.usd,
    source: kdf.ValuationSource.walletMarketData,
    observedAt: oldestObservation,
    validUntil: validUntil,
    prices: prices,
  );
}
