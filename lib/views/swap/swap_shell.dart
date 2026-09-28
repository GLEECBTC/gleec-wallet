import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/swap_activity/swap_activity_bloc.dart';
import 'package:web_dex/bloc/system_health/system_health_bloc.dart';
import 'package:web_dex/bloc/trading_status/trading_status_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/views/dex/dex_page.dart';
import 'package:web_dex/views/swap/activity/swap_activity_view.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/common/swap_widgets.dart';
import 'package:web_dex/views/swap/swap_page.dart';
import 'package:web_dex/views/swap/swap_shell_controller.dart';

export 'package:web_dex/views/swap/swap_shell_controller.dart'
    show SwapDestination;

part 'swap_shell_navigation.dart';

/// The Swap surface.
///
/// [SwapDestination.swap] is the default because it answers the question most
/// people arrive with — turn this into that — without asking them to
/// understand makers, takers or an orderbook first. The full trading
/// interface is not removed, only moved: everything that was on the DEX page
/// is still one tap away under Advanced.
///
/// The form's state lives here rather than in the Swap destination, so moving
/// to Activity and back keeps what was typed; running swaps live app-wide in
/// the registry and outlive the surface altogether.
class SwapShell extends StatefulWidget {
  const SwapShell({
    this.initialDestination = SwapDestination.swap,
    this.destinationBuilder,
    super.key,
  });

  /// Which destination to open on.
  final SwapDestination initialDestination;

  /// Builds the body for a destination.
  ///
  /// Overridable so the shell's own behaviour can be tested without standing
  /// up the trading page's full dependency graph. When set, the shell provides
  /// no swap state of its own.
  final Widget Function(SwapDestination)? destinationBuilder;

  @override
  State<SwapShell> createState() => _SwapShellState();
}

class _SwapShellState extends State<SwapShell> {
  late final SwapShellController _controller = SwapShellController(
    initial: widget.initialDestination,
  );

  @override
  void initState() {
    super.initState();
    routingState.dexState.addListener(_onRouteChanged);
    _followRoute();
  }

  @override
  void dispose() {
    routingState.dexState.removeListener(_onRouteChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onRouteChanged() {
    if (!mounted) return;
    _followRoute();
  }

  /// Follows the dex deep links to the destination that can serve them.
  ///
  /// A `/dex/trading_details/<uuid>` link addresses a specific atomic swap,
  /// which only the full trading interface renders, and a maker-order link
  /// only makes sense there too. Every other dex link opens on Swap.
  void _followRoute() {
    final dex = routingState.dexState;
    if (dex.isTradingDetails || dex.orderType == 'maker') {
      _controller.show(SwapDestination.advanced);
    }
  }

  Widget _body(SwapDestination destination) {
    final builder = widget.destinationBuilder;
    if (builder != null) return builder(destination);
    return switch (destination) {
      SwapDestination.swap => const SwapPage(),
      SwapDestination.activity => const SwapActivityView(),
      // Constructed fresh so the trading page keeps owning its own routing
      // and lifecycle exactly as it does today.
      SwapDestination.advanced => const DexPage(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final shell = SwapShellScope(
      controller: _controller,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final destination = _controller.destination;
          final palette = SwapPalette.of(context);
          return ColoredBox(
            color: destination == SwapDestination.advanced
                ? Colors.transparent
                : palette.canvas,
            child: Column(
              key: const Key('swap-shell'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SwapNavigation(
                  selected: destination,
                  onSelected: _controller.show,
                ),
                Expanded(child: _body(destination)),
              ],
            ),
          );
        },
      ),
    );
    if (widget.destinationBuilder != null) return shell;
    return _SwapScope(controller: _controller, child: shell);
  }
}

/// Owns the swap surface's state and keeps it in step with the app: trading
/// availability, the device clock, deep links, and requests from elsewhere.
class _SwapScope extends StatefulWidget {
  const _SwapScope({required this.controller, required this.child});

  final SwapShellController controller;
  final Widget child;

  @override
  State<_SwapScope> createState() => _SwapScopeState();
}

class _SwapScopeState extends State<_SwapScope> {
  late final SwapServices _services = context.read<SwapServices>();
  late final UnifiedSwapBloc _swap;
  late final SwapActivityBloc _activity;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  late final AppLifecycleListener _lifecycle;
  var _activityStarted = false;

  bool _tradingEnabled(TradingStatusState state) => state.isEnabled;

  bool _clockValid(SystemHealthState state) =>
      state is! SystemHealthLoadSuccess || state.isValid;

  @override
  void initState() {
    super.initState();
    final tradingStatus = context.read<TradingStatusBloc>();
    final systemHealth = context.read<SystemHealthBloc>();

    _swap =
        UnifiedSwapBloc(
            repository: _services.createRepository(
              tradingAllowed: (from, to) =>
                  tradingStatus.state.canTradeAssets([from, to]),
              clockValid: () => _clockValid(systemHealth.state),
            ),
            registry: _services.registry,
            terms: _services.terms,
            preferences: _services.preferences,
            spendableBalance: _services.spendableBalance,
            addressOf: _services.addressOf,
            resolveAsset: _services.resolveAsset,
            holdings: _services.holdings,
          )
          ..add(
            UnifiedSwapCapabilitiesChanged(
              tradingEnabled: _tradingEnabled(tradingStatus.state),
              clockValid: _clockValid(systemHealth.state),
            ),
          )
          ..add(const UnifiedSwapStarted());
    _activity = SwapActivityBloc(
      history: _services.history,
      registry: _services.registry,
    );

    _subscriptions
      ..add(tradingStatus.stream.listen((_) => _publishCapabilities()))
      ..add(systemHealth.stream.listen((_) => _publishCapabilities()))
      ..add(_services.intents.listen((_) => _applyPendingIntent()))
      ..add(_services.openRequests.listen((_) => _openPending()));

    // `inactive` counts as shown: a window that lost focus is still on screen.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => _swap.add(
        UnifiedSwapForegroundChanged(
          foreground:
              state == AppLifecycleState.resumed ||
              state == AppLifecycleState.inactive,
        ),
      ),
    );

    widget.controller.addListener(_onDestinationChanged);
    routingState.dexState.addListener(_onRouteChanged);
    _applyPendingIntent();
    _applyRouteIntent(force: false);
    _openPending();
    if (widget.controller.destination == SwapDestination.activity) {
      _showActivity();
    }
  }

