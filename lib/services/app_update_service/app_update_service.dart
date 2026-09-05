import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_dex/blocs/update_bloc.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/utils/window/window.dart';

const AppUpdateService appUpdateService = AppUpdateService();

class AppUpdateService {
  const AppUpdateService();

  /// The announced release, from the update endpoint.
  ///
  /// The endpoint takes no parameters: it answers every caller with the same
  /// constant, regardless of platform or installed version. It therefore says
  /// what the latest *release* is, and nothing about what any given client can
  /// actually install. Deciding that is [UpdateBloc]'s job.
  Future<UpdateVersionInfo?> getUpdateInfo() async {
    try {
      final http.Response response = await http
          .post(Uri.parse(updateCheckerEndpoint))
          .timeout(const Duration(seconds: 15));

      // Without this a 5xx HTML error page reaches jsonDecode, and the failure
      // surfaces as a parse error rather than as the outage it is.
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

  /// The version the web app is actually being served, read from the
  /// `version.json` Flutter emits next to `index.html`.
  ///
  /// This is the only thing that says what a reload would install. The update
  /// endpoint cannot: it is parameterless, and production is deployed by hand
  /// from a different Firebase project than the one CI deploys, so an
  /// announced release routinely runs ahead of what a given site serves.
  ///
  /// Returns null when the answer cannot be established. Callers must treat
  /// null as "unknown", never as "up to date".
  Future<String?> fetchDeployedWebVersion() async {
    try {
      final uri = Uri.parse('${getOriginUrl()}/version.json').replace(
        queryParameters: {
          // version.json is served `no-cache` (see firebase.json), but that
          // header only exists on sites deployed since it was added, and
          // production deploys by hand. Until then this site still answers
          // max-age=3600, and a cached copy would defeat the whole check. A
          // unique query string is a different HTTP cache key, and also falls
          // through the RESOURCES map of any legacy caching service worker.
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

      final version =
          (jsonDecode(response.body) as Map<String, dynamic>)['version']
              as String?;
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
