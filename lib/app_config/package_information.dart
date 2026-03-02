import 'package:package_info_plus/package_info_plus.dart';

PackageInformation packageInformation = PackageInformation();

class PackageInformation {
  String? packageVersion;
  String? packageName;
  String? commitHash;
  String? buildDate;

  static const String _kCommitHash = String.fromEnvironment(
    'COMMIT_HASH',
    defaultValue: 'unknown',
  );
  static const String _kBuildDate = String.fromEnvironment(
    'BUILD_DATE',
    defaultValue: 'unknown',
  );

  Future<void> init() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    packageVersion = packageInfo.version;
    packageName = packageInfo.packageName;
    commitHash = _kCommitHash;
    buildDate = _kBuildDate;
  }
}
