import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

/// When a swap started and how long it has run, or when it finished and how
/// long it took; for a routed swap, how long it usually takes; for an atomic
/// refund, when the refund unlocks.
///
/// A plain line under the hero rather than part of it, so its minutes change
/// without being read out. It updates on the minute while the swap runs, and
/// not at all once the swap has finished.
class SwapTimeContext extends StatefulWidget {
  const SwapTimeContext({
    required this.snapshot,
    this.delayed = false,
    this.now = DateTime.now,
    super.key,
  });

  final SwapExecutionSnapshot snapshot;

  /// Whether the status may be out of date, when an estimate means nothing.
  final bool delayed;
  final DateTime Function() now;

  @override
  State<SwapTimeContext> createState() => _SwapTimeContextState();
}

class _SwapTimeContextState extends State<SwapTimeContext> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(SwapTimeContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  /// Wakes when the next line would read differently: a whole minute more
  /// since the start, or the refund unlocking.
  void _schedule() {
    _tick?.cancel();
    _tick = null;
    final snapshot = widget.snapshot;
    final start = snapshot.createdAt;
    if (snapshot.isTerminal || start == null) return;
    final now = widget.now();
    final since = now.difference(start);
    var wait =
        const Duration(minutes: 1) -
        Duration(
          microseconds: since.inMicroseconds % Duration.microsecondsPerMinute,
        );
    final unlock = snapshot.refundUnlocksAt;
    if (unlock != null && unlock.isAfter(now)) {
      final untilUnlock = unlock.difference(now);
      if (untilUnlock < wait) wait = untilUnlock;
    }
    _tick = Timer(wait, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  List<String> _lines(DateTime now) {
    final snapshot = widget.snapshot;
    final start = snapshot.createdAt;
    if (snapshot.isTerminal) {
      final end = snapshot.finishedAt;
      if (end == null) return const [];
      return [
        if (start == null || end.isBefore(start))
          LocaleKeys.swapTimeFinished.tr(args: [SwapFormat.time(end, now: now)])
        else
          LocaleKeys.swapTimeFinishedTook.tr(
            args: [
              SwapFormat.time(end, now: now),
              SwapFormat.elapsed(end.difference(start)),
            ],
          ),
      ];
    }
    final unlock = snapshot.refundUnlocksAt;
    final estimate = snapshot.estimatedDuration;
    return [
      if (start != null)
        LocaleKeys.swapTimeStarted.tr(
          args: [
            SwapFormat.time(start, now: now),
            SwapFormat.elapsed(now.difference(start)),
          ],
        ),
      if (unlock != null && snapshot.stage == SwapProgressStage.refunding)
        (now.isBefore(unlock)
                ? LocaleKeys.swapTimeRefundUnlocks
                : LocaleKeys.swapTimeRefundUnlocked)
            .tr(args: [SwapFormat.time(unlock, now: now)])
      else if (!widget.delayed &&
          start != null &&
          estimate != null &&
          estimate > Duration.zero)
        now.difference(start) > estimate
            ? LocaleKeys.swapTimeLonger.tr()
            : estimate < const Duration(minutes: 1)
            ? LocaleKeys.swapTimeUsuallyUnderMinute.tr()
            : LocaleKeys.swapTimeUsually.tr(
                args: [SwapFormat.elapsed(estimate, roundUp: true)],
              ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines(widget.now());
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        children: [
          for (final line in lines)
            Text(
              line,
              style: SwapText.small(context),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
