import 'package:flutter/material.dart';

enum DexViewportTier { narrowPhone, phone, tablet, desktop, wideDesktop }

/// Advanced DEX layout values derived from the local available width.
///
/// The tiers deliberately include each visual contract width: 375, 390, 768,
/// 1024, and 1440 logical pixels. No device or orientation assumptions are
/// involved, so resizable desktop and split-screen windows use the same rules.
@immutable
class DexResponsiveSpec {
  const DexResponsiveSpec._({
    required this.tier,
    required this.gutter,
    required this.availableWidth,
  });

  factory DexResponsiveSpec.fromWidth(double width) {
    if (width <= 375) {
      return DexResponsiveSpec._(
        tier: DexViewportTier.narrowPhone,
        gutter: 12,
        availableWidth: width,
      );
    }
    if (width < 768) {
      return DexResponsiveSpec._(
        tier: DexViewportTier.phone,
        gutter: 16,
        availableWidth: width,
      );
    }
    if (width < 1024) {
      return DexResponsiveSpec._(
        tier: DexViewportTier.tablet,
        gutter: 20,
        availableWidth: width,
      );
    }
    if (width < 1440) {
      return DexResponsiveSpec._(
        tier: DexViewportTier.desktop,
        gutter: 24,
        availableWidth: width,
      );
    }
    return DexResponsiveSpec._(
      tier: DexViewportTier.wideDesktop,
      gutter: 32,
      availableWidth: width,
    );
  }

  final DexViewportTier tier;
  final double gutter;
  final double availableWidth;

  bool get usesMobileLists => availableWidth < 1024;
  bool get usesStackedTradingLayout => availableWidth < 1024;
  double get maxContentWidth => 1320;
  double get orderbookWidth => tier == DexViewportTier.desktop ? 320 : 380;
}
