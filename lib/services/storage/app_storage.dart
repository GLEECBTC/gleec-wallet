import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_dex/services/storage/base_storage.dart';
import 'package:web_dex/shared/utils/utils.dart';

class AppStorage implements BaseStorage {
  SharedPreferences? _prefs;

  @override
  Future<bool> write(String key, dynamic data) async {
    try {
      return await _writeToSharedPrefs(key, data);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<dynamic> read(String key) async {
    final SharedPreferences prefs = await _getPreferences();
    await prefs.reload();
    try {
      final dynamic value = prefs.get(key);
      if (value is String) {
        try {
          return jsonDecode(value);
        } catch (_) {
          return value;
        }
      } else {
        return value;
      }
    } catch (_, s) {
      log(
        'Unable to read application storage',
        path: 'web_storage => read',
        trace: s,
        isError: true,
      );
      rethrow;
    }
  }

  @override
  Future<bool> delete(String key) async {
    final SharedPreferences prefs = await _getPreferences();
    return prefs.remove(key);
  }

  Future<bool> _writeToSharedPrefs(String key, dynamic data) async {
    final SharedPreferences prefs = await _getPreferences();

    switch (data) {
      case final bool value:
        return prefs.setBool(key, value);
      case final double value:
        return prefs.setDouble(key, value);
      case final int value:
        return prefs.setInt(key, value);
      case final String value:
        return prefs.setString(key, value);
      default:
        return prefs.setString(key, jsonEncode(data));
    }
  }

  Future<SharedPreferences> _getPreferences() async {
    if (_prefs != null) {
      return Future.value(_prefs);
    }
    _prefs = await SharedPreferences.getInstance();

    return Future.value(_prefs);
  }
}
