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
  /// How long an established "this site cannot serve that release yet" verdict
  /// is trusted before it is re-checked.
  static const Duration _gateRecheckInterval = Duration(minutes: 30);

  Timer? _checkerTime;
  bool _isPopupShown = false;

  String? _gateAnnouncedVersion;
  DateTime? _gateCheckedAt;

  @override
  void dispose() {
    _checkerTime?.cancel();
  }

  Future<void> init() async {
    await _checkForUpdates();
    // init() is reachable more than once across a session; without this each
    // call would leave another live timer behind.
    _checkerTime?.cancel();
    _checkerTime = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkForUpdates(),
    );
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

    // The endpoint says what has been released. It cannot say whether this
    // client can install it, so check that separately -- and only now that a
    // release has actually been announced, so the common case stays one
    // request per check.
    if (kIsWeb) {
      final canInstall = await _webReloadWouldInstallUpdate(
        versionInfo.version,
        currentVersion,
      );
      if (!canInstall) return;
    } else if (versionInfo.downloadUri == null) {
      log(
        'Update ${versionInfo.version} announced with an unusable '
        'download_url "${versionInfo.downloadUrl}"; suppressing update popup',
        path: 'update_bloc => _checkForUpdates',
        isError: true,
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

  /// Whether reloading this page could actually install the announced release.
  ///
  /// A reload can only ever install what this origin is currently serving.
  /// Production is deployed by hand from a different Firebase project than the
  /// one CI deploys, so an announced release routinely runs ahead of the site
  /// a given user is on -- and offering an update that reloads onto the same
  /// build both fails and re-offers itself on every subsequent check.
  ///
  /// An unknown deployed version counts as "cannot install". That is
  /// deliberately fail-closed: the cost is a missed notification, against a
  /// popup that provably cannot do what it says.
  Future<bool> _webReloadWouldInstallUpdate(
    String announcedVersion,
    String currentVersion,
  ) async {
    final now = DateTime.now();
    if (_gateAnnouncedVersion == announcedVersion &&
        _gateCheckedAt != null &&
        now.difference(_gateCheckedAt!) < _gateRecheckInterval) {
      // Already established that this announcement is unsatisfiable here. A
      // site can lag the announcement by months, so re-fetching version.json
      // every five minutes for the rest of the session buys nothing.
      return false;
    }

    final deployedVersion = await appUpdateService.fetchDeployedWebVersion();
    final canInstall =
        deployedVersion != null &&
        isVersionGreaterThan(deployedVersion, currentVersion);

    if (!canInstall) {
      _gateAnnouncedVersion = announcedVersion;
      _gateCheckedAt = now;
      log(
        'Update $announcedVersion announced, but this origin serves '
        '${deployedVersion ?? 'an undeterminable version'} while the app runs '
        '$currentVersion; a reload would install nothing. Suppressing popup.',
        path: 'update_bloc => _webReloadWouldInstallUpdate',
      );
    }
    return canInstall;
  }

  Future<void> update(UpdateVersionInfo versionInfo) async {
    if (kIsWeb) {
      await hardReloadPage();
      return;
    }

    final Uri? downloadUri = versionInfo.downloadUri;
    if (downloadUri == null) {
      log(
        'App update failed: unusable download URL "${versionInfo.downloadUrl}"',
        path: 'update_bloc => update',
        isError: true,
      );
      return;
    }
    await launchURLString(downloadUri.toString(), inSeparateTab: true);
  }

  Future<String> _getCurrentAppVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }

  /// Whether [newVersion] is strictly newer than [currentVersion].
  ///
  /// Compares dotted versions segment by segment and numerically. The previous
  /// implementation concatenated the digits (`0.9.20` became `920`), which
  /// ranked `0.9.20` above `0.10.0`, and threw outright on any version
  /// carrying a suffix -- an uncaught error inside the five-minute timer.
  ///
  /// Tolerates unequal segment counts (`1.0` == `1.0.0`) and ignores build and
  /// pre-release suffixes, so `0.9.5-rc1` compares as `0.9.5`. Returns false
  /// for anything it cannot parse, so malformed input can never raise a popup.
  static bool isVersionGreaterThan(String newVersion, String currentVersion) {
    List<int>? parse(String version) {
      final normalized = version.trim();
      final pattern = RegExp(
        r'^[0-9]+(?:\.[0-9]+)*'
        r'(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'
        r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
      );
      if (!pattern.hasMatch(normalized)) return null;

      final core = normalized.split(RegExp(r'[+-]')).first;
      final segments = <int>[];
      for (final segment in core.split('.')) {
        final value = int.tryParse(segment);
        if (value == null) return null;
        segments.add(value);
      }
      return segments;
    }

    final newSegments = parse(newVersion);
    final currentSegments = parse(currentVersion);
    if (newSegments == null || currentSegments == null) return false;
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

  /// The download URL as a usable http(s) [Uri], or null when it is absent or
  /// not something we are willing to hand to the platform's URL launcher.
  Uri? get downloadUri {
    final url = downloadUrl.trim();
    if (url.isEmpty || RegExp(r'[\\\s\u0000-\u001f\u007f]').hasMatch(url)) {
      return null;
    }
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return uri;
  }
}
