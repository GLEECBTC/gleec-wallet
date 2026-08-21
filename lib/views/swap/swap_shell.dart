import 'package:flutter/material.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/views/dex/dex_page.dart';
import 'package:web_dex/views/swap/swap_activity_view.dart';
import 'package:web_dex/views/swap/swap_page_provider.dart';

/// The three destinations behind the Swap menu entry.
enum SwapDestination {
  /// The unified swap form.
  swap,

  /// History across both liquidity sources.
  activity,

  /// The full trading interface: orderbook, maker orders, bot.
  advanced,
}

/// The Swap surface.
///
/// [SwapDestination.swap] is the default because it answers the question most
/// people arrive with — turn this into that — without asking them to
/// understand makers, takers or an orderbook first. The full trading
/// interface is not removed, only moved: everything that was on the DEX page
/// is still one tap away under Advanced.
///
/// The earlier attempt at this shipped the same structure with the swap
/// feature behind flags that defaulted off, so the default destination
/// rendered an unavailable message and the only working trading UI was the
/// one demoted to a sub-tab. The structure was not the problem; shipping it
/// switched off was.
class SwapShell extends StatefulWidget {
  const SwapShell({
    this.initialDestination = SwapDestination.swap,
    this.destinationBuilder = _defaultDestination,
    super.key,
  });

  /// Which destination to open on.
  final SwapDestination initialDestination;

  /// Builds the body for a destination.
  ///
  /// Overridable so the shell's own behaviour can be tested without standing
  /// up the trading page's full dependency graph.
  final Widget Function(SwapDestination) destinationBuilder;

  static Widget _defaultDestination(SwapDestination destination) =>
      switch (destination) {
        SwapDestination.swap => const SwapPageProvider(),
        SwapDestination.activity => const SwapActivityView(),
        // Constructed fresh so the trading page keeps owning its own routing
        // and lifecycle exactly as it does today.
        SwapDestination.advanced => const DexPage(),
      };

  @override
  State<SwapShell> createState() => _SwapShellState();
}

class _SwapShellState extends State<SwapShell> {
  late SwapDestination _destination = widget.initialDestination;

  @override
  void initState() {
    super.initState();
    routingState.dexState.addListener(_onRouteChanged);
    _onRouteChanged();
  }

  @override
  void dispose() {
    routingState.dexState.removeListener(_onRouteChanged);
    super.dispose();
  }

  /// Follows the existing dex deep links to the destination that can serve
  /// them.
  ///
  /// A `/dex/trading_details/<uuid>` link addresses a specific atomic swap,
  /// which only the full trading interface renders. Landing on the swap form
  /// first would drop the user somewhere that cannot answer the link, so it
  /// opens directly on Advanced. Every other dex link opens on Swap.
  void _onRouteChanged() {
    final wanted = routingState.dexState.isTradingDetails
        ? SwapDestination.advanced
        : null;
    if (wanted == null || wanted == _destination) return;
    if (!mounted) {
      _destination = wanted;
      return;
    }
    setState(() => _destination = wanted);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<SwapDestination>(
            key: const Key('swap-destination-switcher'),
            segments: const [
              ButtonSegment(
                value: SwapDestination.swap,
                label: Text('Swap'),
                icon: Icon(Icons.swap_calls),
              ),
              ButtonSegment(
                value: SwapDestination.activity,
                label: Text('Activity'),
                icon: Icon(Icons.history),
              ),
              ButtonSegment(
                value: SwapDestination.advanced,
                label: Text('Advanced'),
                icon: Icon(Icons.candlestick_chart),
              ),
            ],
            selected: {_destination},
            onSelectionChanged: (selection) =>
                setState(() => _destination = selection.first),
          ),
        ),
        Expanded(child: widget.destinationBuilder(_destination)),
      ],
    );
  }
}
