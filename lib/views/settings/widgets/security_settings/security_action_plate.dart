import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

/// Generic reusable widget for security actions in the settings page.
///
/// This widget provides a consistent layout for security-related actions
/// with an icon, title, description, and action button. It adapts to both
/// mobile and desktop layouts.
class SecurityActionPlate extends StatelessWidget {
  /// Creates a new SecurityActionPlate widget.
  ///
  /// [icon] The icon widget to display for this security action
  /// [title] The title text for the security action
  /// [description] The description text explaining the action
  /// [actionText] The text for the action button (if not using custom trailing widget)
  /// [onActionPressed] Callback when the action button is pressed (if not using custom trailing widget)
  /// [trailingWidget] Custom widget to display instead of the default action button
  /// [showWarningIndicator] Whether to show a warning indicator next to the title
  /// [warningIndicatorColor] Optional color for the warning indicator (defaults to decrease color)
  /// [iconColor] Optional color for the icon (defaults to primary color)
  /// [buttonTextColor] Optional color for the button text (defaults to theme color)
  const SecurityActionPlate({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionText,
    this.onActionPressed,
    this.trailingWidget,
    this.showWarningIndicator = false,
    this.warningIndicatorColor,
    this.iconColor,
    this.buttonTextColor,
  }) : assert(
         (actionText != null &&
                 onActionPressed != null &&
                 trailingWidget == null) ||
             (trailingWidget != null &&
                 actionText == null &&
                 onActionPressed == null),
         'Either provide actionText/onActionPressed OR trailingWidget, but not both',
       );

  final Widget icon;
  final String title;
  final String description;
  final String? actionText;
  final VoidCallback? onActionPressed;
  final Widget? trailingWidget;
  final bool showWarningIndicator;
  final Color? warningIndicatorColor;
  final Color? iconColor;
  final Color? buttonTextColor;

  @override
  Widget build(BuildContext context) {
    return _ResponsiveBody(
      icon: icon,
      title: title,
      description: description,
      actionText: actionText,
      onActionPressed: onActionPressed,
      trailingWidget: trailingWidget,
      showWarningIndicator: showWarningIndicator,
      warningIndicatorColor: warningIndicatorColor,
      iconColor: iconColor,
      buttonTextColor: buttonTextColor,
    );
  }
}

/// Single responsive widget that handles all layout cases.
/// Adapts between mobile/desktop and column/row layouts based on screen size.
class _ResponsiveBody extends StatelessWidget {
  const _ResponsiveBody({
    required this.icon,
    required this.title,
    required this.description,
    this.actionText,
    this.onActionPressed,
    this.trailingWidget,
    required this.showWarningIndicator,
    this.warningIndicatorColor,
    this.iconColor,
    this.buttonTextColor,
  });

  final Widget icon;
  final String title;
  final String description;
  final String? actionText;
  final VoidCallback? onActionPressed;
  final Widget? trailingWidget;
  final bool showWarningIndicator;
  final Color? warningIndicatorColor;
  final Color? iconColor;
  final Color? buttonTextColor;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumnLayout =
            constraints.maxWidth < 700 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.5;
        return Container(
          padding: _getPadding(!useColumnLayout),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: useColumnLayout
              ? _buildColumnLayout(false)
              : _buildRowLayout(),
        );
      },
    );
  }

  /// Returns appropriate padding based on platform
  EdgeInsets _getPadding(bool isDesktop) {
    return isDesktop
        ? const EdgeInsets.all(16)
        : const EdgeInsets.symmetric(horizontal: 12);
  }

  /// Builds column layout for mobile or constrained desktop widths
  Widget _buildColumnLayout(bool isDesktop) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(height: isDesktop ? 16 : 24),
        _ActionIcon(icon: icon, iconColor: iconColor),
        SizedBox(height: isDesktop ? 16 : 28),
        _ActionTitle(
          title: title,
          showWarningIndicator: showWarningIndicator,
          warningIndicatorColor: warningIndicatorColor,
        ),
        const SizedBox(height: 12),
        _ActionBody(description: description),
        SizedBox(height: isDesktop ? 16 : 8),
        _buildTrailingWidget(fullWidth: true),
        SizedBox(height: isDesktop ? 16 : 6),
      ],
    );
  }

  /// Builds row layout for wide desktop screens
  Widget _buildRowLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(width: 12),
            _ActionIcon(icon: icon, iconColor: iconColor),
            const SizedBox(width: 26),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ActionTitle(
                    title: title,
                    showWarningIndicator: showWarningIndicator,
                    warningIndicatorColor: warningIndicatorColor,
                    isInRowLayout: true,
                  ),
                  const SizedBox(height: 8),
                  _ActionBody(description: description, isInRowLayout: true),
                ],
              ),
            ),
            const SizedBox(width: 16),
            _buildTrailingWidget(),
            const SizedBox(width: 16),
          ],
        ),
      ],
    );
  }

  /// Builds the trailing widget (either custom widget or default action button)
  Widget _buildTrailingWidget({bool fullWidth = false}) {
    if (trailingWidget != null) {
      return trailingWidget!;
    }

    return _ActionButton(
      fullWidth: fullWidth,
      actionText: actionText!,
      onActionPressed: onActionPressed!,
      buttonTextColor: buttonTextColor,
    );
  }
}

