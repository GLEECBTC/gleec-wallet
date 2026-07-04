import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/copied_text.dart';

class SendConfirmItem extends StatelessWidget {
  const SendConfirmItem({
    Key? key,
    required this.title,
    required this.value,
    this.url = '',
    this.usdPrice,
    this.isCopied = false,
    this.isCopiedValueTruncated = false,
    this.isWarningShown = false,
    this.centerAlign = false,
  }) : super(key: key);

  final String title;
  final String value;
  final String url;
  final bool isWarningShown;
  final bool isCopied;
  final bool isCopiedValueTruncated;
  final double? usdPrice;
  final bool centerAlign;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: centerAlign
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            title,
            textAlign: centerAlign ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: Theme.of(
                context,
              ).textTheme.titleLarge?.color?.withValues(alpha: .6),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: centerAlign
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            crossAxisAlignment: centerAlign
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Flexible(
                child: _ValueText(
                  value: value,
                  url: url,
                  isCopied: isCopied,
                  isCopiedValueTruncated: isCopiedValueTruncated,
                  centerAlign: centerAlign,
                  isWarningShown: isWarningShown,
                ),
              ),
              if (usdPrice != null) ...[
                const SizedBox(height: 10),
                Flexible(
                  child: _USDPrice(
                    usdPrice: usdPrice,
                    isWarningShown: isWarningShown,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ValueText extends StatelessWidget {
  const _ValueText({
    required this.value,
    required this.url,
    required this.isCopied,
    required this.isCopiedValueTruncated,
    required this.centerAlign,
    required this.isWarningShown,
  });
  final String value;
  final String url;
  final bool isCopied;
  final bool isCopiedValueTruncated;
  final bool centerAlign;
  final bool isWarningShown;

  @override
  Widget build(BuildContext context) {
    if (url.isNotEmpty) {
      return Hyperlink(
        text: value,
        onPressed: () async => await launchURL(url),
      );
    }
    if (isCopied) {
      return SizedBox(
        width: double.infinity,
        child: CopiedText(
          copiedValue: value,
          isTruncated: isCopiedValueTruncated,
        ),
      );
    }

    return SelectableText(
      value,
      textAlign: centerAlign ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        color: isWarningShown ? Colors.orange[300] : null,
        fontSize: 14,
        fontFamily: 'Manrope',
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Future<void> launchURL(String url) async {
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw Exception('Could not launch $url');
    }
  }
}

class _USDPrice extends StatelessWidget {
  const _USDPrice({this.usdPrice, required this.isWarningShown});

  final double? usdPrice;
  final bool isWarningShown;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      '\$${formatAmt(usdPrice ?? 0)}',
      style: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: isWarningShown ? Colors.orange[300] : null,
      ),
    );
  }
}
