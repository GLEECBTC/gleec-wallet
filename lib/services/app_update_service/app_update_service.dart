import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_dex/blocs/update_bloc.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/utils/window/window.dart';

const AppUpdateService appUpdateService = AppUpdateService();

class AppUpdateService {
  const AppUpdateService();

  Future<UpdateVersionInfo?> getUpdateInfo() async {
    try {
      final http.Response response = await http
          .post(Uri.parse(updateCheckerEndpoint))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        log(
          'Update info request failed with status ${response.statusCode}',
          path: 'app_update_service => getUpdateInfo',
          isError: true,
        );
        return null;
      }
      final Map<String, dynamic> json = jsonDecode(response.body);

      return UpdateVersionInfo(
        status: _getStatus(json['status'] ?? ''),
        version: json['new_version'] ?? '',
        changelog: json['changelog'] ?? '',
        downloadUrl: json['download_url'] ?? '',
      );
    } catch (e, s) {
      log(
        'Failed to fetch update info: $e',
        path: 'app_update_service => getUpdateInfo',
        trace: s,
        isError: true,
      );
      return null;
    }
  }

  /// Returns the "version" field of the `version.json` deployed at the same
  /// origin, or null when it cannot be determined. Only meaningful on web,
  /// where the app is hosted at the origin root.
  Future<String?> fetchDeployedWebVersion() async {
    try {
      final uri = Uri.parse('${getOriginUrl()}/version.json').replace(
        queryParameters: {
          // Cache-buster: defeats the HTTP cache and falls through legacy
          // service-worker RESOURCES maps so the actual deployed file is
          // read even on clients pinned by an old caching service worker.
          'cb': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final http.Response response = await http
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        log(
          'version.json fetch failed with status ${response.statusCode}',
          path: 'app_update_service => fetchDeployedWebVersion',
          isError: true,
        );
        return null;
      }
      final dynamic json = jsonDecode(response.body);
      final version = (json as Map<String, dynamic>)['version'] as String?;
      return (version == null || version.isEmpty) ? null : version;
    } catch (e, s) {
      log(
        'Failed to fetch deployed version.json: $e',
        path: 'app_update_service => fetchDeployedWebVersion',
        trace: s,
        isError: true,
      );
      return null;
    }
  }

  UpdateStatus _getStatus(String status) {
    switch (status) {
      case 'upToDate':
        return UpdateStatus.upToDate;

      case 'available':
        return UpdateStatus.available;

      case 'recommended':
        return UpdateStatus.recommended;

      case 'required':
        return UpdateStatus.required;
      default:
        return UpdateStatus.upToDate;
    }
  }
}
