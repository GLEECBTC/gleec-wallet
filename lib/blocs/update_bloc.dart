import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web_dex/blocs/bloc_base.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/dispatchers/popup_dispatcher.dart';
import 'package:web_dex/platform/platform.dart';
import 'package:web_dex/services/app_update_service/app_update_service.dart';
import 'package:web_dex/shared/widgets/update_popup.dart';

final updateBloc = UpdateBloc();

class UpdateBloc extends BlocBase {
  late Timer _checkerTime;
  bool _isPopupShown = false;

  @override
  void dispose() {
    _checkerTime.cancel();
  }

  Future<void> _checkForUpdates() async {
    final currentVersion = await _getCurrentAppVersion();
    final versionInfo = await appUpdateService.getUpdateInfo();
    if (versionInfo == null) return;
    final bool isNewVersion = _isVersionGreaterThan(
      versionInfo.version,
      currentVersion,
    );

    if (!isNewVersion || _isPopupShown) return;

    PopupDispatcher(
      barrierDismissible: false,
      contentPadding: isMobile
          ? const EdgeInsets.all(15.0)
          : const EdgeInsets.fromLTRB(26, 15, 26, 42),
      popupContent: UpdatePopUp(
        versionInfo: versionInfo,
        onAccept: () {
          _isPopupShown = false;
        },
        onCancel: () {
          _isPopupShown = false;
          _checkerTime.cancel();
        },
      ),
    ).show();
    _isPopupShown = true;
  }

  Future<String> _getCurrentAppVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  bool _isVersionGreaterThan(String newVersion, String currentVersion) {
    if (newVersion == currentVersion) return false;

    final int currentV = int.parse(currentVersion.replaceAll('.', ''));
    final int newV = int.parse(newVersion.replaceAll('.', ''));

    return newV > currentV;
  }

  Future<void> init() async {
    await _checkForUpdates();
    _checkerTime = Timer.periodic(
      const Duration(minutes: 5),
      (_) async => await _checkForUpdates(),
    );
  }

  Future<void> update() async {
    if (kIsWeb) {
      reloadPage();
    }
  }
}

enum UpdateStatus { upToDate, available, recommended, required }

class UpdateVersionInfo {
  const UpdateVersionInfo({
    required this.status,
    required this.version,
    required this.changelog,
    required this.downloadUrl,
  });
  final String version;
  final String changelog;
  final String downloadUrl;
  final UpdateStatus status;
}
