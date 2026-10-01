import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/swap/swap_execution_snapshot.dart';
import 'package:web_dex/views/swap/common/swap_format.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

/// When a swap started, how long it has run and when the engine last
/// answered for it, or when it finished and how long it took; for a routed
/// swap, how long it usually takes; for an atomic refund, when the refund
/// unlocks.
///
/// A plain line under the hero rather than part of it, so its minutes change
/// without being read out. While the swap runs it changes only when a figure
/// would read differently, and not at all once the swap has finished.
class SwapTimeContext extends StatefulWidget {
  const SwapTimeContext({
    required this.snapshot,
    this.delayed = false,
    this.checkedAt,
    this.checks,
    this.now = DateTime.now,
    super.key,
  });

  final SwapExecutionSnapshot snapshot;

  /// Whether the status may be out of date, when an estimate means nothing.
  final bool delayed;

  /// When the engine last answered for the swap, and each answer as it
  /// arrives: a quiet swap is still being checked.
  final DateTime? checkedAt;
  final Stream<DateTime>? checks;
  final DateTime Function() now;

  @override
  State<SwapTimeContext> createState() => _SwapTimeContextState();
}

/// An answer this recent reads as "just now"; after it, the age shows in
/// tens of seconds, then minutes.
const _justChecked = Duration(seconds: 20);

class _SwapTimeContextState extends State<SwapTimeContext> {
  Timer? _tick;
  DateTime? _checkedAt;
  StreamSubscription<DateTime>? _checks;

  @override
  void initState() {
    super.initState();
    _checkedAt = widget.checkedAt;
    _listen();
    _schedule();
  }

  @override
  void didUpdateWidget(SwapTimeContext oldWidget) {
    super.didUpdateWidget(oldWidget);
    final given = widget.checkedAt;
    if (given != null && !(_checkedAt?.isAfter(given) ?? false)) {
      _checkedAt = given;
    }
    if (widget.checks != oldWidget.checks) _listen();
    _schedule();
  }

  void _listen() {
    unawaited(_checks?.cancel());
    _checks = widget.checks?.listen((at) {
      if (!mounted) return;
      setState(() => _checkedAt = at);
      _schedule();
    });
  }

  /// Wakes when the next line would read differently: a whole minute more
  /// since the start, the last answer growing older, or the refund
  /// unlocking.
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
    final untilOlder = _untilCheckedReadsOlder(now);
    if (untilOlder != null && untilOlder < wait) wait = untilOlder;
    _tick = Timer(wait, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_checks?.cancel());
    super.dispose();
  }

  Duration _checkedAge(DateTime now) {
    final age = now.difference(_checkedAt!);
    return age.isNegative ? Duration.zero : age;
  }

  Duration? _untilCheckedReadsOlder(DateTime now) {
    if (_checkedAt == null) return null;
    final age = _checkedAge(now);
    if (age < _justChecked) return _justChecked - age;
    if (age < const Duration(minutes: 1)) {
      return Duration(seconds: (age.inSeconds ~/ 10 + 1) * 10) - age;
    }
    return Duration(minutes: age.inMinutes + 1) - age;
  }

  /// How long ago the engine last answered: "just now", then in tens of
  /// seconds, then as long as the swap's own times.
  String _checked(DateTime now) {
    final age = _checkedAge(now);
    if (age < _justChecked) return LocaleKeys.swapTimeCheckedNow.tr();
    return LocaleKeys.swapTimeCheckedAgo.tr(
      args: [
        if (age < const Duration(minutes: 1))
          LocaleKeys.swapTimeSeconds.tr(args: ['${age.inSeconds ~/ 10 * 10}'])
        else
          SwapFormat.elapsed(age),
      ],
    );
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
      if (start != null && _checkedAt != null)
        LocaleKeys.swapTimeStartedChecked.tr(
          args: [
            SwapFormat.time(start, now: now),
            SwapFormat.elapsed(now.difference(start)),
            _checked(now),
          ],
        )
      else if (start != null)
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
