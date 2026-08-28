import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web_dex/blocs/bloc_base.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/dispatchers/popup_dispatcher.dart';
import 'package:web_dex/services/app_update_service/app_update_service.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/utils/window/window.dart';
import 'package:web_dex/shared/widgets/update_popup.dart';

final updateBloc = UpdateBloc();

class UpdateBloc extends BlocBase {
  Timer? _checkerTime;
  bool _isPopupShown = false;

  @override
  void dispose() {
    _checkerTime?.cancel();
  }

  Future<void> _checkForUpdates() async {
    final currentVersion = await _getCurrentAppVersion();
    final versionInfo = await appUpdateService.getUpdateInfo();
    if (versionInfo == null) return;
    final bool isNewVersion = isVersionGreaterThan(
      versionInfo.version,
      currentVersion,
    );

    if (!isNewVersion || _isPopupShown) return;

    if (kIsWeb) {
      // A reload can only ever install what the server currently hosts.
      // Suppress the popup while the web deploy lags the announcement,
      // otherwise it is unsatisfiable and re-appears on every check.
      final deployedVersion = await appUpdateService.fetchDeployedWebVersion();
      if (deployedVersion == null ||
          !isVersionGreaterThan(deployedVersion, currentVersion)) {
        log(
          'Update ${versionInfo.version} announced, but the deployed web '
          'build is ${deployedVersion ?? 'unknown'}; suppressing update popup',
          path: 'update_bloc => _checkForUpdates',
        );
        return;
      }
    } else if (versionInfo.downloadUri == null) {
      log(
        'Update ${versionInfo.version} announced without a valid '
        'download_url; suppressing update popup',
        path: 'update_bloc => _checkForUpdates',
      );
      return;
    }

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
          _checkerTime?.cancel();
        },
      ),
    ).show();
    _isPopupShown = true;
  }

  Future<String> _getCurrentAppVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  /// Compares dotted version strings segment-wise and numerically.
  ///
  /// Tolerates unequal segment counts ("1.0.0" > "0.9.15") and ignores
  /// pre-release/build suffixes ("0.9.5-rc1" compares as "0.9.5"). Returns
  /// false whenever [newVersion] is not strictly greater — including for
  /// malformed input, so garbage from the API can never trigger the popup.
  static bool isVersionGreaterThan(String newVersion, String currentVersion) {
    List<int> parse(String version) {
      final core = version.trim().split(RegExp(r'[+-]')).first;
      return core
          .split('.')
          .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final newSegments = parse(newVersion);
    final currentSegments = parse(currentVersion);
    final length = newSegments.length > currentSegments.length
        ? newSegments.length
        : currentSegments.length;
    for (var i = 0; i < length; i++) {
      final newSegment = i < newSegments.length ? newSegments[i] : 0;
      final currentSegment = i < currentSegments.length
          ? currentSegments[i]
          : 0;
      if (newSegment != currentSegment) return newSegment > currentSegment;
    }
    return false;
  }

  Future<void> init() async {
    await _checkForUpdates();
    _checkerTime?.cancel();
    _checkerTime = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkForUpdates(),
    );
  }

  Future<void> update(UpdateVersionInfo versionInfo) async {
    if (kIsWeb) {
      await hardReloadPage();
      return;
    }

    final Uri? downloadUri = versionInfo.downloadUri;
    if (downloadUri == null) {
      log(
        'App update failed: invalid download URL "${versionInfo.downloadUrl}"',
        path: 'update_bloc => update',
        isError: true,
      );
      return;
    }
    await launchURLString(downloadUri.toString(), inSeparateTab: true);
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

  /// Parsed http(s) download URL, or null when absent or invalid.
  Uri? get downloadUri {
    final url = downloadUrl.trim();
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return null;
    }
    return uri;
  }
}
