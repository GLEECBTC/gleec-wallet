import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/logout_popup.dart';

class SettingsLogoutButton extends StatefulWidget {
  const SettingsLogoutButton({Key? key}) : super(key: key);

  @override
  State<SettingsLogoutButton> createState() => _SettingsLogoutButtonState();
}

class _SettingsLogoutButtonState extends State<SettingsLogoutButton> {
  Future<void> _showLogoutDialog() async {
    await AppDialog.showWithCallback<void>(
      context: context,
      width: 320,
      barrierDismissible: true,
      childBuilder: (closeDialog) =>
          LogOutPopup(onConfirm: closeDialog, onCancel: closeDialog),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('settings-logout-button'),
      onTap: () {
        _showLogoutDialog();
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 20, 0, 20),
        child: Row(
          mainAxisAlignment: isMobile
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.logOut.tr(),
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: theme.custom.warningColor,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.exit_to_app, color: theme.custom.warningColor, size: 18),
          ],
        ),
      ),
    );
  }
}
