import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/features/unified_swap/application/route_activity_bloc.dart';
import 'package:web_dex/features/unified_swap/presentation/activity/activity_detail_view.dart';
import 'package:web_dex/features/unified_swap/presentation/activity/activity_list_view.dart';
import 'package:web_dex/features/unified_swap/presentation/activity/activity_widgets.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';

class RouteActivityPage extends StatefulWidget {
  const RouteActivityPage({
    this.bloc,
    this.showDetails = false,
    this.initialRouteExecutionId,
    this.onExecutionSelected,
    this.onBack,
    this.onCancelRequested,
    this.onStopAfterCurrentRequested,
    this.onRecoveryRequested,
    this.clipboardWriter = defaultActivityClipboardWriter,
    this.announcement = defaultActivityAnnouncement,
    this.manageLifecycle = true,
    super.key,
  });

  final RouteActivityBloc? bloc;
  final bool showDetails;
  final String? initialRouteExecutionId;
  final ValueChanged<String>? onExecutionSelected;
  final VoidCallback? onBack;
  final ValueChanged<String>? onCancelRequested;
  final ValueChanged<String>? onStopAfterCurrentRequested;
  final ValueChanged<String>? onRecoveryRequested;
  final ActivityClipboardWriter clipboardWriter;
  final ActivityAnnouncement announcement;
  final bool manageLifecycle;

  @override
  State<RouteActivityPage> createState() => _RouteActivityPageState();
}

class _RouteActivityPageState extends State<RouteActivityPage>
    with WidgetsBindingObserver {
  RouteActivityBloc? _bloc;
  String? _requestedRouteExecutionId;

  @override
  void initState() {
    super.initState();
    if (widget.manageLifecycle) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextBloc = widget.bloc ?? _maybeActivityBloc(context);
    if (!identical(_bloc, nextBloc)) {
      _requestedRouteExecutionId = null;
    }
    _bloc = nextBloc;
    _requestInitialDetail();
  }

  @override
  void didUpdateWidget(RouteActivityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bloc != widget.bloc) {
      _bloc = widget.bloc ?? _maybeActivityBloc(context);
      _requestedRouteExecutionId = null;
    }
    if (oldWidget.initialRouteExecutionId != widget.initialRouteExecutionId ||
        oldWidget.showDetails != widget.showDetails) {
      _requestedRouteExecutionId = null;
      _requestInitialDetail();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.manageLifecycle || state != AppLifecycleState.resumed) return;
    _bloc?.add(const RouteActivityAppResumed());
  }

  @override
  void dispose() {
    if (widget.manageLifecycle) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _requestInitialDetail() {
    final bloc = _bloc;
    final routeExecutionId = widget.initialRouteExecutionId;
    if (!widget.showDetails ||
        bloc == null ||
        bloc.state.walletId == null ||
        routeExecutionId == null ||
        routeExecutionId.trim().isEmpty ||
        _requestedRouteExecutionId == routeExecutionId ||
        bloc.state.selectedExecution?.summary.routeExecutionId ==
            routeExecutionId) {
      return;
    }
    _requestedRouteExecutionId = routeExecutionId;
    bloc.add(RouteActivityExecutionRequested(routeExecutionId));
  }

  Future<void> _refresh() async {
    final bloc = _bloc;
    if (bloc == null || bloc.state.walletId == null) return;
    bloc.add(const RouteActivityRefreshRequested());
    try {
      await bloc.stream
          .firstWhere(
            (state) =>
                state.status == RouteActivityLoadStatus.ready ||
                state.status == RouteActivityLoadStatus.unavailable,
          )
          .timeout(const Duration(seconds: 30));
    } on Object {
      // The BLoC owns the typed failure state. Pull-to-refresh should simply
      // finish when its local wait is interrupted.
    }
  }

  void _openExecution(String routeExecutionId) {
    final bloc = _bloc;
    if (bloc == null) return;
    bloc.add(RouteActivityExecutionRequested(routeExecutionId));
    widget.onExecutionSelected?.call(routeExecutionId);
  }

  void _loadMore() {
    _bloc?.add(const RouteActivityLoadMoreRequested());
  }

  void _retryDetail() {
    final routeExecutionId = widget.initialRouteExecutionId;
    if (routeExecutionId == null || routeExecutionId.trim().isEmpty) return;
    _bloc?.add(RouteActivityExecutionRequested(routeExecutionId));
  }

  @override
  Widget build(BuildContext context) {
    final bloc = _bloc;
    if (bloc == null) {
      return RouteActivityPlaceholder(
        key: const Key('activity-dependency-unavailable'),
        icon: Icons.lock_outline_rounded,
        title: unifiedSwapText(
          context,
          'activity.dependencyUnavailableTitle',
          'Activity is unavailable',
        ),
        message: unifiedSwapText(
          context,
          'activity.dependencyUnavailableBody',
          'Connect an authenticated wallet before viewing Unified Swap '
              'activity.',
        ),
      );
    }
    return BlocConsumer<RouteActivityBloc, RouteActivityState>(
      bloc: bloc,
      listenWhen: (previous, current) =>
          previous.walletId != current.walletId && current.walletId != null,
      listener: (context, state) {
        // A deep link may be built before its wallet scope is authenticated.
        // Retry only after the BLoC accepts that scope; otherwise the detail
        // event is intentionally ignored by the application layer.
        _requestedRouteExecutionId = null;
        _requestInitialDetail();
      },
      builder: (context, state) {
        if (state.walletId == null) {
          return RouteActivityPlaceholder(
            key: const Key('activity-wallet-unavailable'),
            icon: Icons.account_balance_wallet_outlined,
            title: unifiedSwapText(
              context,
              'activity.noWalletTitle',
              'No authenticated wallet',
            ),
            message: unifiedSwapText(
              context,
              'activity.noWalletBody',
              'Sign in to a wallet to load authoritative Unified Swap '
                  'activity.',
            ),
          );
        }
        if (widget.showDetails) {
          final routeExecutionId = widget.initialRouteExecutionId;
          if (routeExecutionId == null || routeExecutionId.trim().isEmpty) {
            return RouteActivityPlaceholder(
              icon: Icons.receipt_long_outlined,
              title: unifiedSwapText(
                context,
                'activity.detailsUnavailableTitle',
                'Route details are unavailable',
              ),
              message: unifiedSwapText(
                context,
                'activity.missingExecutionId',
                'No complete execution ID was provided.',
              ),
              actionLabel: unifiedSwapText(
                context,
                'activity.backToActivity',
                'Back to Activity',
              ),
              onAction: _back,
            );
          }
          return RouteActivityDetailView(
            state: state,
            routeExecutionId: routeExecutionId,
            onBack: _back,
            onRetry: _retryDetail,
            clipboardWriter: widget.clipboardWriter,
            announcement: widget.announcement,
            onCancelRequested: widget.onCancelRequested,
            onStopAfterCurrentRequested: widget.onStopAfterCurrentRequested,
            onRecoveryRequested: widget.onRecoveryRequested,
          );
        }
        return RouteActivityListView(
          state: state,
          onRefresh: _refresh,
          onLoadMore: _loadMore,
          onExecutionSelected: _openExecution,
          clipboardWriter: widget.clipboardWriter,
          announcement: widget.announcement,
        );
      },
    );
  }

  void _back() {
    if (widget.onBack case final onBack?) {
      onBack();
      return;
    }
    unawaited(Navigator.maybePop(context));
  }
}

RouteActivityBloc? _maybeActivityBloc(BuildContext context) {
  try {
    return context.read<RouteActivityBloc>();
  } on Object {
    return null;
  }
}