/// Icon widget for the security action.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({required this.icon, this.iconColor});

  final Widget icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final defaultColor = iconColor ?? Theme.of(context).colorScheme.primary;

    return DefaultIconStyle(color: defaultColor, size: 50.0, child: icon);
  }
}

/// Default icon style widget that applies default styling to child icons.
/// Similar to Flutter's DefaultTextStyle pattern.
/// TODO: Further enhancements so that it only overrides the styling values
/// if an icon is passed and it doesn't have one applied to be more in line
/// with `DefaultTextStyle`. Ideally, it should apply recursively to nested
/// `Icon`s.
class DefaultIconStyle extends StatelessWidget {
  const DefaultIconStyle({
    super.key,
    required this.color,
    required this.size,
    required this.child,
  });

  final Color color;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IconTheme(
      data: IconThemeData(color: color, size: size),
      child: child,
    );
  }
}

/// Title widget for the security action.
///
/// Displays the action title with an optional warning indicator
/// to emphasize security-sensitive operations.
class _ActionTitle extends StatelessWidget {
  const _ActionTitle({
    required this.title,
    required this.showWarningIndicator,
    this.warningIndicatorColor,
    this.isInRowLayout = false,
  });

  final String title;
  final bool showWarningIndicator;
  final Color? warningIndicatorColor;
  final bool isInRowLayout;

  @override
  Widget build(BuildContext context) {
    final textAlign = isInRowLayout ? TextAlign.left : TextAlign.center;
    // TODO: See if possible to refactor theme to provide this text style in
    // accordance with the Material Design 3 typography guidelines. This is
    // used in other places as well. e.g. The seed backup notification.
    final titleStyle = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.w700, fontSize: 16);

    if (!showWarningIndicator) {
      return Text(
        title,
        style: titleStyle,
        textAlign: textAlign,
        overflow: TextOverflow.visible,
        softWrap: true,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: warningIndicatorColor ?? theme.custom.decreaseColor,
            borderRadius: BorderRadius.circular(7 / 2),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            title,
            style: titleStyle,
            textAlign: textAlign,
            overflow: TextOverflow.visible,
            softWrap: true,
          ),
        ),
      ],
    );
  }
}

/// Description widget explaining the purpose of the security action.
class _ActionBody extends StatelessWidget {
  const _ActionBody({required this.description, this.isInRowLayout = false});

  final String description;
  final bool isInRowLayout;

  @override
  Widget build(BuildContext context) {
    final textAlign = isInRowLayout ? TextAlign.left : TextAlign.center;
    // TODO: See if possible to refactor theme to provide this text style in
    // accordance with the Material Design 3 typography guidelines. This is
    // used in other places as well. e.g. The seed backup notification.
    final descriptionStyle = Theme.of(
      context,
    ).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w500, fontSize: 14);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100),
      child: Text(
        description,
        style: descriptionStyle,
        textAlign: textAlign,
        overflow: TextOverflow.visible,
        softWrap: true,
      ),
    );
  }
}

/// Button widget for triggering the security action.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.actionText,
    required this.onActionPressed,
    this.buttonTextColor,
    this.fullWidth = false,
  });

  final bool fullWidth;
  final String actionText;
  final VoidCallback onActionPressed;
  final Color? buttonTextColor;

  @override
  Widget build(BuildContext context) {
    final width = fullWidth ? double.infinity : 210.0;
    const height = 48.0;

    return UiPrimaryButton(
      expandForText: true,
      onPressed: onActionPressed,
      width: width,
      height: height,
      text: actionText,
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: buttonTextColor ?? theme.custom.defaultGradientButtonTextColor,
      ),
    );
  }
}
