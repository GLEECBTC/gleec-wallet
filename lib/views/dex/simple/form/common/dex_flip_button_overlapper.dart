import 'package:flutter/material.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_flip_button.dart';

class DexFlipButtonOverlapper extends StatelessWidget {
  final Future<bool> Function()? onTap;
  final Widget topWidget;
  final Widget bottomWidget;
  final double offsetTop;

  const DexFlipButtonOverlapper({
    Key? key,
    required this.onTap,
    required this.topWidget,
    required this.bottomWidget,
    this.offsetTop = 84,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        topWidget,
        SizedBox(height: 56, child: DexFlipButton(onTap: onTap)),
        bottomWidget,
      ],
    );
  }
}
