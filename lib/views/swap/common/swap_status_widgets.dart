import 'package:flutter/material.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

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
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
                  style: SwapText.small(
                    context,
                  ).copyWith(color: foreground, fontWeight: FontWeight.w700),
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

/// A large centred status: an icon tile, a heading and a line of copy.
class SwapStatusHero extends StatelessWidget {
  const SwapStatusHero({
    required this.icon,
    required this.title,
    this.body,
    this.tone = SwapTone.brand,
    this.liveRegion = true,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? body;
  final SwapTone tone;
  final bool liveRegion;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = SwapPalette.of(context);
    final (background, foreground) = switch (tone) {
      SwapTone.brand ||
      SwapTone.neutral => (palette.selected, palette.brandHover),
      _ => (palette.toneBackground(tone), palette.toneColor(tone)),
    };
    final body = this.body;
    return Semantics(
      liveRegion: liveRegion,
      container: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(icon, size: 30, color: foreground),
            ),
            const SizedBox(height: 14),
            Semantics(
              header: true,
              child: Text(
                title,
                style: SwapText.heading(context),
                textAlign: TextAlign.center,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body,
                style: SwapText.body(context),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
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
