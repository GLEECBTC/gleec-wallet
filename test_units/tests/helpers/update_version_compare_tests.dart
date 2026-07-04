import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/blocs/update_bloc.dart';

void main() => testUpdateVersionCompare();

void testUpdateVersionCompare() {
  group('UpdateBloc.isVersionGreaterThan:', () {
    test('basic ordering', () {
      expect(UpdateBloc.isVersionGreaterThan('0.9.5', '0.9.4'), true);
      expect(UpdateBloc.isVersionGreaterThan('0.9.4', '0.9.5'), false);
      expect(UpdateBloc.isVersionGreaterThan('0.9.5', '0.9.5'), false);
      expect(UpdateBloc.isVersionGreaterThan('0.10.0', '0.9.5'), true);
    });

    test('unequal segment counts and digit widths', () {
      expect(UpdateBloc.isVersionGreaterThan('1.0.0', '0.9.15'), true);
      expect(UpdateBloc.isVersionGreaterThan('0.9.15', '1.0.0'), false);
      expect(UpdateBloc.isVersionGreaterThan('1.0', '1.0.0'), false);
      expect(UpdateBloc.isVersionGreaterThan('1.0.1', '1.0'), true);
      expect(UpdateBloc.isVersionGreaterThan('0.9.10', '0.9.9'), true);
    });

    test('non-numeric suffixes and garbage never throw', () {
      expect(UpdateBloc.isVersionGreaterThan('0.9.5-rc1', '0.9.4'), true);
      expect(UpdateBloc.isVersionGreaterThan('0.9.5-rc1', '0.9.5'), false);
      expect(UpdateBloc.isVersionGreaterThan('0.9.5+7', '0.9.5'), false);
      expect(UpdateBloc.isVersionGreaterThan('', '0.9.5'), false);
      expect(UpdateBloc.isVersionGreaterThan('abc', '0.9.5'), false);
      expect(UpdateBloc.isVersionGreaterThan('0.9.5', ''), true);
    });
  });

  group('UpdateVersionInfo.downloadUri:', () {
    UpdateVersionInfo info(String url) => UpdateVersionInfo(
      status: UpdateStatus.available,
      version: '1.0.0',
      changelog: '',
      downloadUrl: url,
    );

    test('accepts http(s) URLs', () {
      expect(
        info(
          'https://github.com/GLEECBTC/gleec-wallet/releases/tag/0.9.5',
        ).downloadUri.toString(),
        'https://github.com/GLEECBTC/gleec-wallet/releases/tag/0.9.5',
      );
      expect(info(' https://example.com ').downloadUri, isNotNull);
      expect(info('http://example.com').downloadUri, isNotNull);
    });

    test('rejects empty, non-http, and malformed URLs', () {
      expect(info('').downloadUri, isNull);
      expect(info('   ').downloadUri, isNull);
      expect(info('javascript:alert(1)').downloadUri, isNull);
      expect(info('ftp://example.com/file').downloadUri, isNull);
      expect(info('not a url').downloadUri, isNull);
    });
  });
}
