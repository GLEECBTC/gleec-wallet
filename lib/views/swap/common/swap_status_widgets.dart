import 'package:flutter/material.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';
import 'package:web_dex/views/swap/motion/swap_motion.dart';

/// A small pill label: "Best net return", "Expires in 18s".
class SwapBadge extends StatelessWidget {
  const SwapBadge({
    required this.label,
    this.tone = SwapTone.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final SwapTone tone;
  final IconData? icon;

  static const _padding = EdgeInsets.symmetric(horizontal: 9, vertical: 4);

  static TextStyle _labelStyle(BuildContext context) =>
      SwapText.small(context).copyWith(fontWeight: FontWeight.w700);

  /// How wide a badge reading [label], without an icon, is on one line.
  static double widthOf(BuildContext context, String label) =>
      _padding.horizontal +
      SwapText.widthOf(context, label, _labelStyle(context));

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final foreground = palette.toneColor(tone);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.toneBackground(tone),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.toneBorder(tone)),
        ),
        child: Padding(
          padding: _padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  style: _labelStyle(context).copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tinted box that explains something: a warning, a note, a protection.
class SwapCallout extends StatelessWidget {
  const SwapCallout({
    required this.message,
    this.title,
    this.tone = SwapTone.info,
    this.icon,
    this.action,
    this.liveRegion = false,
    super.key,
  });

  final String? title;
  final String message;
  final SwapTone tone;
  final IconData? icon;
  final Widget? action;
  final bool liveRegion;

  static IconData defaultIcon(SwapTone tone) => switch (tone) {
    SwapTone.warning || SwapTone.pending => Icons.warning_amber_rounded,
    SwapTone.danger => Icons.error_outline_rounded,
    SwapTone.success => Icons.verified_user_outlined,
    _ => Icons.info_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final title = this.title;
    return Semantics(
      liveRegion: liveRegion,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.toneBackground(tone),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.toneBorder(tone)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  icon ?? defaultIcon(tone),
                  size: 20,
                  color: palette.toneColor(tone),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(title, style: SwapText.strong(context)),
                      const SizedBox(height: 4),
                    ],
                    Text(message, style: SwapText.body(context)),
                    if (action != null) ...[const SizedBox(height: 6), action!],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A one-line message under a control: an error, a warning or a hint.
class SwapHelperLine extends StatelessWidget {
  const SwapHelperLine({
    required this.text,
    this.tone = SwapTone.neutral,
    this.icon,
    super.key,
  });

  final String text;
  final SwapTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final color = switch (tone) {
      SwapTone.danger => palette.danger,
      SwapTone.warning || SwapTone.pending => palette.warning,
      _ => palette.textSecondary,
    };
    final glyph =
        icon ??
        switch (tone) {
          SwapTone.danger => Icons.error_outline_rounded,
          SwapTone.warning || SwapTone.pending => Icons.warning_amber_rounded,
          _ => Icons.info_outline_rounded,
        };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(glyph, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: SwapText.small(context).copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How a [SwapStatusHero] moves when what it shows changes.
class SwapHeroMotion {
  const SwapHeroMotion({
    this.animate = true,
    this.iconFrom = 0.8,
    this.iconTurns = 0,
    this.iconCurve = SwapMotion.enter,
    this.iconDuration = SwapMotion.pop,
    this.ring,
    this.ringColor,
  });

  /// Whether a change animates; otherwise it shows at once.
  final bool animate;

  /// How a new icon arrives: from this share of its size, unwinding
  /// [iconTurns] (anticlockwise), along [iconCurve].
  final double iconFrom;
  final double iconTurns;
  final Curve iconCurve;
  final Duration iconDuration;

  /// A ring spreads once from the tile, in [ringColor], each time this
  /// changes to something other than null.
  final Object? ring;
  final Color? ringColor;
}

/// A large centred status: an icon tile, a heading and a line of copy.
///
/// With [motion], a new tone blends in, a new icon pops in and new copy rises
/// in; without it, the hero is still.
class SwapStatusHero extends StatelessWidget {
  const SwapStatusHero({
    required this.icon,
    required this.title,
    this.body,
    this.tone = SwapTone.brand,
    this.liveRegion = true,
    this.action,
    this.motion,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;
  final SwapTone tone;
  final bool liveRegion;
  final Widget? action;
  final SwapHeroMotion? motion;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final (background, foreground) = switch (tone) {
      SwapTone.brand ||
      SwapTone.neutral => (palette.selected, palette.brandHover),
      _ => (palette.toneBackground(tone), palette.toneColor(tone)),
    };
    final body = this.body;
    final motion = this.motion;
    final glyph = Icon(icon, size: 30, color: foreground);
    final Widget titleText = Text(
      title,
      style: SwapText.heading(context),
      textAlign: TextAlign.center,
    );
    final Widget? bodyText = body == null
        ? null
        : Text(
            body,
            style: SwapText.body(context),
            textAlign: TextAlign.center,
          );
    final copy = [
      Semantics(
        header: true,
        child: motion == null ? titleText : _rise(title, motion, titleText),
      ),
      if (bodyText != null) ...[
        const SizedBox(height: 8),
        if (motion == null)
          bodyText
        else
          _rise(
            body,
            motion,
            bodyText,
            delay: const Duration(milliseconds: 40),
          ),
      ],
      if (action != null) ...[const SizedBox(height: 16), action!],
    ];
    return Semantics(
      liveRegion: liveRegion,
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          children: [
            if (motion == null)
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: glyph,
              )
            else
              _movingTile(context, motion, palette, background, glyph),
            const SizedBox(height: 14),
            if (motion == null)
              ...copy
            else
              SwapSmoothSize(
                animate: motion.animate,
                alignment: Alignment.topCenter,
                child: Column(children: copy),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _rise(
    Object? key,
    SwapHeroMotion motion,
    Widget child, {
    Duration delay = Duration.zero,
  }) => SwapReveal(
    revealKey: key,
    onMount: false,
    animate: motion.animate,
    delay: delay,
    child: child,
  );

  Widget _movingTile(
    BuildContext context,
    SwapHeroMotion motion,
    SwapPalette palette,
    Color background,
    Widget glyph,
  ) => SwapPulse(
    trigger: motion.ring,
    active: motion.animate && motion.ring != null,
    color: motion.ringColor ?? palette.success,
    beat: SwapMotion.ring,
    spread: 28,
    opacity: 0.45,
    borderRadius: BorderRadius.circular(22),
    child: AnimatedContainer(
      duration: motion.animate
          ? SwapMotion.of(context, SwapMotion.colour)
          : Duration.zero,
      curve: SwapMotion.standard,
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: SwapPop(
        trigger: icon,
        animate: motion.animate,
        from: motion.iconFrom,
        turns: motion.iconTurns,
        curve: motion.iconCurve,
        duration: motion.iconDuration,
        child: glyph,
      ),
    ),
  );
}

/// One of the recovery questions: "What happened?", "Where are the funds?".
class SwapQuestion extends StatelessWidget {
  const SwapQuestion({
    required this.eyebrow,
    this.title,
    this.body,
    this.trailing,
    this.divider = true,
    super.key,
  });

  final String eyebrow;
  final String? title;
  final String? body;
  final Widget? trailing;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final title = this.title;
    final body = this.body;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divider ? Border(top: BorderSide(color: palette.border)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(eyebrow.toUpperCase(), style: SwapText.eyebrow(context)),
              if (title != null) ...[
                const SizedBox(height: 7),
                Text(title, style: SwapText.strong(context)),
              ],
              if (body != null) ...[
                const SizedBox(height: 5),
                Text(body, style: SwapText.body(context)),
              ],
              if (trailing != null) ...[const SizedBox(height: 4), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small count bubble.
class SwapCountDot extends StatelessWidget {
  const SwapCountDot({required this.count, this.tone, super.key});

  final int count;
  final SwapTone? tone;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final background = switch (tone) {
      SwapTone.warning => palette.warning,
      SwapTone.danger => palette.danger,
      _ => palette.brand,
    };
    final foreground = switch (tone) {
      SwapTone.warning => palette.canvas,
      SwapTone.danger => palette.canvas,
      _ => palette.onBrand,
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: SwapText.small(context).copyWith(
          color: foreground,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          height: 1.2,
        ),
      ),
    );
  }
}
