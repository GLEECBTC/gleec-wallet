// ignore: always_use_package_imports
import 'stub.dart'
    if (dart.library.js_interop) 'web_platform_info.dart'
    if (dart.library.io) 'native_platform_info.dart';

enum PlatformType {
  chrome,
  firefox,
  safari,
  edge,
  opera,
  brave,
  android,
  ios,
  windows,
  mac,
  linux,
  unknown,
}

abstract class PlatformInfo {
  /// Base constructor is required for the factory constructor to work.
  /// This constructor is not meant to be instantiated directly.
  const PlatformInfo();

  /// Creates a platform-specific instance of [PlatformInfo]
  factory PlatformInfo.create() => createPlatformInfo();

  String get osLanguage;
  String get platform;
  String? get screenSize;
  Future<PlatformType> get platformType;

  /// Legacy method for backward compatibility
  static PlatformInfo getInstance() => PlatformInfo.create();
}

mixin MemoizedPlatformInfoMixin {
  String? _osLanguage;
  String? _platform;
  String? _screenSize;
  Future<PlatformType>? _platformType;

  String get osLanguage => _osLanguage ??= computeOsLanguage();
  String get platform => _platform ??= computePlatform();
  String? get screenSize => _screenSize ??= computeScreenSize();
  Future<PlatformType> get platformType =>
      _platformType ??= computePlatformType();

  String computeOsLanguage();
  String computePlatform();
  String? computeScreenSize();
  Future<PlatformType> computePlatformType();
}
