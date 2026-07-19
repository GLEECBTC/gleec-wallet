import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';

class DexInfoContainer extends StatelessWidget {
  final List<Widget> children;

  const DexInfoContainer({Key? key, required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    return Container(
      padding: EdgeInsets.all(geometry.space12),
      decoration: BoxDecoration(
        color: colors.surfaceHigh,
        border: Border.all(color: colors.border, width: 1.0),
        borderRadius: geometry.borderRadius16,
      ),
      child: Column(children: children),
    );
  }
}
