import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// The swap screens' names for the shared colour tokens, which moved to the
/// UI kit once the wallet screens adopted them. New code uses [AppPalette].
typedef SwapPalette = AppPalette;

/// The swap screens' name for [AppTone].
typedef SwapTone = AppTone;

/// The swap screens' name for the shared type scale, [AppText].
typedef SwapText = AppText;

/// Shared geometry.
abstract final class SwapGeometry {
  /// The readable column width of every swap screen.
  static const contentWidth = 576.0;

  /// The width of a side panel on a wide screen.
  static const panelWidth = 520.0;

  /// Width from which review and pickers open beside the form, not over it.
  static const sidePanelBreakpoint = 960.0;

  /// The minimum interactive size.
  static const touchTarget = 48.0;

  /// Width below which the swap screens take their phone layout, with
  /// tighter cards.
  static const compactWidth = 600.0;

  /// Height below which a screen's main action is pinned, as on a phone
  /// held sideways.
  static const shortHeight = 560.0;

  /// Whether the window is phone-sized.
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < compactWidth;

  /// Whether a screen's main action stays pinned above the content, so it
  /// never scrolls out of reach.
  static bool pinsAction(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width < compactWidth || size.height < shortHeight;
  }
}
