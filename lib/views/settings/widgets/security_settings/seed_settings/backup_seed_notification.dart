import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_settings_entry.dart';

class BackupSeedNotification extends StatefulWidget {
  const BackupSeedNotification({
    super.key,
    this.title,
    this.description,
    this.customizationNotification,
    this.hideOnMobile = true,
  });

  final String? title;
  final String? description;
  final CustomizationBackupNotificationData? customizationNotification;
  final bool hideOnMobile;

  @override
  State<BackupSeedNotification> createState() => _BackupSeedNotificationState();
}

class _BackupSeedNotificationState extends State<BackupSeedNotification> {
  @override
  Widget build(BuildContext context) {
    if (isMobile && widget.hideOnMobile) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final CustomizationBackupNotificationData customization =
        _getCustomization();

    final String title =
        widget.title ?? LocaleKeys.backupSeedNotificationTitle.tr();
    final String description =
        widget.description ?? LocaleKeys.backupSeedNotificationDescription.tr();

    return ValueListenableBuilder<bool>(
      valueListenable: recoveryPhraseFlowOnScreen,
      builder: (context, backingUp, _) {
        // The reminder has been answered: do not push the words it asked
        // for down the screen.
        if (backingUp) return const SizedBox.shrink();
        return BlocBuilder<AuthBloc, AuthBlocState>(
          builder: (context, state) {
            final currentWallet = state.currentUser?.wallet;
            if (currentWallet == null ||
                currentWallet.config.hasRecoveryPhrase) {
              return const SizedBox();
            }
            final text = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Line(customization.line),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: customization.titleStyle),
                      const SizedBox(height: 2),
                      Text(description, style: customization.descriptionStyle),
                    ],
                  ),
                ),
              ],
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17,
                    vertical: 15,
                  ),
                  decoration: AppSurface.card(
                    palette,
                    color: customization.backgroundColor,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final beside =
                          !customization.isBelowButton &&
                          constraints.maxWidth >= 560 &&
                          MediaQuery.textScalerOf(context).scale(1) <= 1.5;
                      if (!beside) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            text,
                            const SizedBox(height: 12),
                            _BackupButton(customization),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: text),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 180,
                            child: _BackupButton(customization),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        );
      },
    );
  }

  CustomizationBackupNotificationData _getCustomization() {
    final CustomizationBackupNotificationData? customizationNotification =
        widget.customizationNotification;
    if (customizationNotification != null) {
      return customizationNotification;
    }
    return CustomizationBackupNotificationData(
      titleStyle: Theme.of(context).textTheme.bodyMedium!
          .copyWith(fontWeight: FontWeight.w700, fontSize: 16),
      // The theme draws this style at half opacity, which is unreadable for
      // the one sentence that says why to back up.
      descriptionStyle: Theme.of(context).textTheme.bodyLarge!.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      line: BackupNotificationLineStyle(
        width: 8,
        height: 45,
        color: AppPalette.of(context).warning,
      ),
    );
  }
}

class _BackupButton extends StatelessWidget {
  const _BackupButton(this.customization);

  final CustomizationBackupNotificationData customization;

  @override
  Widget build(BuildContext context) {
    // Backing up is the most important thing an unprotected wallet can do,
    // so it gets a full-size primary button, and the button starts the
    // backup rather than opening the list it is offered in.
    return UiPrimaryButton(
      expandForText: true,
      backgroundColor: customization.buttonBackgroundColor,
      textStyle: customization.buttonTextColor == null
          ? null
          : TextStyle(color: customization.buttonTextColor),
      onPressed: () =>
          openSecuritySettings(entry: SecuritySettingsEntry.recoveryPhrase),
      text: LocaleKeys.backupSeedNotificationButton.tr(),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.line);

  final BackupNotificationLineStyle line;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: line.height,
      width: line.width,
      margin: const EdgeInsets.only(right: 20),
      decoration: BoxDecoration(
        color: line.color,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
      ),
    );
  }
}

class BackupNotificationLineStyle {
  BackupNotificationLineStyle({
    required this.width,
    required this.height,
    required this.color,
  });

  final double width;
  final double height;
  final Color color;
}

class CustomizationBackupNotificationData {
  CustomizationBackupNotificationData({
    required this.titleStyle,
    required this.descriptionStyle,
    required this.line,
    this.backgroundColor,
    this.buttonBackgroundColor,
    this.buttonTextColor,
    this.isBelowButton = false,
  });

  final TextStyle? titleStyle;
  final TextStyle? descriptionStyle;
  final bool isBelowButton;
  final Color? backgroundColor;
  final Color? buttonBackgroundColor;
  final Color? buttonTextColor;
  final BackupNotificationLineStyle line;
}
