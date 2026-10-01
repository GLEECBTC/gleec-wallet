import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/utils/window/window.dart';

/// What the browser tab says about swaps, most pressing first.
enum SwapTabSignal {
  /// A running swap waits on the user.
  action(0xFFF59E0B),

  /// A finished swap needs looking at.
  attention(0xFFF59E0B),

  /// A swap completed while the user was away from the tab.
  completed(0xFF16A34A),

  /// A swap is running.
  running(0xFF8C41FF);

  const SwapTabSignal(this.argb);

  /// The dot on the tab's icon.
  final int argb;
}

/// Marks the browser tab while swaps need following: its title says what is
/// happening and its icon carries a dot, so a swap can be followed from
/// another tab. A completion the user was away for shows until they return.
///
/// Web only: elsewhere there is no tab, and Android would show the title in
/// its recent apps.
class SwapTabSignals extends StatefulWidget {
  const SwapTabSignals({
    required this.color,
    required this.child,
    this.enabled = kIsWeb,
    this.badge = setTabIconBadge,
    super.key,
  });

  /// The colour the app's own title passes, which the browser keeps as its
  /// theme colour.
  final Color color;
  final Widget child;
  final bool enabled;

  /// Puts a dot of an ARGB colour on the tab's icon, or takes it off.
  final void Function(int? argb) badge;

  @override
  State<SwapTabSignals> createState() => _SwapTabSignalsState();
}

class _SwapTabSignalsState extends State<SwapTabSignals> {
  SwapExecutionRegistry? _registry;
  StreamSubscription<List<SwapExecutionSnapshot>>? _executions;
  StreamSubscription<SwapExecutionNotice>? _notices;
  AppLifecycleListener? _lifecycle;
  var _away = false;
  var _completedAway = false;
  SwapTabSignal? _badged;
  String? _titled;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    final registry = _registry = context.read<SwapServices?>()?.registry;
    if (registry == null) return;
    _away = _isAway(WidgetsBinding.instance.lifecycleState);
    _executions = registry.executions.listen((_) => _changed());
    _notices = registry.notices.listen((notice) {
      if (_away && notice.kind == SwapExecutionNoticeKind.completed) {
        _completedAway = true;
        _changed();
      }
    });
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _away = _isAway(state);
        if (!_away) _completedAway = false;
        _changed();
      },
    );
  }

  @override
  void dispose() {
    unawaited(_executions?.cancel());
    unawaited(_notices?.cancel());
    _lifecycle?.dispose();
    if (_badged != null) widget.badge(null);
    super.dispose();
  }

  /// Any state but the foreground: another tab, or another window in front.
  static bool _isAway(AppLifecycleState? state) =>
      state != null && state != AppLifecycleState.resumed;

  SwapTabSignal? get _signal {
    final registry = _registry;
    if (registry == null) return null;
    final running = registry.current.where((s) => !s.isTerminal).toList();
    if (running.any((s) => s.stage == SwapProgressStage.actionRequired)) {
      return SwapTabSignal.action;
    }
    if (registry.unacknowledgedAttentionCount > 0) {
      return SwapTabSignal.attention;
    }
    if (_completedAway) return SwapTabSignal.completed;
    if (running.isNotEmpty) return SwapTabSignal.running;
    return null;
  }

  void _changed() {
    if (!mounted) return;
    final signal = _signal;
    if (signal != _badged) {
      _badged = signal;
      widget.badge(signal?.argb);
    }
    final title = _title(signal);
    if (title != _titled) {
      _titled = title;
      // A hidden tab draws no frames, so the title is set now rather than
      // left to the next build, which may not come until the user is back.
      SystemChrome.setApplicationSwitcherDescription(
        ApplicationSwitcherDescription(
          label: title,
          primaryColor: widget.color.toARGB32(),
        ),
      );
    }
    setState(() {});
  }

  String _title(SwapTabSignal? signal) {
    if (signal == null) return appTitle;
    final running = _registry!.activeCount;
    final what = switch (signal) {
      SwapTabSignal.action => LocaleKeys.swapTabAction.tr(),
      SwapTabSignal.attention => LocaleKeys.swapTabAttention.tr(),
      SwapTabSignal.completed => LocaleKeys.swapTabCompleted.tr(),
      SwapTabSignal.running =>
        running > 1
            ? LocaleKeys.swapTabRunningMany.tr(args: ['$running'])
            : LocaleKeys.swapTabRunning.tr(),
    };
    return LocaleKeys.swapTabTitle.tr(args: [what, appShortTitle]);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _registry == null) return widget.child;
    // Built after the app's own title, so this one is the one the tab keeps
    // when the app rebuilds.
    return Title(
      title: _titled ?? appTitle,
      color: widget.color,
      child: widget.child,
    );
  }
}
