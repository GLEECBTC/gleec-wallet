import 'package:flutter/material.dart';
import 'package:web_dex/common/screen.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/shared/ui/ui_gradient_icon.dart';
import 'package:web_dex/shared/widgets/html_parser.dart';

class SupportItemData {
  const SupportItemData({
    required this.title,
    this.content,
    this.onTap,
  });

  final String title;
  final String? content;
  final VoidCallback? onTap;
}

class SupportItem extends StatefulWidget {
  const SupportItem({Key? key, required this.data, this.isLast = false})
      : super(key: key);

  final SupportItemData data;
  final bool isLast;

  @override
  State<SupportItem> createState() => _SupportItemState();
}

class _SupportItemState extends State<SupportItem> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: InkWell(
            child: Row(
              mainAxisAlignment: isMobile
                  ? MainAxisAlignment.spaceBetween
                  : MainAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.data.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
                if (isMobile)
                  const SizedBox(
                    width: 30,
                  ),
                UiGradientIcon(
                  icon: expanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
              ],
            ),
            onTap: () {
              if (widget.data.onTap != null) {
                widget.data.onTap!();
                return;
              }
              setState(() {
                expanded = !expanded;
              });
            },
          ),
        ),
        const SizedBox(
          height: 10,
        ),
        if (widget.data.content != null)
          Visibility(
            visible: expanded,
            child: HtmlParser(
              widget.data.content!,
              linkStyle: TextStyle(
                color: palette.brandHover,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        const UiDivider(),
      ],
    );
  }
}
