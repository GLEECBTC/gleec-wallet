import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_action_plate.dart';

class LegacyMigrationCleanupPlate extends StatelessWidget {
  const LegacyMigrationCleanupPlate({super.key});

  @override
  Widget build(BuildContext context) {
    final wallet = context.select(
      (AuthBloc bloc) => bloc.state.currentUser?.wallet,
    );
    if (wallet == null || !wallet.hasIncompleteNativeLegacyCleanup) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SecurityActionPlate(
        icon: const Icon(Icons.warning_amber_rounded),
        title: LocaleKeys.legacyMigrationCleanupTitle.tr(),
        description: LocaleKeys.legacyMigrationCleanupDescription.tr(),
        trailingWidget: const SizedBox.shrink(),
        showWarningIndicator: true,
      ),
    );
  }
}
