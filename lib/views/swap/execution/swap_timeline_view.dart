import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/swap/common/swap_copy.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

part 'swap_step_line.dart';

/// How a swap completes, step by step, with where it has got to.
///
/// With [animate], a change passes down the steps in order: each changed step
/// blends to its new colours as its icon pops in, the line below a step fills
/// as the step completes, and a completed step sends out one ripple. However
/// many steps change at once, this takes at most [SwapMotion.cascadeLimit],
/// which also paces a jump of several steps. Without [animate], or with less
/// motion, a change shows at once.
///
/// While [tracking], the step the swap is on pulses: three times when it first
/// appears and at each of [resumes], twice after the steps move on, and once
/// for any other [event]. Every burst ends within five seconds, and the step
/// stays still between them.
class SwapTimelineView extends StatefulWidget {
  const SwapTimelineView({
    required this.steps,
    this.animate = false,
    this.tracking = false,
    this.event,
    this.resumes = 0,
    super.key,
  });

  final List<SwapTimelineStep> steps;
  final bool animate;

  /// Whether the engine is answering for the swap.
  final bool tracking;

  /// Changes whenever something new is heard of the swap.
  final Object? event;

  /// How many times the app has come back to the foreground.
  final int resumes;

  @override
  State<SwapTimelineView> createState() => _SwapTimelineViewState();
}

/// Where one step's change sits in the cascade, as fractions of it.
typedef _Beat = ({double start, double end, double fillStart, double fillEnd});

