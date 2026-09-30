import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:web_dex/views/swap/motion/swap_motion_tokens.dart';

part 'swap_effect_render.dart';

/// Brings [child] in: it starts faded and shifted by [offset], and settles
/// where it is laid out.
///
/// Plays when it first appears ([onMount]) and each time [revealKey] changes.
/// With [animate] false a change simply shows. Enter-only: the old content is
/// gone at once, so there is never a second copy of anything.
class SwapReveal extends StatelessWidget {
  const SwapReveal({
    required this.child,
    this.revealKey,
    this.onMount = true,
    this.animate = true,
    this.offset = const Offset(0, 10),
    this.delay = Duration.zero,
    this.duration = SwapMotion.reveal,
    this.curve = SwapMotion.enter,
    super.key,
  });

  /// A screen arriving from the direction of travel: from the end edge going
  /// forward, from the start edge going back. Never on first mount.
  const SwapReveal.screen({
    required this.child,
    required this.revealKey,
    required bool forward,
    super.key,
  }) : onMount = false,
       animate = true,
       offset = forward ? const Offset(24, 0) : const Offset(-24, 0),
       delay = Duration.zero,
       duration = SwapMotion.screen,
       curve = SwapMotion.enter;

  final Widget child;
  final Object? revealKey;
  final bool onMount;
  final bool animate;
  final Offset offset;
  final Duration delay;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) => _EffectPlayer(
    trigger: revealKey,
    onMount: onMount,
    animate: animate,
    delay: delay,
    duration: duration,
    curve: curve,
    start: _EffectStart(opacity: 0, offset: offset),
    alignment: Alignment.center,
    child: child,
  );
}

/// Pops [child] in from [from] of its size each time [trigger] changes,
/// fading in with [fade]. [turns] adds a spin that unwinds as it settles:
/// positive turns unwind anticlockwise.
class SwapPop extends StatelessWidget {
  const SwapPop({
    required this.child,
    required this.trigger,
    this.from = 0.8,
    this.fade = true,
    this.turns = 0,
    this.onMount = false,
    this.animate = true,
    this.delay = Duration.zero,
    this.duration = SwapMotion.pop,
    this.curve = SwapMotion.enter,
    this.alignment = Alignment.center,
    super.key,
  });

  final Widget child;
  final Object? trigger;
  final double from;
  final bool fade;
  final double turns;
  final bool onMount;
  final bool animate;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => _EffectPlayer(
    trigger: trigger,
    onMount: onMount,
    animate: animate,
    delay: delay,
    duration: duration,
    curve: curve,
    start: _EffectStart(opacity: fade ? 0 : 1, scale: from, turns: turns),
    alignment: alignment,
    child: child,
  );
}

class _EffectPlayer extends StatefulWidget {
  const _EffectPlayer({
    required this.trigger,
    required this.onMount,
    required this.animate,
    required this.delay,
    required this.duration,
    required this.curve,
    required this.start,
    required this.alignment,
    required this.child,
  });

  final Object? trigger;
  final bool onMount;
  final bool animate;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final _EffectStart start;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  State<_EffectPlayer> createState() => _EffectPlayerState();
}

class _EffectPlayerState extends State<_EffectPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Animation<double> _progress = kAlwaysCompleteAnimation;
  CurvedAnimation? _curve;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!SwapMotion.enabled(context)) {
      _controller.value = 1;
    } else if (!_started && widget.onMount && widget.animate) {
      _play();
    }
    _started = true;
  }

  @override
  void didUpdateWidget(_EffectPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger == oldWidget.trigger) return;
    if (widget.animate && SwapMotion.enabled(context)) {
      _play();
    } else {
      _controller.value = 1;
    }
  }

  void _play() {
    final total = widget.delay + widget.duration;
    if (total == Duration.zero) return;
    final begin = widget.delay.inMicroseconds / total.inMicroseconds;
    _curve?.dispose();
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, 1, curve: widget.curve),
    );
    _progress = _curve!;
    _controller
      ..duration = total
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _curve?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SwapEffect(
    progress: _progress,
    start: widget.start,
    alignment: widget.alignment,
    child: widget.child,
  );
}

/// Presses [child] down slightly while a pointer is down on it.
///
/// It listens without joining the gesture arena, so the child's own taps and
/// long presses are untouched; moving past the touch slop lets go.
class SwapPressScale extends StatefulWidget {
  const SwapPressScale({
    required this.child,
    this.enabled = true,
    this.scale = 0.97,
    super.key,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<SwapPressScale> createState() => _SwapPressScaleState();
}

class _SwapPressScaleState extends State<SwapPressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SwapMotion.press,
    reverseDuration: SwapMotion.release,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: SwapMotion.standard,
  );
  late final Animation<double> _progress = ReverseAnimation(_curve);
  Offset? _down;

  void _press(PointerDownEvent event) {
    if (!widget.enabled || !SwapMotion.enabled(context)) return;
    _down = event.position;
    _controller.forward();
  }

  void _move(PointerMoveEvent event) {
    final down = _down;
    if (down != null && (event.position - down).distance > kTouchSlop) {
      _release();
    }
  }

  void _release([PointerEvent? _]) {
    _down = null;
    _controller.reverse();
  }

  @override
  void didUpdateWidget(SwapPressScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _release();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _press,
    onPointerMove: _move,
    onPointerUp: _release,
    onPointerCancel: _release,
    child: _SwapEffect(
      progress: _progress,
      start: _EffectStart(scale: widget.scale),
      alignment: Alignment.center,
      child: widget.child,
    ),
  );
}
