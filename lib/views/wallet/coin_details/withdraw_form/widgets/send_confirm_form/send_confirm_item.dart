import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/widgets/copied_text.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';

class SendConfirmItem extends StatelessWidget {
  const SendConfirmItem({
    super.key,
    required this.title,
    required this.value,
    this.url = '',
    this.usdPrice,
    this.isCopied = false,
    this.isCopiedValueTruncated = false,
    this.isWarningShown = false,
    this.centerAlign = false,
  });

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
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final valueWidget = _ValueText(
                value: value,
                url: url,
                isCopied: isCopied,
                isCopiedValueTruncated: isCopiedValueTruncated,
                centerAlign: centerAlign,
                isWarningShown: isWarningShown,
              );
              final usdWidget = usdPrice == null
                  ? null
                  : _USDPrice(
                      usdPrice: usdPrice,
                      isWarningShown: isWarningShown,
                      centerAlign: centerAlign,
                    );

              if (usdWidget == null) return valueWidget;

              if (constraints.maxWidth < 320 || textScale > 1.3) {
                return Column(
                  crossAxisAlignment: centerAlign
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [valueWidget, const SizedBox(height: 6), usdWidget],
                );
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: centerAlign
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(child: valueWidget),
                  const SizedBox(width: 10),
                  Flexible(child: usdWidget),
                ],
              );
            },
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
    final warningColor = NoticeBanner.styleOf(
      context,
      NoticeBannerVariant.warning,
    ).foreground;
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
        color: isWarningShown ? warningColor : null,
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
  const _USDPrice({
    this.usdPrice,
    required this.isWarningShown,
    required this.centerAlign,
  });

  final double? usdPrice;
  final bool isWarningShown;
  final bool centerAlign;

  @override
  Widget build(BuildContext context) {
    final warningColor = NoticeBanner.styleOf(
      context,
      NoticeBannerVariant.warning,
    ).foreground;
    return SelectableText(
      '\$${formatAmt(usdPrice ?? 0)}',
      textAlign: centerAlign ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: isWarningShown ? warningColor : null,
      ),
    );
  }
}
