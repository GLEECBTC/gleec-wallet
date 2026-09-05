import 'package:test/test.dart';
import 'package:web_dex/blocs/update_bloc.dart';

/// Covers [UpdateBloc.isVersionGreaterThan], which decides whether the update
/// popup is offered at all.
void testUpdateVersionCompare() {
  group('UpdateBloc.isVersionGreaterThan:', () {
    test('orders ordinary releases', () {
      expect(UpdateBloc.isVersionGreaterThan('0.9.7', '0.9.6'), isTrue);
      expect(UpdateBloc.isVersionGreaterThan('0.9.6', '0.9.7'), isFalse);
      expect(UpdateBloc.isVersionGreaterThan('1.0.0', '0.9.9'), isTrue);
    });

    test('never offers an update to the version already running', () {
      expect(UpdateBloc.isVersionGreaterThan('0.9.7', '0.9.7'), isFalse);
    });

    test('compares segments numerically, not as concatenated digits', () {
      // The previous implementation stripped the dots and parsed the result,
      // so 0.9.20 became 920 and 0.10.0 became 100 -- ranking the older
      // release higher and offering users a downgrade.
      expect(UpdateBloc.isVersionGreaterThan('0.9.20', '0.10.0'), isFalse);
      expect(UpdateBloc.isVersionGreaterThan('0.10.0', '0.9.20'), isTrue);
      expect(UpdateBloc.isVersionGreaterThan('0.9.10', '0.9.9'), isTrue);
    });

    test('tolerates unequal segment counts', () {
      expect(UpdateBloc.isVersionGreaterThan('1.0', '1.0.0'), isFalse);
      expect(UpdateBloc.isVersionGreaterThan('1.0.1', '1.0'), isTrue);
      expect(UpdateBloc.isVersionGreaterThan('2', '1.9.9'), isTrue);
    });

    test('ignores build and pre-release suffixes instead of throwing', () {
      // The previous implementation called int.parse on "097-rc1" and threw,
      // uncaught, inside the five-minute periodic check.
      expect(UpdateBloc.isVersionGreaterThan('0.9.7-rc1', '0.9.7'), isFalse);
      expect(UpdateBloc.isVersionGreaterThan('0.9.8-rc1', '0.9.7'), isTrue);
      expect(UpdateBloc.isVersionGreaterThan('0.9.7+2', '0.9.7+1'), isFalse);
    });

    test('treats unparseable input as "no update"', () {
      expect(UpdateBloc.isVersionGreaterThan('', '0.9.7'), isFalse);
      expect(
        UpdateBloc.isVersionGreaterThan('not-a-version', '0.9.7'),
        isFalse,
      );
      expect(UpdateBloc.isVersionGreaterThan('0.9.8', ''), isFalse);
    });

    test(
      'rejects malformed segments instead of repairing them into releases',
      () {
        for (final version in [
          'release99.0.0',
          '0.9.8oops',
          '1..0',
          '1.0.',
          '1. 0.0',
          '1.0.0-',
          '1.0.0+',
          '1.0.0+build!',
          '999999999999999999999999999999999.0.0',
        ]) {
          expect(
            UpdateBloc.isVersionGreaterThan(version, '0.9.7'),
            isFalse,
            reason: 'invalid announced version: $version',
          );
          expect(
            UpdateBloc.isVersionGreaterThan('2.0.0', version),
            isFalse,
            reason: 'invalid installed version: $version',
          );
        }
      },
    );

    test('matches the versions in production today', () {
      // The endpoint announces 0.9.6; walletrc serves 0.9.7 and dex.gleec.com
      // serves 0.9.4. Only the second of these may raise a popup.
      expect(UpdateBloc.isVersionGreaterThan('0.9.6', '0.9.7'), isFalse);
      expect(UpdateBloc.isVersionGreaterThan('0.9.6', '0.9.4'), isTrue);
    });
  });

  group('UpdateBloc.canInstallAnnouncedWebUpdate:', () {
    bool canInstall({
      String announced = '0.9.6',
      String current = '0.9.4',
      String? deployed = '0.9.6',
    }) => UpdateBloc.canInstallAnnouncedWebUpdate(
      announcedVersion: announced,
      currentVersion: current,
      deployedVersion: deployed,
    );

    test('waits until the origin serves the announced release', () {
      expect(canInstall(deployed: '0.9.5'), isFalse);
      expect(canInstall(deployed: '0.9.6'), isTrue);
      expect(canInstall(deployed: '0.9.7'), isTrue);
    });

    test('requires both an announcement and deployment newer than the app', () {
      expect(canInstall(deployed: '0.9.4'), isFalse);
      expect(canInstall(deployed: '0.9.3'), isFalse);
      expect(canInstall(current: '0.9.6', deployed: '0.9.7'), isFalse);
      expect(canInstall(current: '0.9.7', deployed: '0.9.8'), isFalse);
    });

    test('fails closed for unknown or malformed versions', () {
      expect(canInstall(deployed: null), isFalse);
      for (final invalid in ['', 'unknown', '1..0', '0.9.8oops']) {
        expect(canInstall(deployed: invalid), isFalse);
        expect(canInstall(announced: invalid), isFalse);
        expect(canInstall(current: invalid), isFalse);
      }
    });

    test('uses numeric segments and the existing normalization policy', () {
      expect(
        canInstall(announced: '0.10.0', current: '0.9.8', deployed: '0.9.20'),
        isFalse,
      );
      expect(
        canInstall(announced: '1.0.0', current: '0.9.4', deployed: '1.0'),
        isTrue,
      );
      expect(canInstall(deployed: ' 0.9.6+2 '), isTrue);
      expect(canInstall(announced: '0.9.6-rc1'), isTrue);
    });
  });
}

/// Covers the download-URL guard that decides whether a native update can be
/// started at all.
void testUpdateDownloadUri() {
  group('UpdateVersionInfo.downloadUri:', () {
    UpdateVersionInfo infoWith(String url) => UpdateVersionInfo(
      status: UpdateStatus.available,
      version: '0.9.8',
      changelog: '',
      downloadUrl: url,
    );

    test('accepts http(s) release URLs', () {
      expect(
        infoWith(
          'https://github.com/GLEECBTC/gleec-wallet/releases/tag/0.9.6',
        ).downloadUri,
        isNotNull,
      );
      expect(infoWith('  https://example.com/a  ').downloadUri, isNotNull);
    });

    test('rejects everything that is not an http(s) URL', () {
      expect(infoWith('').downloadUri, isNull);
      expect(infoWith('   ').downloadUri, isNull);
      expect(infoWith('javascript:alert(1)').downloadUri, isNull);
      expect(infoWith('file:///etc/passwd').downloadUri, isNull);
    });

    test('rejects hostless and ambiguous download URLs', () {
      for (final url in [
        'https:',
        'https:/release.zip',
        'https:///release.zip',
        'https://',
        'https://user:password@example.com/release.zip',
        'https://exa mple.com/release.zip',
        'https://example.com\n.attacker.example/release.zip',
        r'https://example.com\@attacker.example/release.zip',
      ]) {
        expect(infoWith(url).downloadUri, isNull, reason: url);
      }
    });
  });
}
