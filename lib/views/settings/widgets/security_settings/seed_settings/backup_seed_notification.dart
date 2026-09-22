import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/router/state/routing_state.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class BackupSeedNotification extends StatefulWidget {
  const BackupSeedNotification({
    Key? key,
    this.title,
    this.description,
    this.customizationNotification,
    this.hideOnMobile = true,
  }) : super(key: key);

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

    final CustomizationBackupNotificationData customization =
        _getCustomization();

    final String title =
        widget.title ?? LocaleKeys.backupSeedNotificationTitle.tr();
    final String description =
        widget.description ?? LocaleKeys.backupSeedNotificationDescription.tr();

    return BlocBuilder<AuthBloc, AuthBlocState>(
      builder: (context, state) {
        final currentWallet = state.currentUser?.wallet;
        if (currentWallet == null || currentWallet.config.hasBackup) {
          return const SizedBox();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(18)),
                color:
                    customization.backgroundColor ??
                    Theme.of(context).colorScheme.surface,
              ),
              child: customization.isBelowButton
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Line(customization.line),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: customization.titleStyle),
                              const SizedBox(height: 8),
                              Text(
                                description,
                                style: customization.descriptionStyle,
                              ),
                              const SizedBox(height: 12),
                              _BackupButton(customization),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 12,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Line(customization.line),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: customization.titleStyle),
                                  const SizedBox(height: 2),
                                  Text(
                                    description,
                                    style: customization.descriptionStyle,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        _BackupButton(customization),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
          ],
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
      titleStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      descriptionStyle: Theme.of(context).textTheme.bodyLarge!.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: 14,
      ),
      line: BackupNotificationLineStyle(
        width: 8,
        height: 45,
        color: theme.custom.warningColor,
      ),
    );
  }
}

class _BackupButton extends StatelessWidget {
  const _BackupButton(this.customization);

  final CustomizationBackupNotificationData customization;

  @override
  Widget build(BuildContext context) {
    return UiPrimaryButton(
      text: LocaleKeys.backupSeedNotificationButton.tr(),
      backgroundColor:
          customization.buttonBackgroundColor ??
          theme.custom.simpleButtonBackgroundColor,
      width: 85,
      height: 28,
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontSize: 12,
        color: customization.buttonTextColor,
      ),
      onPressed: routingState.settingsState.openSecurity,
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
