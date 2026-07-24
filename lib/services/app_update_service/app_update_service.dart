import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web_dex/blocs/update_bloc.dart';
import 'package:web_dex/shared/constants.dart';

const AppUpdateService appUpdateService = AppUpdateService();

class AppUpdateService {
  const AppUpdateService();

  Future<UpdateVersionInfo?> getUpdateInfo() async {
    try {
      final http.Response response = await http.post(
        Uri.parse(updateCheckerEndpoint),
      );
      final Map<String, dynamic> json = jsonDecode(response.body);

      return UpdateVersionInfo(
        status: _getStatus(json['status'] ?? ''),
        version: json['new_version'] ?? '',
        changelog: json['changelog'] ?? '',
        downloadUrl: json['download_url'] ?? '',
      );
    } catch (e) {
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
