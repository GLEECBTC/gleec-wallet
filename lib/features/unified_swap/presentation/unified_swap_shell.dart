import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:web_dex/features/unified_swap/application/route_execution_bloc.dart';
import 'package:web_dex/features/unified_swap/domain/route_execution_models.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_config.dart';
import 'package:web_dex/features/unified_swap/infrastructure/unified_swap_production_composition.dart';
import 'package:web_dex/features/unified_swap/presentation/activity/activity_page.dart';
import 'package:web_dex/features/unified_swap/presentation/swap/unified_swap_page.dart';
import 'package:web_dex/features/unified_swap/presentation/unified_swap_design.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/router/state/unified_swap_section_state.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/dex/dex_page.dart';

/// Calm Core shell used identically by mobile, tablet, desktop, and web.
///
/// The shell replaces the legacy wallet chrome only while Unified Swap is
/// active. The Gleec logo returns to Wallet and the overflow keeps the existing
/// global destinations reachable without nesting the old navigation.
class UnifiedSwapShell extends StatelessWidget {
  const UnifiedSwapShell({super.key, this.config = const UnifiedSwapConfig()});

  final UnifiedSwapConfig config;

  @override
  Widget build(BuildContext context) {
    final route = routingState.unifiedSwapState.value;
    final selected = _navigationDestination(route.destination);
    final colors = UnifiedSwapDesign.colors(context);
    return ScreenshotSensitive(
      child: ColoredBox(
        color: colors.canvas,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scaledBody = MediaQuery.textScalerOf(context).scale(16);
            final desktop =
                constraints.maxWidth >= UnifiedSwapDesign.desktopBreakpoint &&
                (scaledBody < 24 || constraints.maxWidth >= 1200);
            return Column(
              children: [
                _UnifiedSwapHeader(
                  selected: selected,
                  showNavigation: desktop,
                  onSelected: _select,
                ),
                Expanded(child: _body(context, route)),
                if (!desktop)
                  _UnifiedSwapBottomNavigation(
                    selected: selected,
                    onSelected: _select,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  UnifiedSwapDestination _navigationDestination(
    UnifiedSwapDestination destination,
  ) {
    return destination == UnifiedSwapDestination.activityDetails
        ? UnifiedSwapDestination.activity
        : destination;
  }

  void _select(UnifiedSwapDestination destination) {
    switch (destination) {
      case UnifiedSwapDestination.swap:
        routingState.unifiedSwapState.replace(
          const UnifiedSwapRouteState.swap(),
        );
      case UnifiedSwapDestination.activity:
      case UnifiedSwapDestination.activityDetails:
        routingState.unifiedSwapState.replace(
          const UnifiedSwapRouteState.activity(),
        );
      case UnifiedSwapDestination.advanced:
        routingState.unifiedSwapState.replace(
          const UnifiedSwapRouteState.advanced(),
        );
    }
  }

  Widget _body(BuildContext context, UnifiedSwapRouteState route) {
    switch (route.destination) {
      case UnifiedSwapDestination.swap:
        final production = _maybeProductionComposition(context);
        return UnifiedSwapPage(
          config: config,
          maximumAmountResolver: production?.maximumAmount,
          selectionGateway: production,
        );
      case UnifiedSwapDestination.activity:
        return RouteActivityPage(
          onExecutionSelected: (routeExecutionId) {
            routingState.unifiedSwapState.replace(
              UnifiedSwapRouteState.activityDetails(routeExecutionId),
            );
          },
        );
      case UnifiedSwapDestination.activityDetails:
        return _UnifiedSwapActivityDetail(
          config: config,
          routeExecutionId: route.routeExecutionId,
        );
      case UnifiedSwapDestination.advanced:
        return const DexPage();
    }
  }
}

/// Connects read-only Activity history to the wallet-scoped durable execution
/// coordinator. Controls are exposed only after that coordinator has reattached
/// the exact route and KDF has supplied a current executable snapshot.
class _UnifiedSwapActivityDetail extends StatefulWidget {
  const _UnifiedSwapActivityDetail({
    required this.config,
    required this.routeExecutionId,
  });

  final UnifiedSwapConfig config;
  final String? routeExecutionId;

  @override
  State<_UnifiedSwapActivityDetail> createState() =>
      _UnifiedSwapActivityDetailState();
}

class _UnifiedSwapActivityDetailState
    extends State<_UnifiedSwapActivityDetail> {
  RouteExecutionBloc? _executionBloc;
  String? _requestedRouteExecutionId;
  bool _showLiveExecution = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _maybeExecutionBloc(context);
    if (!identical(next, _executionBloc)) {
      _executionBloc = next;
      _requestedRouteExecutionId = null;
    }
    _requestReattachment();
  }

  @override
  void didUpdateWidget(_UnifiedSwapActivityDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.routeExecutionId != widget.routeExecutionId) {
      _requestedRouteExecutionId = null;
      _showLiveExecution = false;
      _requestReattachment();
    }
  }

  void _requestReattachment() {
    final bloc = _executionBloc;
    final routeExecutionId = widget.routeExecutionId;
    final status = bloc?.state.status;
    if (bloc == null ||
        bloc.state.walletId == null ||
        routeExecutionId == null ||
        routeExecutionId.trim().isEmpty ||
        _requestedRouteExecutionId == routeExecutionId ||
        status == RouteExecutionLoadStatus.starting ||
        status == RouteExecutionLoadStatus.reattaching) {
      return;
    }
    _requestedRouteExecutionId = routeExecutionId;
    bloc.add(RouteExecutionReattachRequested(routeExecutionId));
  }

  @override
  Widget build(BuildContext context) {
    final routeExecutionId = widget.routeExecutionId;
    final bloc = _executionBloc;
    if (routeExecutionId == null || bloc == null) {
      return RouteActivityPage(
        showDetails: true,
        initialRouteExecutionId: routeExecutionId,
        onBack: _backToActivity,
      );
    }
    return BlocConsumer<RouteExecutionBloc, RouteExecutionState>(
      bloc: bloc,
      listenWhen: (previous, current) =>
          (previous.status == RouteExecutionLoadStatus.starting ||
              previous.status == RouteExecutionLoadStatus.reattaching) &&
          current.status != RouteExecutionLoadStatus.starting &&
          current.status != RouteExecutionLoadStatus.reattaching,
      listener: (_, __) => _requestReattachment(),
      builder: (context, state) {
        if (_showLiveExecution) {
          final production = _maybeProductionComposition(context);
          return UnifiedSwapPage(
            config: widget.config,
            initialRouteExecutionId: routeExecutionId,
            maximumAmountResolver: production?.maximumAmount,
          );
        }
        final progress = state.progress;
        final matches =
            state.session?.routeExecutionId == routeExecutionId &&
            progress?.routeExecutionId == routeExecutionId &&
            progress!.isExecutable &&
            !state.controlInFlight;
        final controls = progress?.controls;
        final pending = progress?.pendingAction;
        return RouteActivityPage(
          showDetails: true,
          initialRouteExecutionId: routeExecutionId,
          onBack: _backToActivity,
          onCancelRequested:
              matches && controls!.canCancel && !controls.reconciliationOnly
              ? _cancel
              : null,
          onStopAfterCurrentRequested:
              matches &&
                  controls!.canStopAfterCurrent &&
                  !controls.reconciliationOnly
              ? _stopAfterCurrent
              : null,
          onRecoveryRequested:
              matches &&
                  pending != null &&
                  pending.isExecutable &&
                  pending.allowedActions.contains(
                    RouteExecutionActionKind.selectRecoveryRoute,
                  )
              ? _openRecovery
              : null,
        );
      },
    );
  }

  void _cancel(String routeExecutionId) {
    if (_matchesCurrentSession(routeExecutionId)) {
      _executionBloc!.add(const RouteExecutionCancelRequested());
    }
  }

  void _stopAfterCurrent(String routeExecutionId) {
    if (_matchesCurrentSession(routeExecutionId)) {
      _executionBloc!.add(const RouteExecutionStopAfterCurrentRequested());
    }
  }

  void _openRecovery(String routeExecutionId) {
    if (!_matchesCurrentSession(routeExecutionId)) return;
    setState(() => _showLiveExecution = true);
  }

  bool _matchesCurrentSession(String routeExecutionId) =>
      routeExecutionId == widget.routeExecutionId &&
      _executionBloc?.state.session?.routeExecutionId == routeExecutionId &&
      _executionBloc?.state.progress?.routeExecutionId == routeExecutionId;

  void _backToActivity() => routingState.unifiedSwapState.replace(
    const UnifiedSwapRouteState.activity(),
  );
}

RouteExecutionBloc? _maybeExecutionBloc(BuildContext context) {
  try {
    return context.read<RouteExecutionBloc>();
  } on Object {
    return null;
  }
}

UnifiedSwapProductionComposition? _maybeProductionComposition(
  BuildContext context,
) {
  try {
    return context.read<UnifiedSwapProductionComposition>();
  } on Object {
    return null;
  }
}

class _UnifiedSwapHeader extends StatelessWidget {
  const _UnifiedSwapHeader({
    required this.selected,
    required this.showNavigation,
    required this.onSelected,
  });

  final UnifiedSwapDestination selected;
  final bool showNavigation;
  final ValueChanged<UnifiedSwapDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsetsDirectional.fromSTEB(18, 8, 10, 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: unifiedSwapText(
                  context,
                  'shell.walletLogo',
                  'Gleec Wallet',
                ),
                child: InkWell(
                  key: const Key('unified-swap-logo'),
                  onTap: () => routingState.selectedMenu = MainMenuValue.wallet,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SvgPicture.asset(
                          'assets/logo/g_icon.svg',
                          width: 25,
                          height: 32,
                        ),
                        const SizedBox(width: 9),
                        SvgPicture.asset(
                          Theme.of(context).brightness == Brightness.dark
                              ? 'assets/logo/logo_dark.svg'
                              : 'assets/logo/logo.svg',
                          width: 112,
                          height: 25,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (showNavigation)
                Semantics(
                  container: true,
                  label: LocaleKeys.unifiedSwap_navigationLabel.tr(),
                  child: FocusTraversalGroup(
                    child: Row(
                      children: [
                        for (final destination in const [
                          UnifiedSwapDestination.swap,
                          UnifiedSwapDestination.activity,
                          UnifiedSwapDestination.advanced,
                        ])
                          _UnifiedSwapNavigationItem(
                            destination: destination,
                            selected: selected == destination,
                            onPressed: () => onSelected(destination),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              _GlobalOverflowButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnifiedSwapBottomNavigation extends StatelessWidget {
  const _UnifiedSwapBottomNavigation({
    required this.selected,
    required this.onSelected,
  });

  final UnifiedSwapDestination selected;
  final ValueChanged<UnifiedSwapDestination> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return Material(
      color: colors.surface,
      child: SafeArea(
        top: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              for (final destination in const [
                UnifiedSwapDestination.swap,
                UnifiedSwapDestination.activity,
                UnifiedSwapDestination.advanced,
              ])
                Expanded(
                  child: _UnifiedSwapNavigationItem(
                    destination: destination,
                    selected: selected == destination,
                    vertical: true,
                    onPressed: () => onSelected(destination),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnifiedSwapNavigationItem extends StatelessWidget {
  const _UnifiedSwapNavigationItem({
    required this.destination,
    required this.selected,
    required this.onPressed,
    this.vertical = false,
  });

  final UnifiedSwapDestination destination;
  final bool selected;
  final VoidCallback onPressed;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    final (label, icon) = switch (destination) {
      UnifiedSwapDestination.swap => (
        unifiedSwapText(context, 'navigation.swap', 'Swap'),
        Icons.hub_outlined,
      ),
      UnifiedSwapDestination.activity ||
      UnifiedSwapDestination.activityDetails => (
        unifiedSwapText(context, 'navigation.activity', 'Activity'),
        Icons.history_toggle_off_rounded,
      ),
      UnifiedSwapDestination.advanced => (
        unifiedSwapText(context, 'navigation.advanced', 'Advanced'),
        Icons.show_chart_rounded,
      ),
    };
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: vertical ? 2 : 2),
        child: Material(
          color: selected ? colors.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: Key('unified-swap-nav-${destination.name}'),
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: vertical ? 6 : 14,
                  vertical: vertical ? 5 : 10,
                ),
                child: vertical
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 18,
                            color: selected
                                ? colors.textPrimary
                                : colors.textSecondary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            label,
                            maxLines: 1,
                            style: UnifiedSwapDesign.typography(context)
                                .labelSmall
                                .copyWith(
                                  color: selected
                                      ? colors.textPrimary
                                      : colors.textSecondary,
                                ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: 18,
                            color: selected
                                ? colors.textPrimary
                                : colors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: UnifiedSwapDesign.typography(context)
                                .labelMedium
                                .copyWith(
                                  color: selected
                                      ? colors.textPrimary
                                      : colors.textSecondary,
                                ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlobalOverflowButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = UnifiedSwapDesign.colors(context);
    return PopupMenuButton<MainMenuValue>(
      key: const Key('unified-swap-global-overflow'),
      tooltip: unifiedSwapText(
        context,
        'shell.moreDestinations',
        'More wallet destinations',
      ),
      onSelected: (destination) => routingState.selectedMenu = destination,
      itemBuilder: (context) => [
        for (final destination in const [
          MainMenuValue.wallet,
          MainMenuValue.settings,
          MainMenuValue.support,
        ])
          PopupMenuItem(value: destination, child: Text(destination.title)),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox.square(
          dimension: 48,
          child: Icon(Icons.more_vert_rounded),
        ),
      ),
    );
  }
}
