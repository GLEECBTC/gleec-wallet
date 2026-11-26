import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class SettingsContentWrapper extends StatelessWidget {
  const SettingsContentWrapper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 15),
        decoration: AppSurface.card(palette),
        child: child,
      ),
    );
  }
}
