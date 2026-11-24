import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

Future<void> showMissingCoinsDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      content: _buildDialogContent(context),
      title: Text(LocaleKeys.myCoinsMissing.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.close.tr()),
        ),
        ElevatedButton(
          onPressed: () async {
            Navigator.of(context).pop();

            _launchHelpUrl();
          },
          child: Text(LocaleKeys.myCoinsMissingMoreInfo.tr()),
        ),
      ],
    ),
  );
}

Widget _buildDialogContent(BuildContext context) {
  final theme = Theme.of(context);
  final textStyle = theme.textTheme.bodyMedium;

  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(LocaleKeys.myCoinsMissingReassurance.tr(), style: textStyle),
      const SizedBox(height: 8),
      Text(LocaleKeys.authImportDerivationHint.tr(), style: textStyle),
    ],
  );
}

Future<void> _launchHelpUrl() async {
  final url = Uri.parse(
    'https://komodoplatform.com/en/blog/komodo-wallet-v0-9-0-is-now-live/#note-for-web-wallet-users-with-existing-wallets-before-the-latest-release',
  );
  if (await canLaunchUrl(url)) {
    await launchUrl(url);
  }
}
