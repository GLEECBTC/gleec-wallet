import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_deleting.dart';

/// Keeps the engine session available for fresh password proof while reusing
/// the catalog's existing deletion review and confirmation flow.
class WalletRemovalSection extends StatefulWidget {
  const WalletRemovalSection({this.onBackUpRecoveryPhrase, super.key});

  /// Starts the recovery-phrase backup. The review offers it first for a
  /// wallet whose phrase is not confirmed, in place of removing it.
  final void Function(BuildContext context)? onBackUpRecoveryPhrase;

  @override
  State<WalletRemovalSection> createState() => _WalletRemovalSectionState();
}

class _WalletRemovalSectionState extends State<WalletRemovalSection> {
  bool _reviewOpen = false;

  @override
  Widget build(BuildContext context) => BlocBuilder<AuthBloc, AuthBlocState>(
    builder: (context, auth) {
      final wallet = auth.currentUser?.wallet;
      if (wallet == null || wallet.isHW) return const SizedBox.shrink();
      return LayoutBuilder(
        builder: (context, constraints) => SecurityActionPlate(
          icon: const Icon(Icons.delete_outline),
          title: 'authRemoveWalletTitle'.tr(),
          description: 'authRemoveWalletDescription'.tr(),
          // Not the primary button: nothing here should invite removal.
          trailingWidget: SecuritySecondaryButton(
            key: const Key('settings-delete-wallet'),
            width: SecurityActionPlate.isWide(context, constraints)
                ? SecurityActionPlate.actionWidth
                : double.infinity,
            text: 'authRemoveWalletAction'.tr(),
            // The review opens above this button, which keeps focus for the
            // return; opening twice is refused in [_review].
            onPressed: _review,
          ),
        ),
      );
    },
  );

  Future<void> _review() async {
    if (_reviewOpen) return;
    final user = context.read<AuthBloc>().state.currentUser;
    if (user == null || user.wallet.isHW) return;
    setState(() => _reviewOpen = true);
    final backUp = widget.onBackUpRecoveryPhrase;
    try {
      await AppDialog.showWithCallback<void>(
        context: context,
        width: 480,
        barrierDismissible: false,
        childBuilder: (close) => SingleChildScrollView(
          child: WalletDeleting(
            wallet: user.wallet,
            additionalWarning: 'authRemoveWalletActivityWarning'.tr(),
            close: close,
            onBackUpFirst: backUp == null
                ? null
                : () {
                    close();
                    if (mounted) backUp(context);
                  },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reviewOpen = false);
    }
  }
}