class _SwapTimelineViewState extends State<SwapTimelineView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cascade;
  List<SwapStepStatus> _from = const [];
  List<_Beat?> _beats = const [];
  int _pulse = 0;
  int _pulseBeats = 3;
  Duration _pulseDelay = SwapMotion.screen;

  @override
  void initState() {
    super.initState();
    _cascade = AnimationController(vsync: this, value: 1);
    _from = _statuses(widget.steps);
  }

  static List<SwapStepStatus> _statuses(List<SwapTimelineStep> steps) => [
    for (final step in steps) step.status,
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!SwapMotion.enabled(context)) _cascade.value = 1;
  }

  @override
  void didUpdateWidget(SwapTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final moved = _update(oldWidget);
    if (widget.resumes != oldWidget.resumes) {
      _beatAfter(Duration.zero, beats: 3);
    } else if (widget.animate && widget.event != oldWidget.event) {
      moved
          ? _beatAfter(_cascade.duration ?? Duration.zero, beats: 2)
          : _beatAfter(Duration.zero, beats: 1);
    }
  }

  void _beatAfter(Duration delay, {required int beats}) {
    _pulse++;
    _pulseBeats = beats;
    _pulseDelay = delay;
  }

  /// Plays or shows the change from [oldWidget]'s steps; whether it played.
  bool _update(SwapTimelineView oldWidget) {
    final from = _statuses(oldWidget.steps);
    final to = _statuses(widget.steps);
    final changed = [
      if (from.length == to.length)
        for (var i = 0; i < to.length; i++)
          if (from[i] != to[i]) i,
    ];
    if (changed.isEmpty) {
      if (from.length != to.length) _snap(to);
      return false;
    }
    if (!widget.animate || !SwapMotion.enabled(context)) {
      _snap(to);
      return false;
    }
    _play(from, to, changed);
    return true;
  }

  void _snap(List<SwapStepStatus> to) {
    _from = to;
    _beats = const [];
    _cascade.value = 1;
  }

  void _play(
    List<SwapStepStatus> from,
    List<SwapStepStatus> to,
    List<int> changed,
  ) {
    final step = SwapMotion.step.inMicroseconds;
    final stride = step - SwapMotion.stepOverlap.inMicroseconds;
    final fill = SwapMotion.fill.inMicroseconds;
    final windows = <int, (int, int, int, int)>{};
    var total = 0;
    for (final (order, index) in changed.indexed) {
      final start = order * stride;
      final fillStart = start + step ~/ 2;
      windows[index] = (start, start + step, fillStart, fillStart + fill);
      total = math.max(total, fillStart + fill);
    }
    // A longer cascade is compressed, never cut short.
    final length = math.min(total, SwapMotion.cascadeLimit.inMicroseconds);
    _from = from;
    _beats = [
      for (var i = 0; i < to.length; i++)
        if (windows[i] case (final a, final b, final c, final d))
          (
            start: a / total,
            end: b / total,
            fillStart: c / total,
            fillEnd: d / total,
          )
        else
          null,
    ];
    _cascade
      ..duration = Duration(microseconds: length)
      ..forward(from: 0);
  }

  Animation<double> _window(double start, double end, Curve curve) =>
      _cascade.drive(CurveTween(curve: Interval(start, end, curve: curve)));

  @override
  void dispose() {
    _cascade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    return Semantics(
      container: true,
      label: LocaleKeys.swapProgressTitle.tr(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++)
              _StepRow(
                step: steps[i],
                last: i == steps.length - 1,
                from: i < _from.length ? _from[i] : steps[i].status,
                beat: i < _beats.length ? _beats[i] : null,
                window: _window,
                duration: _cascade.duration ?? Duration.zero,
                animate: widget.animate,
                pulse: (
                  trigger: _pulse,
                  beats: _pulseBeats,
                  delay: _pulseDelay,
                  active:
                      widget.tracking &&
                      steps[i].status == SwapStepStatus.current,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The pulse a step shows while the swap is on it.
typedef _Pulse = ({Object trigger, int beats, Duration delay, bool active});

/// A step's colours: fill, outline and glyph.
typedef _Colours = (Color background, Color border, Color foreground);

_Colours _coloursOf(
  SwapStepStatus status,
  SwapPalette palette,
) => switch (status) {
  SwapStepStatus.done => (palette.successBg, palette.success, palette.success),
  SwapStepStatus.current => (
    palette.selected,
    palette.brand,
    palette.brandHover,
  ),
  SwapStepStatus.error => (palette.dangerBg, palette.danger, palette.danger),
  SwapStepStatus.cancelled => (
    palette.surfaceHigh,
    palette.textTertiary,
    palette.textTertiary,
  ),
  SwapStepStatus.notStarted => (
    palette.surfaceHigh,
    palette.controlBorder,
    palette.textTertiary,
  ),
};

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.last,
    required this.from,
    required this.beat,
    required this.window,
    required this.duration,
    required this.animate,
    required this.pulse,
  });

  final SwapTimelineStep step;
  final bool last;
  final SwapStepStatus from;
  final _Beat? beat;
  final Animation<double> Function(double start, double end, Curve curve)
  window;
  final Duration duration;
  final bool animate;
  final _Pulse pulse;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final icon = switch (step.status) {
      SwapStepStatus.done => Icons.check_rounded,
      SwapStepStatus.current => Icons.more_horiz_rounded,
      SwapStepStatus.error => Icons.priority_high_rounded,
      SwapStepStatus.cancelled => Icons.close_rounded,
      SwapStepStatus.notStarted => Icons.circle_outlined,
    };
    final statusLabel = switch (step.status) {
      SwapStepStatus.done => LocaleKeys.swapStepCompleted,
      SwapStepStatus.current => LocaleKeys.swapStepCurrent,
      SwapStepStatus.error => LocaleKeys.swapStepError,
      SwapStepStatus.cancelled => LocaleKeys.swapStepCancelled,
      SwapStepStatus.notStarted => LocaleKeys.swapStepNotStarted,
    }.tr(args: [step.title]);
    final emphasised =
        step.status == SwapStepStatus.current ||
        step.status == SwapStepStatus.error;
    final beat = this.beat;
    final done = step.status == SwapStepStatus.done;

    return Semantics(
      label: '$statusLabel. ${step.detail}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  SwapPulse(
                    trigger: pulse.trigger,
                    active: pulse.active,
                    onMount: true,
                    beats: pulse.beats,
                    delay: pulse.delay,
                    color: palette.brand,
                    child: SwapPulse(
                      trigger: done,
                      active: animate && beat != null,
                      color: palette.success,
                      beat: SwapMotion.ring,
                      spread: 10,
                      opacity: 0.4,
                      delay: beat == null
                          ? Duration.zero
                          : duration * beat.start,
                      child: _node(palette, icon, beat),
                    ),
                  ),
                  if (!last)
                    Expanded(
                      child: SwapStepLine(
                        fill: beat != null && done && from != step.status
                            ? window(
                                beat.fillStart,
                                beat.fillEnd,
                                SwapMotion.standard,
                              )
                            : AlwaysStoppedAnimation(done ? 1 : 0),
                        color: palette.border,
                        fillColor: palette.success,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 70),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: SwapText.strong(context).copyWith(
                          color: step.status == SwapStepStatus.notStarted
                              ? palette.textSecondary
                              : palette.text,
                          fontWeight: emphasised
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(step.detail, style: SwapText.small(context)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _node(SwapPalette palette, IconData icon, _Beat? beat) {
    final glyph = Icon(
      icon,
      size: step.status == SwapStepStatus.notStarted ? 10 : 16,
      color: _coloursOf(step.status, palette).$3,
    );
    if (beat == null) return _circle(_coloursOf(step.status, palette), glyph);
    final blend = window(beat.start, beat.end, SwapMotion.standard);
    final (fromBg, fromBorder, _) = _coloursOf(from, palette);
    final (toBg, toBorder, toFg) = _coloursOf(step.status, palette);
    return AnimatedBuilder(
      animation: blend,
      builder: (context, child) => _circle((
        Color.lerp(fromBg, toBg, blend.value)!,
        Color.lerp(fromBorder, toBorder, blend.value)!,
        toFg,
      ), child!),
      child: SwapPaintEffect(
        progress: window(
          beat.start,
          beat.end,
          step.status == SwapStepStatus.error
              ? SwapMotion.error
              : SwapMotion.success,
        ),
        opacity: 0,
        scale: 0.6,
        child: glyph,
      ),
    );
  }

  static Widget _circle(_Colours colours, Widget glyph) => Container(
    width: 32,
    height: 32,
    decoration: BoxDecoration(
      color: colours.$1,
      shape: BoxShape.circle,
      border: Border.all(color: colours.$2, width: 2),
    ),
    child: glyph,
  );
}
