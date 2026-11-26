import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';

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
  /// [status] One status row under the description
  /// [details] Further controls of the section, below its header
  /// [showWarningIndicator] Whether to show a warning indicator next to the title
  /// [warningIndicatorColor] Optional color for the warning indicator (defaults to danger color)
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
    this.status,
    this.details,
    this.showWarningIndicator = false,
    this.warningIndicatorColor,
    this.iconColor,
    this.buttonTextColor,
  }) : assert(
         (actionText == null) == (onActionPressed == null),
         'Provide actionText and onActionPressed together',
       ),
       assert(
         trailingWidget == null || actionText == null,
         'Provide actionText/onActionPressed OR trailingWidget, not both',
       );

  /// Width of a section's action when it sits beside the text.
  static const double actionWidth = 210;

  final Widget icon;
  final String title;
  final String description;
  final String? actionText;
  final VoidCallback? onActionPressed;
  final Widget? trailingWidget;
  final Widget? status;
  final Widget? details;
  final bool showWarningIndicator;
  final Color? warningIndicatorColor;
  final Color? iconColor;
  final Color? buttonTextColor;

  /// Whether a section this wide puts its action beside its text. Sections
  /// that build their own action use it to size that action the same way.
  static bool isWide(BuildContext context, BoxConstraints constraints) =>
      constraints.maxWidth >= 700 &&
      MediaQuery.textScalerOf(context).scale(1) <= 1.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = isWide(context, constraints);
        return SecuritySectionCard(
          padding: wide
              ? const EdgeInsets.all(16)
              : const EdgeInsets.symmetric(horizontal: 12),
          child: wide ? _buildRowLayout() : _buildColumnLayout(),
        );
      },
    );
  }

  /// Builds column layout for mobile or constrained desktop widths
  Widget _buildColumnLayout() {
    final trailing = _buildTrailingWidget(fullWidth: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 24),
        _ActionIcon(icon: icon, iconColor: iconColor),
        const SizedBox(height: 28),
        _ActionTitle(
          title: title,
          showWarningIndicator: showWarningIndicator,
          warningIndicatorColor: warningIndicatorColor,
        ),
        const SizedBox(height: 12),
        _ActionBody(description: description),
        if (status != null) ...[
          const SizedBox(height: 12),
          // Short statuses sit under the centred text; long ones wrap.
          Center(child: IntrinsicWidth(child: status)),
        ],
        if (trailing != null) ...[const SizedBox(height: 8), trailing],
        if (details != null) ...[
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: details),
        ],
        SizedBox(height: details != null || trailing == null ? 16 : 6),
      ],
    );
  }

  /// Builds row layout for wide desktop screens
  Widget _buildRowLayout() {
    final trailing = _buildTrailingWidget();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  if (status != null) ...[const SizedBox(height: 8), status!],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 16), trailing],
            const SizedBox(width: 16),
          ],
        ),
        if (details != null)
          Padding(
            // Aligned with the text, past the icon.
            padding: const EdgeInsets.fromLTRB(88, 16, 16, 0),
            child: details,
          ),
      ],
    );
  }

  /// Builds the trailing widget (either custom widget or default action button)
  Widget? _buildTrailingWidget({bool fullWidth = false}) {
    if (trailingWidget != null) return trailingWidget;
    if (actionText == null) return null;

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

    return ExcludeSemantics(
      child: DefaultIconStyle(color: defaultColor, size: 50.0, child: icon),
    );
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
    final palette = AppPalette.of(context);
    final textAlign = isInRowLayout ? TextAlign.left : TextAlign.center;
    final text = Semantics(
      header: true,
      child: Text(
        title,
        style: SecuritySectionText.title(context),
        textAlign: textAlign,
        overflow: TextOverflow.visible,
        softWrap: true,
      ),
    );

    if (!showWarningIndicator) return text;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: warningIndicatorColor ?? palette.danger,
            borderRadius: BorderRadius.circular(7 / 2),
          ),
        ),
        const SizedBox(width: 7),
        Flexible(child: text),
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

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100),
      child: Text(
        description,
        style: SecuritySectionText.body(context),
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
    final palette = AppPalette.of(context);
    final width = fullWidth ? double.infinity : SecurityActionPlate.actionWidth;
    const height = 48.0;

    return UiPrimaryButton(
      expandForText: true,
      onPressed: onActionPressed,
      width: width,
      height: height,
      text: actionText,
      textStyle: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: buttonTextColor ?? palette.onBrand),
    );
  }
}
