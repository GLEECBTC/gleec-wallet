import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

/// On-demand explainer for the gasless (GasFree) custody address: how fees are
/// paid in the token, and the honest disclosure that sending depends on the
/// GasFree service being available (funds stay safe on-chain; the recovery
/// phrase also works in other GasFree-compatible wallets).
class GaslessInfoDialog extends StatelessWidget {
  const GaslessInfoDialog({required this.assetName, super.key});

  /// Ticker shown in the copy (e.g. `USDT`).
  final String assetName;

  /// Opens the dialog. Safe to call from any gasless surface (receive badge,
  /// send-screen chip).
  static Future<void> show(BuildContext context, {required String assetName}) {
    return showDialog<void>(
      context: context,
      builder: (_) => GaslessInfoDialog(assetName: assetName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(LocaleKeys.gaslessInfoTitle.tr()),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 420,
          maxHeight: MediaQuery.sizeOf(context).height * 0.65,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                LocaleKeys.gaslessInfoBodyHow.tr(args: [assetName, assetName]),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                LocaleKeys.gaslessInfoProviderDependence.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.close.tr()),
        ),
      ],
    );
  }
}
