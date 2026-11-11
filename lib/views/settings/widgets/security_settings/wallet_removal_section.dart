import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_deleting.dart';

/// Keeps the engine session available for fresh password proof while reusing
/// the catalog's existing deletion review and confirmation flow.
class WalletRemovalSection extends StatefulWidget {
  const WalletRemovalSection({super.key});

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
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'authRemoveWalletTitle'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: 8),
              Text('authRemoveWalletDescription'.tr()),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const Key('settings-delete-wallet'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: _reviewOpen ? null : _review,
                  icon: const Icon(Icons.delete_outline),
                  label: Text('authRemoveWalletAction'.tr()),
                ),
              ),
            ],
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
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _reviewOpen = false);
    }
  }
}
