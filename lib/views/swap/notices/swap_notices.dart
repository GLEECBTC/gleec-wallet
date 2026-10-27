import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/main_menu_value.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:web_dex/shared/swap/swap_execution_registry.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
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

  @override
  void initState() {
    super.initState();
    final services = _services = context.read<SwapServices?>();
    if (services == null) return;
    _subscription = services.registry.notices.listen(_show);
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
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
        final received = amount == null
            ? ticker
            : SwapFormat.tokens(amount, ticker, rounding: SwapRounding.down);
        return LocaleKeys.swapNoticeCompleted.tr(
          args: [
            if (amount != null && snapshot.outcome!.receivedReported)
              LocaleKeys.swapReceivedReported.tr(
                args: [received, SwapTermsRepository.provider],
              )
            else
              received,
          ],
        );
      case SwapExecutionNoticeKind.refunded:
        final copy = SwapExecutionCopy(notice.snapshot, _services!.networks());
        return LocaleKeys.swapNoticeRefunded.tr(
          args: [copy.fromTicker, copy.fromNetwork],
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
