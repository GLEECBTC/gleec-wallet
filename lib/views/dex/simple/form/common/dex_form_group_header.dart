import 'package:flutter/material.dart';
import 'package:web_dex/views/dex/simple/form/common/dex_form_title.dart';

class DexFormGroupHeader extends StatelessWidget {
  const DexFormGroupHeader({
    this.title,
    this.actions,
    this.background,
    Key? key,
  }) : super(key: key);

  final String? title;
  final List<Widget>? actions;
  final Widget? background;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (background != null)
          Positioned(left: 0, right: 0, top: 0, bottom: 0, child: background!),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Column(
              children: [
                if (title != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: DexFormTitle(title!),
                  ),
                if (actions != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: actions!,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
