import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/common/wallet_password_dialog/wallet_password_dialog.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';

class PlateSeedBackup extends StatelessWidget {
  const PlateSeedBackup({required this.onViewSeedPressed});
  final Function(BuildContext context) onViewSeedPressed;

  @override
  Widget build(BuildContext context) {
    final currentWallet = context.read<AuthBloc>().state.currentUser?.wallet;
    final hasBackup = currentWallet?.config.hasBackup ?? false;
    final authBloc = context.read<AuthBloc>();

    final text = hasBackup
        ? LocaleKeys.viewSeedPhrase.tr()
        : LocaleKeys.backupSeedPhrase.tr();

    return SecurityActionPlate(
      icon: const Icon(Icons.security),
      title: LocaleKeys.saveAndRemember.tr(),
      description: LocaleKeys.seedAccessSpan1.tr(),
      showWarningIndicator: false,
      trailingWidget: _SeedActionButtons(
        onViewSeedPressed: onViewSeedPressed,
        authBloc: authBloc,
        actionText: text,
      ),
    );
  }
}

/// Widget containing both the main seed action button and download button
class _SeedActionButtons extends StatelessWidget {
  const _SeedActionButtons({
    required this.onViewSeedPressed,
    required this.authBloc,
    required this.actionText,
  });

  final Function(BuildContext context) onViewSeedPressed;
  final AuthBloc authBloc;
  final String actionText;

  @override
  Widget build(BuildContext context) {
    final width = isMobile ? double.infinity : 187.0;
    final height = isMobile ? 52.0 : 40.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        UiPrimaryButton(
          onPressed: () => onViewSeedPressed(context),
          width: width,
          height: height,
          text: actionText,
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: theme.custom.defaultGradientButtonTextColor,
          ),
        ),
        const SizedBox(height: 8),
        UiUnderlineTextButton(
          onPressed: () async {
            final expectedWalletId = authBloc.state.currentUser?.walletId;
            if (expectedWalletId == null) return;
            final String? password = await walletPasswordDialog(context);
            if (password == null) return;

            if (!context.mounted ||
                authBloc.state.currentUser?.walletId != expectedWalletId) {
              return;
            }
            authBloc.add(
              AuthWalletDownloadRequested(
                password: password,
                expectedWalletId: expectedWalletId,
              ),
            );
          },
          width: width,
          height: height,
          text: LocaleKeys.seedPhraseSettingControlsDownloadSeed.tr(),
          textFontSize: 14,
        ),
      ],
    );
  }
}
