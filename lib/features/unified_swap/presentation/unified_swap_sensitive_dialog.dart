import 'package:flutter/material.dart';

/// Invalidates wallet-bound dialogs before a wallet scope is replaced.
class UnifiedSwapSensitiveDialogController extends ChangeNotifier {
  int _generation = 0;

  int get generation => _generation;

  void invalidate() {
    _generation++;
    notifyListeners();
  }
}

class UnifiedSwapSensitiveDialogScope
    extends InheritedNotifier<UnifiedSwapSensitiveDialogController> {
  const UnifiedSwapSensitiveDialogScope({
    required UnifiedSwapSensitiveDialogController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static UnifiedSwapSensitiveDialogController? maybeOf(BuildContext context) =>
      context
          .getInheritedWidgetOfExactType<UnifiedSwapSensitiveDialogScope>()
          ?.notifier;
}

/// Shows a root dialog that is dismissed if its originating wallet scope
/// changes. The generation is checked again after dismissal so a stale result
/// can never be interpreted as consent.
Future<bool> showUnifiedSwapSensitiveConfirmation({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) async {
  final controller = UnifiedSwapSensitiveDialogScope.maybeOf(context);
  final generation = controller?.generation;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final child = builder(dialogContext);
      if (controller == null || generation == null) return child;
      return _SensitiveDialogGenerationGuard(
        controller: controller,
        generation: generation,
        child: child,
      );
    },
  );
  if (controller != null && controller.generation != generation) return false;
  return confirmed ?? false;
}

class _SensitiveDialogGenerationGuard extends StatefulWidget {
  const _SensitiveDialogGenerationGuard({
    required this.controller,
    required this.generation,
    required this.child,
  });

  final UnifiedSwapSensitiveDialogController controller;
  final int generation;
  final Widget child;

  @override
  State<_SensitiveDialogGenerationGuard> createState() =>
      _SensitiveDialogGenerationGuardState();
}

class _SensitiveDialogGenerationGuardState
    extends State<_SensitiveDialogGenerationGuard> {
  bool _dismissScheduled = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleGenerationChanged);
    _handleGenerationChanged();
  }

  @override
  void didUpdateWidget(_SensitiveDialogGenerationGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleGenerationChanged);
      widget.controller.addListener(_handleGenerationChanged);
    }
    _handleGenerationChanged();
  }

  void _handleGenerationChanged() {
    if (_dismissScheduled ||
        widget.controller.generation == widget.generation) {
      return;
    }
    _dismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleGenerationChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
