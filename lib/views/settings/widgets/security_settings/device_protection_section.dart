import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_bloc.dart';
import 'package:web_dex/bloc/security_settings/security_settings_event.dart';
import 'package:web_dex/bloc/wallet_protection/wallet_protection_bloc.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/views/common/wallet_access/wallet_protection_panel.dart';

/// Local unlock protection is independent of recovery and personal passwords.
class DeviceProtectionSection extends StatelessWidget {
  const DeviceProtectionSection({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<AuthBloc, AuthBlocState>(
    builder: (context, auth) {
      final access = context.read<WalletAccessService?>();
      final id = auth.currentUser?.walletId;
      if (access == null || id == null) return const SizedBox.shrink();
      // Absent when the section is shown on its own, outside the page.
      final security = context.read<SecuritySettingsBloc?>();
      return BlocProvider(
        key: ValueKey((
          id,
          context
              .read<AuthBloc>()
              .state
              .currentUser
              ?.metadata['_wallet_entry_id'],
        )),
        create: (_) => WalletProtectionBloc(access: access, walletId: id),
        child: WalletProtectionPanel(
          showLockSettings: true,
          onSetPassword: security == null
              ? null
              : () => security.add(const PasswordUpdateEvent()),
        ),
      );
    },
  );
}
