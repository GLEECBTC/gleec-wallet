import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// #644: We want the password to be obscured most of the time
/// in order to workaround the problem of some devices ignoring `TYPE_TEXT_FLAG_NO_SUGGESTIONS`,
/// https://github.com/flutter/engine/blob/d1c71e5206bd9546f4ff64b7336c4e74e3f4ccfd/shell/platform/android/io/flutter/plugin/editing/TextInputPlugin.java#L93-L99
class PasswordVisibilityControl extends StatefulWidget {
  const PasswordVisibilityControl({
    required this.onVisibilityChange,
    this.isObscured,
    this.showLabel,
    this.hideLabel,
  });
  final void Function(bool) onVisibilityChange;
  final bool? isObscured;
  final String? showLabel;
  final String? hideLabel;

  @override
  State<PasswordVisibilityControl> createState() =>
      _PasswordVisibilityControlState();
}

class _PasswordVisibilityControlState extends State<PasswordVisibilityControl> {
  bool _isObscured = true;
  bool get _obscured => widget.isObscured ?? _isObscured;

  void _setObscureTo(bool isObscured) {
    if (!mounted) {
      return;
    }
    setState(() {
      _isObscured = isObscured;
    });
    widget.onVisibilityChange(_isObscured);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _obscured
          ? widget.showLabel ?? 'authShowPassword'.tr()
          : widget.hideLabel ?? 'authHidePassword'.tr(),
      onPressed: () => _setObscureTo(!_obscured),
      icon: Icon(
        _obscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        color: Theme.of(
          context,
        ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
      ),
    );
  }
}
