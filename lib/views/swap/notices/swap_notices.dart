import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_analytics.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/utils/extensions/kdf_user_extensions.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';

/// Tells the user, wherever they are in the app, when a swap they started
/// finishes or needs them.
///
/// A cross-chain swap can take half an hour, and nobody should have to sit on
/// the progress screen to find out it worked.
class SwapNoticeListener extends StatefulWidget {
  const SwapNoticeListener({required this.child, super.key});

  final Widget child;

  @override
  State<SwapNoticeListener> createState() => _SwapNoticeListenerState();
}

class _SwapNoticeListenerState extends State<SwapNoticeListener> {
  StreamSubscription<SwapExecutionNotice>? _subscription;
  SwapServices? _services;
  SwapAnalyticsReporter? _analytics;

  @override
  void initState() {
    super.initState();
    final services = _services = context.read<SwapServices?>();
    if (services == null) return;
    _subscription = services.registry.notices.listen(_show);
    final analytics = context.read<AnalyticsBloc?>();
    final auth = context.read<AuthBloc?>();
    if (analytics != null) {
      _analytics = SwapAnalyticsReporter(
        registry: services.registry,
        log: analytics.logEvent,
        walletType: () => auth?.state.currentUser?.type ?? '',
      );
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    unawaited(_analytics?.dispose());
    super.dispose();
  }

  void _show(SwapExecutionNotice notice) {
    final services = _services;
    if (!mounted || services == null) return;
    final snapshot = notice.snapshot;
    // Already on screen: the screen itself is the notice.
    if (services.viewing.contains(snapshot.id)) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        content: Text(_message(notice)),
        action: SnackBarAction(
          label: LocaleKeys.swapNoticeView.tr(),
          onPressed: () {
            services.requestOpen((id: snapshot.id, source: snapshot.source));
            routingState.selectedMenu = MainMenuValue.dex;
          },
        ),
      ),
    );
  }

  String _message(SwapExecutionNotice notice) {
    switch (notice.kind) {
      case SwapExecutionNoticeKind.completed:
        final snapshot = notice.snapshot;
        final amount = snapshot.outcome?.receivedAmount;
        final asset = snapshot.outcome?.receivedAsset ?? snapshot.to;
        final ticker = asset == null
            ? snapshot.toTicker
            : SwapFormat.ticker(asset);
        return LocaleKeys.swapNoticeCompleted.tr(
          args: [
            amount == null
                ? ticker
                : SwapFormat.tokens(
                    amount,
                    ticker,
                    rounding: SwapRounding.down,
                  ),
          ],
        );
      case SwapExecutionNoticeKind.needsAttention:
        return LocaleKeys.swapNoticeAttention.tr();
      case SwapExecutionNoticeKind.actionRequired:
        return LocaleKeys.swapNoticeAction.tr();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Rebuilds with whether any followed swap needs the user's attention, for
/// the mark on the Swap menu entry.
class SwapAttentionBuilder extends StatelessWidget {
  const SwapAttentionBuilder({required this.builder, super.key});

  final Widget Function(BuildContext context, bool needsAttention) builder;

  @override
  Widget build(BuildContext context) {
    final registry = context.read<SwapServices?>()?.registry;
    if (registry == null) return builder(context, false);
    return StreamBuilder<List<SwapExecutionSnapshot>>(
      stream: registry.executions,
      builder: (context, _) =>
          builder(context, registry.unacknowledgedAttentionCount > 0),
    );
  }
}
