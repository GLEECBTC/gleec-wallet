import 'package:flutter/material.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';

/// Rings that spread from [child]'s outline and fade: [beats] of them, each
/// time [trigger] changes, and once when it first appears with [onMount].
///
/// A burst lasts at most five seconds and then stops, so the pulse never asks
/// a user to wait motion out (WCAG 2.2.2). The rings are painted behind the
/// child and beyond its bounds; they take no taps and add nothing for screen
/// readers. Nothing plays while [active] is false or motion is off.
class SwapPulse extends StatefulWidget {
  const SwapPulse({
    required this.child,
    required this.trigger,
    required this.color,
    this.beats = 1,
    this.active = true,
    this.onMount = false,
    this.delay = Duration.zero,
    this.beat = SwapMotion.beat,
    this.spacing = SwapMotion.beatSpacing,
    this.spread = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(999)),
    this.opacity = 0.5,
    this.strokeWidth = 2,
    super.key,
  }) : assert(beats >= 1 && beats <= 3);

  final Widget child;
  final Object? trigger;
  final Color color;
  final int beats;
  final bool active;
  final bool onMount;
  final Duration delay;
  final Duration beat;
  final Duration spacing;

  /// How far past the child's outline a ring travels.
  final double spread;
  final BorderRadiusGeometry borderRadius;

  /// A ring's opacity as it leaves the outline; it fades to nothing.
  final double opacity;
  final double strokeWidth;

  /// How long one burst of [beats] runs.
  Duration get burst => delay + spacing * (beats - 1) + beat;

  @override
  State<SwapPulse> createState() => _SwapPulseState();
}

class _SwapPulseState extends State<SwapPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _started = false;
  int _beats = 1;

  @override
  void initState() {
    super.initState();
    assert(widget.burst <= const Duration(seconds: 5));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!SwapMotion.enabled(context)) {
      _stop();
    } else if (!_started && widget.onMount) {
      _play();
    }
    _started = true;
  }

  @override
  void didUpdateWidget(SwapPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    assert(widget.burst <= const Duration(seconds: 5));
    if (!widget.active) {
      _stop();
    } else if (widget.trigger != oldWidget.trigger) {
      _play();
    }
  }

  void _play() {
    if (!widget.active || !SwapMotion.enabled(context)) return;
    _beats = widget.beats;
    _controller
      ..duration = widget.burst
      ..forward(from: 0);
  }

  void _stop() {
    _controller
      ..stop()
      ..value = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _PulsePainter(
        progress: _controller,
        beats: _beats,
        delay: widget.delay,
        beat: widget.beat,
        spacing: widget.spacing,
        color: widget.color,
        spread: widget.spread,
        borderRadius: widget.borderRadius.resolve(
          Directionality.maybeOf(context) ?? TextDirection.ltr,
        ),
        opacity: widget.opacity,
        strokeWidth: widget.strokeWidth,
      ),
      child: widget.child,
    ),
  );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.progress,
    required this.beats,
    required this.delay,
    required this.beat,
    required this.spacing,
    required this.color,
    required this.spread,
    required this.borderRadius,
    required this.opacity,
    required this.strokeWidth,
  }) : super(repaint: progress);

  final AnimationController progress;
  final int beats;
  final Duration delay;
  final Duration beat;
  final Duration spacing;
  final Color color;
  final double spread;
  final BorderRadius borderRadius;
  final double opacity;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final total = progress.duration;
    if (!progress.isAnimating || total == null) return;
    final elapsed = total * progress.value;
    final outline = borderRadius.toRRect(Offset.zero & size);
    for (var i = 0; i < beats; i++) {
      final since = elapsed - delay - spacing * i;
      final t = since.inMicroseconds / beat.inMicroseconds;
      if (t <= 0 || t >= 1) continue;
      final eased = Curves.easeOutCubic.transform(t);
      canvas.drawRRect(
        outline.inflate(spread * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth + (0.5 - strokeWidth) * eased
          ..color = color.withValues(alpha: opacity * (1 - eased)),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.beats != beats ||
      oldDelegate.delay != delay ||
      oldDelegate.beat != beat ||
      oldDelegate.spacing != spacing ||
      oldDelegate.color != color ||
      oldDelegate.spread != spread ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.opacity != opacity ||
      oldDelegate.strokeWidth != strokeWidth;
}
