import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/common/app_assets.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

class DexFlipButton extends StatefulWidget {
  final Future<bool> Function()? onTap;

  const DexFlipButton({Key? key, this.onTap}) : super(key: key);

  @override
  DexFlipButtonState createState() => DexFlipButtonState();
}

class DexFlipButtonState extends State<DexFlipButton> {
  double _rotation = 0;

  @override
  Widget build(BuildContext context) {
    final colors = GleecColorTokens.of(context);
    final geometry = GleecGeometry.of(context);
    final motion = GleecMotion.of(context);
    return Center(
      child: Tooltip(
        message: LocaleKeys.swap.tr(),
        child: Semantics(
          button: true,
          enabled: widget.onTap != null,
          child: InkWell(
            borderRadius: geometry.borderRadius24,
            onTap: () async {
              if (widget.onTap != null) {
                if (await widget.onTap!()) {
                  setState(() {
                    _rotation = (_rotation + 180) % 360;
                  });
                }
              }
            },
            child: Opacity(
              opacity: widget.onTap == null ? 0.5 : 1.0,
              child: SizedBox.square(
                dimension: 56,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surfaceRaised,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.borderStrong),
                    boxShadow: geometry.surfaceShadow(colors),
                  ),
                  child: Center(
                    child: AnimatedRotation(
                      turns: _rotation / 360,
                      duration: motion.resolve(context, motion.standard),
                      curve: motion.standardCurve,
                      child: const DexSvgImage(
                        path: Assets.dexSwapCoins,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
