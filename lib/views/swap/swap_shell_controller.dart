import 'package:flutter/widgets.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';

/// The three destinations behind the Swap menu entry.
enum SwapDestination {
  /// The unified swap form.
  swap,

  /// History across both liquidity sources.
  activity,

  /// The full trading interface: orderbook, maker orders, bot.
  advanced,
}

/// Moves the Swap surface between its destinations, and opens a swap's
/// detail in Activity, from anywhere inside it.
class SwapShellController extends ChangeNotifier {
  SwapShellController({SwapDestination initial = SwapDestination.swap})
    : _destination = initial;

  SwapDestination _destination;
  SwapExecutionRef? _detail;

  /// The destination on screen.
  SwapDestination get destination => _destination;

  /// The swap whose detail Activity shows, if any.
  SwapExecutionRef? get detail => _detail;

  /// Shows [destination].
  void show(SwapDestination destination) {
    if (destination == _destination) return;
    _destination = destination;
    notifyListeners();
  }

  /// Shows Activity, on [swap]'s detail when given.
  void showActivity({SwapExecutionRef? swap}) {
    _destination = SwapDestination.activity;
    _detail = swap;
    notifyListeners();
  }

  /// Returns Activity to its list.
  void closeDetail() {
    if (_detail == null) return;
    _detail = null;
    notifyListeners();
  }
}

/// Makes a [SwapShellController] available to the swap surface.
///
/// An [InheritedNotifier] rather than a Provider: the controller is a
/// [ChangeNotifier], which Provider refuses to hand out as a plain value.
class SwapShellScope extends InheritedNotifier<SwapShellController> {
  const SwapShellScope({
    required SwapShellController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// The nearest controller, without subscribing to its changes.
  static SwapShellController of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<SwapShellScope>();
    assert(scope != null, 'No SwapShellScope above this widget');
    return scope!.notifier!;
  }
}
