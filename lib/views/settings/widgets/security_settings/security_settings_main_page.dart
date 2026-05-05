import 'package:flutter/material.dart';
import 'package:web_dex/views/settings/widgets/security_settings/change_password_section.dart';
import 'package:web_dex/views/settings/widgets/security_settings/legacy_migration_cleanup_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/plate_seed_backup.dart';
import 'package:web_dex/views/settings/widgets/security_settings/plate_private_key_backup.dart';
import 'package:web_dex/views/settings/widgets/security_settings/unban_pubkeys_plate.dart';

class SecuritySettingsMainPage extends StatelessWidget {
  const SecuritySettingsMainPage({
    super.key,
    required this.onViewSeedPressed,
    required this.onViewPrivateKeysPressed,
  });

  final Function(BuildContext context) onViewSeedPressed;
  final Function(BuildContext context) onViewPrivateKeysPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LegacyMigrationCleanupPlate(),
        SizedBox(
          width: double.infinity,
          child: PlateSeedBackup(onViewSeedPressed: onViewSeedPressed),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: PlatePrivateKeyBackup(
            onViewPrivateKeysPressed: onViewPrivateKeysPressed,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: UnbanPubkeysPlate()),
        const SizedBox(height: 12),
        const ChangePasswordSection(),
      ],
    );
  }
}
