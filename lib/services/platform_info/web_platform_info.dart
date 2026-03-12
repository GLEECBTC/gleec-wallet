import 'package:web/web.dart' as web;
import 'package:web_dex/services/platform_info/platform_info.dart';
import 'package:web_dex/shared/utils/browser_helpers.dart';

PlatformInfo createPlatformInfo() => WebPlatformInfo();

class WebPlatformInfo extends PlatformInfo with MemoizedPlatformInfoMixin {
  BrowserInfo? _browserInfo;

  BrowserInfo get browserInfo => _browserInfo ??= BrowserInfoParser.get();

  @override
  String computeOsLanguage() => web.window.navigator.language;

  @override
  String computePlatform() =>
      '${browserInfo.os} ${browserInfo.browserName} ${browserInfo.browserVersion}';

  @override
  String? computeScreenSize() => browserInfo.screenSize;

  @override
  Future<PlatformType> computePlatformType() async {
    final browserName = browserInfo.browserName.toLowerCase();

    // Check for Brave browser using the async API
    if (browserName == 'chrome') {
      final isBrave = await isBraveApiAvailable();
      if (isBrave) {
        return PlatformType.brave;
      }
    }

    switch (browserName) {
      case 'chrome':
        return PlatformType.chrome;
      case 'firefox':
        return PlatformType.firefox;
      case 'safari':
        return PlatformType.safari;
      case 'edge':
        return PlatformType.edge;
      case 'opera':
        return PlatformType.opera;
      case 'brave':
        return PlatformType.brave;
      default:
        return PlatformType.unknown;
    }
  }
}
