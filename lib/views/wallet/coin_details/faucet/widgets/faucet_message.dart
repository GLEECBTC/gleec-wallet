import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/wallet/coin_details/faucet/models/faucet_success_info.dart';

class FaucetMessage extends StatelessWidget {
  const FaucetMessage(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final info = parseSuccessMessage(message);
    final textStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: Theme.of(
        context,
      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
    );
    return Center(
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 324,
        decoration: BoxDecoration(
          color: theme.custom.subCardBackgroundColor,
          borderRadius: BorderRadius.circular(18),
        ),
        child: SelectableText.rich(
          TextSpan(
            text: '${info.message}\n',
            children: _getLinkText(context, textStyle, info.link),
          ),
          textAlign: TextAlign.center,
          style: textStyle,
        ),
      ),
    );
  }

  FaucetSuccessInfo parseSuccessMessage(String message) {
    if (message.contains('Link:')) {
      final link = message.substring(
        message.indexOf('<') + 1,
        message.indexOf('>'),
      );
      final mssg = message.substring(0, message.indexOf(' Link'));

      return FaucetSuccessInfo(message: mssg, link: link);
    }
    return FaucetSuccessInfo(message: message);
  }

  List<InlineSpan> _getLinkText(
    BuildContext context,
    TextStyle textStyle,
    String? link,
  ) {
    if (link == null) {
      return [];
    }
    return [
      TextSpan(
        text: LocaleKeys.faucetLinkToTransaction.tr(),
        mouseCursor: SystemMouseCursors.click,
        style: textStyle.copyWith(decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()
          ..onTap = () async {
            await canLaunchUrlString(link)
                ? await launchUrlString(link)
                : throw 'Could not launch $link}';
          },
      ),
    ];
  }
}