  /// Loads Activity the first time it is shown, and refreshes it after.
  void _showActivity() {
    if (_activityStarted) {
      _activity.add(const SwapActivityRefreshed());
      return;
    }
    _activityStarted = true;
    _activity.add(const SwapActivityStarted());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    widget.controller.removeListener(_onDestinationChanged);
    routingState.dexState.removeListener(_onRouteChanged);
    unawaited(_swap.close());
    unawaited(_activity.close());
    super.dispose();
  }

  void _publishCapabilities() {
    _swap.add(
      UnifiedSwapCapabilitiesChanged(
        tradingEnabled: _tradingEnabled(
          context.read<TradingStatusBloc>().state,
        ),
        clockValid: _clockValid(context.read<SystemHealthBloc>().state),
      ),
    );
  }

  void _onDestinationChanged() {
    _swap.add(
      UnifiedSwapVisibilityChanged(
        visible: widget.controller.destination == SwapDestination.swap,
      ),
    );
    if (widget.controller.destination == SwapDestination.activity &&
        widget.controller.detail == null) {
      _showActivity();
    }
  }

  var _routeReadScheduled = false;

  // The router sets a link's fields one by one, notifying for each: a maker
  // link's currencies arrive before the order type that rules it out.
  void _onRouteChanged() {
    if (_routeReadScheduled) return;
    _routeReadScheduled = true;
    scheduleMicrotask(() {
      _routeReadScheduled = false;
      if (mounted) _applyRouteIntent(force: true);
    });
  }

  void _applyPendingIntent() {
    final intent = _services.takePendingIntent();
    if (intent == null) return;
    _swap.add(
      UnifiedSwapIntentApplied(
        pay: intent.pay,
        receive: intent.receive,
        amount: intent.amount,
      ),
    );
    widget.controller.show(SwapDestination.swap);
  }

  /// Applies `/dex?from_currency=…&to_currency=…&from_amount=…`. On mount the
  /// same link is applied once only; a fresh navigation always applies.
  void _applyRouteIntent({required bool force}) {
    final dex = routingState.dexState;
    if (dex.orderType == 'maker' || dex.isTradingDetails) return;
    final pay = dex.fromCurrency;
    final receive = dex.toCurrency;
    if (pay.isEmpty && receive.isEmpty) return;
    final signature = '$pay|$receive|${dex.fromAmount}';
    if (!force && _services.lastRouteIntent == signature) return;
    _services.lastRouteIntent = signature;
    _swap.add(
      UnifiedSwapIntentApplied(
        pay: pay.isEmpty ? null : pay,
        receive: receive.isEmpty ? null : receive,
        amount: dex.fromAmount.isEmpty ? null : dex.fromAmount,
      ),
    );
  }

  void _openPending() {
    final ref = _services.takePendingOpen();
    if (ref == null) return;
    widget.controller.showActivity(swap: ref);
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<UnifiedSwapBloc>.value(value: _swap),
        BlocProvider<SwapActivityBloc>.value(value: _activity),
      ],
      child: widget.child,
    );
  }
}
