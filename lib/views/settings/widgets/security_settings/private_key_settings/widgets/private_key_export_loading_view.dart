import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';

/// Shown while the export runs.
///
/// The screen previously rendered nothing at all during `starting` and
/// `exporting`, so unlocking the wallet dropped the reader onto a blank page
/// with no indication that anything was happening.
class PrivateKeyExportLoadingView extends StatelessWidget {
  const PrivateKeyExportLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: WalletAccessProgress(
          label: LocaleKeys.privateKeyExportLoading.tr(),
          showLabel: true,
        ),
      ),
    );
  }
}
