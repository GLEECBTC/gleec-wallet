import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart' as kdf;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
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
import 'package:web_dex/router/state/routing_state.dart';

typedef UnifiedSwapCurrentWalletId = Future<String?> Function();
typedef UnifiedSwapQuoteRepositoryFactory =
    KdfUnifiedSwapQuoteRepository Function({
      required String walletId,
      required TradeRouteManager manager,
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
      final production = UnifiedSwapProductionComposition(
        sdk: sdk,
        manager: sdk.tradeRoutes,
        config: config,
        loadCapabilities: capabilitiesLoader ?? _loadCapabilities,
        tradingStatus: _maybeRepository<TradingStatusService>(context),
      );
      final analytics = UnifiedSwapAnalyticsCoordinator(
        analytics: _maybeRepository<AnalyticsBloc>(context),
      );
      final scoped = UnifiedSwapWalletScope(
        key: ObjectKey(sdk),
        currentWalletId: () async =>
            (await sdk.auth.currentUser)?.walletId.compoundId,
        walletIds: sdk.auth
            .watchCurrentUser()
            .map((user) => user?.walletId.compoundId)
            .distinct(),
        manager: sdk.tradeRoutes,
        quoteRepositoryFactory:
            quoteRepositoryFactory ??
            ({required walletId, required manager}) =>
                production.quoteRepository(walletId),
        initialIntentResolver: () => production.initialIntent(
          legacyHints: routingState.unifiedSwapState.value.legacyHints,
        ),
        analyticsCoordinator: analytics,
        executionEligibilityCheck:
            executionEligibilityCheck ?? production.isReviewEligible,
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
    this.analyticsCoordinator,
    this.executionEligibilityCheck,
    this.routeExecutionId,
    super.key,
  });

  final UnifiedSwapCurrentWalletId currentWalletId;
  final Stream<String?> walletIds;
  final TradeRouteManager manager;
  final Widget child;
  final UnifiedSwapQuoteRepositoryFactory? quoteRepositoryFactory;
  final UnifiedSwapInitialIntentResolver? initialIntentResolver;
  final UnifiedSwapAnalyticsCoordinator? analyticsCoordinator;
  final UnifiedSwapExecutionEligibilityCheck? executionEligibilityCheck;
  final UnifiedSwapRouteExecutionIdFactory? routeExecutionId;

  @override
  State<UnifiedSwapWalletScope> createState() => _UnifiedSwapWalletScopeState();
}

class _UnifiedSwapWalletScopeState extends State<UnifiedSwapWalletScope> {
  StreamSubscription<String?>? _walletSubscription;
  RouteActivityBloc? _activityBloc;
  RouteExecutionBloc? _executionBloc;
  UnifiedSwapBloc? _quoteBloc;
  KdfRouteExecutionRepository? _executionRepository;
  KdfUnifiedSwapReviewCoordinator? _reviewCoordinator;
  int _identityGeneration = 0;
  int _walletGeneration = 0;
  String? _walletId;

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
        _identityGeneration++;
        _queueWallet(walletId);
      },
      onError: (_, _) {
        _identityGeneration++;
        _queueWallet(null);
      },
    );
  }

  void _queueWallet(String? walletId) {
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
    if (walletId == _walletId && _activityBloc != null) return;
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

    RouteActivityBloc? activityBloc;
    RouteExecutionBloc? executionBloc;
    UnifiedSwapBloc? quoteBloc;
    KdfRouteExecutionRepository? executionRepository;
    KdfUnifiedSwapReviewCoordinator? reviewCoordinator;
    try {
      if (!mounted || generation != _walletGeneration) return;
      if (walletId != null) {
        final activityRepository = KdfRouteActivityRepository(
          manager: widget.manager,
          walletId: walletId,
        );
        executionRepository = KdfRouteExecutionRepository(
          walletId: walletId,
          manager: widget.manager,
          executionEligibilityCheck: widget.executionEligibilityCheck,
        );
        activityBloc = RouteActivityBloc(repository: activityRepository)
          ..add(RouteActivityWalletChanged(walletId));
        executionBloc = RouteExecutionBloc(repository: executionRepository)
          ..add(RouteExecutionWalletChanged(walletId));
        final quoteRepository = widget.quoteRepositoryFactory?.call(
          walletId: walletId,
          manager: widget.manager,
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
      if (quoteBloc != null && widget.initialIntentResolver != null) {
        unawaited(_seedIntent(quoteBloc, generation));
      }
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

  Future<void> _seedIntent(UnifiedSwapBloc bloc, int generation) async {
    try {
      final intent = await widget.initialIntentResolver?.call();
      if (!mounted ||
          generation != _walletGeneration ||
          !identical(_quoteBloc, bloc) ||
          intent == null) {
        return;
      }
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
    _identityGeneration++;
    _walletGeneration++;
    unawaited(_walletSubscription?.cancel());
    unawaited(_disposeWalletBindings());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activityBloc = _activityBloc;
    final executionBloc = _executionBloc;
    if (activityBloc == null || executionBloc == null) {
      return widget.child;
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
      key: ValueKey(_walletId),
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
    return child;
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
