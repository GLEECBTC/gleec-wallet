import 'package:flutter/material.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/views/common/pages/page_plate.dart';
import 'package:web_dex/views/settings/widgets/security_settings/seed_settings/backup_seed_notification.dart';

class PageLayout extends StatelessWidget {
  const PageLayout({
    required this.content,
    this.header,
    this.noBackground = true,
    this.padding,
    this.showBackupNotice = true,
  });

  final Widget content;
  final Widget? header;
  final bool noBackground;
  final EdgeInsetsGeometry? padding;

  /// Off for a page whose host already shows the seed backup notice.
  final bool showBackupNotice;

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return _MobileLayout(
        header: header,
        content: content,
        noBackground: noBackground,
        padding: padding ?? EdgeInsets.zero,
        showBackupNotice: showBackupNotice,
      );
    }
    return _DesktopLayout(
      header: header,
      content: content,
      noBackground: noBackground,
      padding: padding ?? PagePlate.standardPadding,
      showBackupNotice: showBackupNotice,
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.content,
    required this.showBackupNotice,
    this.header,
    this.noBackground = false,
    this.padding = PagePlate.standardPadding,
  });

  final Widget? header;
  final Widget content;
  final bool noBackground;
  final EdgeInsetsGeometry padding;
  final bool showBackupNotice;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.max,
      children: [
        if (showBackupNotice) const BackupSeedNotification(hideOnMobile: false),
        if (header != null) header!,
        Flexible(
          child: PagePlate(
            noBackground: noBackground,
            padding: padding,
            child: Column(mainAxisSize: MainAxisSize.max, children: [content]),
          ),
        ),
      ],
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({
    required this.content,
    required this.showBackupNotice,
    this.header,
    this.noBackground = false,
    this.padding,
  });

  final Widget content;
  final Widget? header;
  final bool noBackground;
  final EdgeInsetsGeometry? padding;
  final bool showBackupNotice;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (showBackupNotice) const BackupSeedNotification(),
        Flexible(
          child: PagePlate(
            noBackground: noBackground,
            padding: padding ?? EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (header != null) ...[const SizedBox(height: 23), header!],
                content,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
