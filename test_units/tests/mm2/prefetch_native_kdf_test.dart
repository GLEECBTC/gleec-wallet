import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:path/path.dart' as path;

import '../../../tool/prefetch_native_kdf.dart' as prefetch;

void main() {
  group('native KDF preparation before platform configuration', () {
    late _ArtifactFixture fixture;

    setUp(() async {
      fixture = await _ArtifactFixture.create();
    });
    tearDown(() => fixture.dispose());

    test(
      'clean Windows extraction verifies the approved DLL before build',
      () async {
        final originalManifest = fixture.manifest.readAsStringSync();
        // An unrelated, unpublished Mac archive must not block Windows setup.
        fixture.updateManifest((json) {
          final api = json['api'] as Map<String, dynamic>;
          final platforms = api['platforms'] as Map<String, dynamic>;
          (platforms['macos']
              as Map<String, dynamic>)['valid_zip_sha256_checksums'] = [
            '0' * 64,
          ];
        });
        final selectedManifest = fixture.manifest.readAsStringSync();

        await fixture.prepare('windows');

        expect(fixture.file('windows/bin/kdflib.dll').readAsBytesSync(), [
          4,
          5,
          6,
        ]);
        expect(
          fixture.file('windows/bin/enum_derives.dll').existsSync(),
          isFalse,
        );
        expect(fixture.file('macos/bin/libkdflib.dylib').existsSync(), isFalse);
        expect(fixture.archiveRequests, [fixture.names['windows']]);
        expect(fixture.manifest.readAsStringSync(), selectedManifest);
        expect(selectedManifest, isNot(originalManifest));
        await fixture.verify('windows');
      },
    );

    test('a verified cache needs no network access', () async {
      await fixture.prepare('windows');
      fixture.requests.clear();
      await fixture.server.close(force: true);

      await fixture.prepare('windows');

      expect(fixture.requests, isEmpty);
      await fixture.verify('windows');
    });

    test('archive checksum mismatch cannot install a DLL or marker', () async {
      fixture.updateManifest((json) {
        final api = json['api'] as Map<String, dynamic>;
        final platforms = api['platforms'] as Map<String, dynamic>;
        (platforms['windows']
            as Map<String, dynamic>)['valid_zip_sha256_checksums'] = [
          '1' * 64,
        ];
      });

      await expectLater(fixture.prepare('windows'), throwsA(isA<Exception>()));

      expect(fixture.file('windows/bin/kdflib.dll').existsSync(), isFalse);
      expect(
        fixture.file('windows/bin/.api_last_updated_windows').existsSync(),
        isFalse,
      );
    });

    test(
      'checksum-valid executable-only archive remains a release failure',
      () async {
        fixture.replaceArchive('windows', {
          'kdf.exe': [1, 2, 3],
        });

        await expectLater(fixture.prepare('windows'), throwsStateError);

        expect(fixture.file('windows/bin/kdf.exe').existsSync(), isTrue);
        expect(fixture.file('windows/bin/kdflib.dll').existsSync(), isFalse);
      },
    );

    test('macOS fetches its library without fetching Windows', () async {
      await fixture.prepare('macos');

      expect(fixture.file('macos/bin/libkdflib.dylib').existsSync(), isTrue);
      expect(fixture.archiveRequests, [fixture.names['macos']]);
      expect(fixture.file('windows/bin/kdflib.dll').existsSync(), isFalse);
      await fixture.verify('macos');
    });

    test(
      'Android prepares and verifies both configured architectures',
      () async {
        await fixture.prepare('android');

        expect(fixture.archiveRequests, [
          fixture.names['android-armv7'],
          fixture.names['android-aarch64'],
        ]);
        await fixture.verify('android-armv7');
        await fixture.verify('android-aarch64');
      },
    );

    test(
      'changed runtime bytes fail existing provenance verification',
      () async {
        await fixture.prepare('windows');
        fixture.file('windows/bin/kdflib.dll').writeAsBytesSync([9, 8, 7]);

        await expectLater(fixture.verify('windows'), throwsStateError);
      },
    );

    test('a stale commit marker cannot authorize a current library', () async {
      await fixture.prepare('windows');
      final marker = fixture.file('windows/bin/.api_last_updated_windows');
      final json =
          jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
      json['api_commit_hash'] = 'a' * 40;
      json['archive_filename'] = 'kdf_aaaaaaa-win-x86-64.zip';
      marker.writeAsStringSync(jsonEncode(json));

      await expectLater(fixture.verify('windows'), throwsStateError);
    });

    test(
      'a missing provenance marker does not certify an existing library',
      () async {
        await fixture.prepare('windows');
        fixture.file('windows/bin/.api_last_updated_windows').deleteSync();

        await expectLater(fixture.verify('windows'), throwsStateError);
      },
    );

    test(
      'disabled downloads verify existing bytes and reject absent ones',
      () async {
        await fixture.prepare('windows');
        fixture.requests.clear();
        fixture.updateManifest((json) {
          (json['api'] as Map<String, dynamic>)['fetch_at_build_enabled'] =
              false;
        });

        await fixture.prepare('windows');
        expect(fixture.requests, isEmpty);
        fixture.file('windows/bin/kdflib.dll').deleteSync();
        await expectLater(fixture.prepare('windows'), throwsStateError);
        expect(fixture.requests, isEmpty);
      },
    );

    test('missing selected platform fails before any download', () async {
      fixture.updateManifest((json) {
        final api = json['api'] as Map<String, dynamic>;
        (api['platforms'] as Map<String, dynamic>).remove('windows');
        (api['required_platforms'] as List<dynamic>).remove('windows');
      });

      await expectLater(fixture.prepare('windows'), throwsStateError);
      expect(fixture.requests, isEmpty);
    });

    test('unknown target fails before any download', () async {
      await expectLater(fixture.prepare('web'), throwsArgumentError);
      expect(fixture.requests, isEmpty);
    });

    test(
      'linked DLL cannot inherit verified provenance',
      () async {
        await fixture.prepare('windows');
        final library = fixture.file('windows/bin/kdflib.dll');
        final original = fixture.file('original.dll')
          ..writeAsBytesSync([4, 5, 6]);
        library.deleteSync();
        Link(library.path).createSync(original.path);

        await expectLater(fixture.verify('windows'), throwsStateError);
      },
      skip: Platform.isWindows
          ? 'Windows symlink privilege is not guaranteed'
          : false,
    );
  });
}

