import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Upstream Material passkey symbol, matching the system credential vocabulary.
/// Source and Apache license are retained under third_party/notices.
class WalletPasskeyIcon extends StatelessWidget {
  const WalletPasskeyIcon({this.size = 24, this.color, super.key});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/ui_icons/passkey.svg',
    width: size,
    height: size,
    excludeFromSemantics: true,
    colorFilter: ColorFilter.mode(
      color ??
          IconTheme.of(context).color ??
          Theme.of(context).colorScheme.onSurface,
      BlendMode.srcIn,
    ),
  );
}
