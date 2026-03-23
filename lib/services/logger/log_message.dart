class LogMessage {
  final String appVersion;

  /// MM2 version
  ///
  /// Nullable because log can be called before the API is started.
  final String? mm2Version;

  /// App locale
  ///
  /// Nullable because log can be called before the locale is not yet set.
  final String? appLocale;

  final String platform;
  final String osLanguage;
  final String screenSize;
  final int timestamp;
  final String message;
  final String? path;
  final String date;

  const LogMessage({
    required this.appVersion,
    required this.mm2Version,
    required this.appLocale,
    required this.platform,
    required this.osLanguage,
    required this.screenSize,
    required this.timestamp,
    required this.message,
    required this.date,
    this.path,
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'path': path,
      'app_version': appVersion,
      'mm2_version': mm2Version,
      'app_language': appLocale,
      'platform': platform,
      'os_language': osLanguage,
      'screen_size': screenSize,
      'timestamp': timestamp,
      'date': date,
    };
  }

  factory LogMessage.fromJson(Map<String, dynamic> json) {
    return LogMessage(
      appVersion: json['app_version'] as String,
      mm2Version: json['mm2_version'] as String?,
      appLocale: json['app_language'] as String?,
      platform: json['platform'] as String,
      osLanguage: json['os_language'] as String,
      screenSize: json['screen_size'] as String,
      timestamp: (json['timestamp'] as num).toInt(),
      message: json['message'] as String,
      path: json['path'] as String?,
      date: json['date'] as String,
    );
  }
}