class _LocalHttp extends HttpOverrides {}

class _ArtifactFixture {
  _ArtifactFixture(this.directory, this.server);

  static const commit = '1234567890abcdef1234567890abcdef12345678';
  final Directory directory;
  final HttpServer server;
  final requests = <String>[];
  final archives = <String, List<int>>{};
  final names = <String, String>{};

  File get manifest => file('app_build/build_config.json');
  Iterable<String> get archiveRequests => requests
      .where((request) => request.endsWith('.zip'))
      .map(path.posix.basename);

  File file(String relative) => File(path.join(directory.path, relative));

  static Future<_ArtifactFixture> create() async {
    final directory = await Directory.systemTemp.createTemp('native-kdf-test-');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _ArtifactFixture(directory, server);
    final config =
        jsonDecode(
              File(
                'sdk/packages/komodo_defi_framework/app_build/build_config.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    config['api'] = {
      'api_commit_hash': commit,
      'branch': 'main',
      'fetch_at_build_enabled': true,
      'concurrent_downloads_enabled': false,
      'require_full_commit_hash': true,
      'required_platforms': [
        'windows',
        'macos',
        'android-armv7',
        'android-aarch64',
      ],
      'source_urls': ['http://127.0.0.1:${server.port}'],
      'platforms': <String, dynamic>{},
    };
    fixture.manifest.parent.createSync(recursive: true);
    fixture.manifest.writeAsStringSync(jsonEncode(config));
    fixture.replaceArchive('windows', {
      'kdf.exe': [1, 2, 3],
      'kdflib.dll': [4, 5, 6],
      'enum_derives.dll': [7, 8, 9],
    });
    fixture.replaceArchive('macos', {
      'kdf': [1, 2, 3],
      'libkdflib.dylib': [4, 5, 6],
    });
    fixture.replaceArchive('android-armv7', {
      'libkdf.a': [1, 2, 3],
    });
    fixture.replaceArchive('android-aarch64', {
      'libkdf.a': [4, 5, 6],
    });
    server.listen((request) async {
      fixture.requests.add(request.uri.path);
      final bytes = fixture.archives[path.posix.basename(request.uri.path)];
      if (bytes != null) {
        request.response.add(bytes);
      } else if (request.uri.path == '/main/' || request.uri.path == '/') {
        request.response.write(
          fixture.names.values
              .map((name) => '<a href="$name">$name</a>')
              .join(),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    return fixture;
  }

  void replaceArchive(String platform, Map<String, List<int>> files) {
    final suffix = switch (platform) {
      'windows' => 'win-x86-64',
      'macos' => 'mac-universal',
      _ => platform,
    };
    final name = 'kdf_${commit.substring(0, 7)}-$suffix.zip';
    final zipped = Process.runSync(Platform.isWindows ? 'python' : 'python3', [
      '-c',
      'import io,json,sys,zipfile\n'
          'out=io.BytesIO()\n'
          'with zipfile.ZipFile(out,"w") as archive:\n'
          ' for name,values in json.loads(sys.argv[1]).items():\n'
          '  archive.writestr(name,bytes(values))\n'
          'sys.stdout.buffer.write(out.getvalue())\n',
      jsonEncode(files),
    ], stdoutEncoding: null);
    if (zipped.exitCode != 0) throw StateError('Fixture ZIP creation failed');
    final bytes = zipped.stdout as List<int>;
    names[platform] = name;
    archives[name] = bytes;
    updateManifest((json) {
      final api = json['api'] as Map<String, dynamic>;
      (api['platforms'] as Map<String, dynamic>)[platform] = {
        'matching_pattern': '^${RegExp.escape(name)}\$',
        'valid_zip_sha256_checksums': [sha256.convert(bytes).toString()],
        'path': '$platform/bin',
      };
    });
  }

  void updateManifest(void Function(Map<String, dynamic>) update) {
    final config =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    update(config);
    manifest.writeAsStringSync(jsonEncode(config));
  }

  Future<void> prepare(String target) => HttpOverrides.runWithHttpOverrides(
    () => prefetch.prefetchNativeKdf(
      target: target,
      frameworkDirectory: directory,
    ),
    _LocalHttp(),
  );

  Future<void> verify(String platform) => prefetch.verifyNativeKdfArtifact(
    platform: platform,
    frameworkDirectory: directory,
    config: BuildConfig.fromJson(
      jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>,
    ),
  );

  Future<void> dispose() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  }
}
