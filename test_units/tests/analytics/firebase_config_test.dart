import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_dex/bloc/analytics/firebase_options_placeholders.dart';
import 'package:xml/xml.dart';

/// Guards the committed Firebase configuration on Apple platforms.
///
/// Two separate things have to stay true, and neither is visible in a diff
/// review of the file that breaks it:
///
/// 1. No real project values are committed. `flutterfire configure` rewrites
///    these files in place as a side effect of pointing local tooling at a
///    Firebase project, so they land in a working tree without anyone
///    deciding to publish them. That happened once already, and shipped a
///    live API key in the macOS release artifact.
/// 2. No `GoogleService-Info.plist` is copied into the app bundle. FirebaseCore
///    reads a bundled plist at plugin registration and raises on a malformed
///    `GOOGLE_APP_ID`, which crashes the app at launch, before Dart runs and
///    outside any error handling the app could install.
const List<String> _plistPaths = <String>[
  'ios/Runner/GoogleService-Info.plist',
  'macos/Runner/GoogleService-Info.plist',
];

const List<String> _appIdFilePaths = <String>[
  'ios/firebase_app_id_file.json',
  'macos/firebase_app_id_file.json',
];

const List<String> _pbxprojPaths = <String>[
  'ios/Runner.xcodeproj/project.pbxproj',
  'macos/Runner.xcodeproj/project.pbxproj',
];

/// Values a real Firebase project has and a placeholder does not: a Google API
/// key, and a well-formed `1:<project number>:<platform>:<hash>` app ID.
final RegExp _googleApiKey = RegExp(r'AIza[0-9A-Za-z_-]{30,}');
final RegExp _realAppId = RegExp(r'\b1:\d+:[a-z]+:[0-9a-f]+\b');

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path should exist');
  return file.readAsStringSync();
}

void main() {
  group('Apple Firebase config:', () {
    test('the committed plists carry no real project values', () {
      for (final path in _plistPaths) {
        final source = _read(path);
        expect(
          _googleApiKey.hasMatch(source),
          isFalse,
          reason: '$path contains a real Google API key',
        );
        expect(
          _realAppId.hasMatch(source),
          isFalse,
          reason: '$path contains a real Firebase app ID',
        );
        expect(
          source.contains(firebaseOptionsPlaceholderMarker),
          isTrue,
          reason: '$path should still hold the placeholder markers',
        );

        final entries = XmlDocument.parse(
          source,
        ).findAllElements('dict').single.childElements.toList();
        final values = <String, String>{
          for (var index = 0; index < entries.length; index += 2)
            entries[index].innerText: entries[index + 1].innerText,
        };
        for (final key in [
          'API_KEY',
          'GCM_SENDER_ID',
          'BUNDLE_ID',
          'PROJECT_ID',
          'STORAGE_BUCKET',
          'GOOGLE_APP_ID',
        ]) {
          expect(
            values[key],
            firebaseOptionsPlaceholderMarker,
            reason: '$path: $key should still be a placeholder',
          );
        }
      }
    });

    test('the committed app-id files carry no real project values', () {
      for (final path in _appIdFilePaths) {
        final values = (jsonDecode(_read(path)) as Map<String, dynamic>).map(
          (key, value) => MapEntry(key, '$value'),
        );

        for (final key in <String>[
          'GOOGLE_APP_ID',
          'FIREBASE_PROJECT_ID',
          'GCM_SENDER_ID',
        ]) {
          expect(
            values[key],
            contains(firebaseOptionsPlaceholderMarker),
            reason: '$path: $key should still be a placeholder',
          );
        }
      }
    });

    test('no Xcode target copies GoogleService-Info.plist into the bundle', () {
      for (final path in _pbxprojPaths) {
        // Xcode comments are labels only; deleting or renaming one must not
        // hide a build-file reference that still bundles the plist.
        final source = _read(
          path,
        ).replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
        final references = RegExp(r'\b([A-Fa-f0-9]{24})\s*=\s*\{([^{}]*)\}')
            .allMatches(source)
            .where(
              (match) =>
                  RegExp(
                    r'\bisa\s*=\s*PBXFileReference\s*;',
                  ).hasMatch(match[2]!) &&
                  match[2]!.contains('GoogleService-Info.plist'),
            );
        expect(
          references,
          isNotEmpty,
          reason: '$path should retain the file reference',
        );
        for (final reference in references) {
          expect(
            RegExp('\\bfileRef\\s*=\\s*${reference[1]}\\s*;').hasMatch(source),
            isFalse,
            reason:
                '$path builds the placeholder plist; FirebaseCore will raise on '
                'its GOOGLE_APP_ID at launch',
          );
        }
      }
    });

    test('placeholder options are recognised in both spellings', () {
      // firebase_options.dart writes `<THIS_IS_AUTOGENERATED>`; the plists
      // write it bare.
      for (final marker in <String>[
        firebaseOptionsPlaceholderMarker,
        '<$firebaseOptionsPlaceholderMarker>',
      ]) {
        expect(
          isPlaceholderFirebaseOptions(
            FirebaseOptions(
              apiKey: marker,
              appId: marker,
              messagingSenderId: marker,
              projectId: marker,
            ),
          ),
          isTrue,
          reason: '$marker should be treated as unconfigured',
        );
      }
    });

    test('a placeholder in any single field is enough to skip init', () {
      const real = FirebaseOptions(
        apiKey: 'AIzaSyExampleExampleExampleExampleExample',
        appId: '1:000000000000:ios:0000000000000000',
        messagingSenderId: '000000000000',
        projectId: 'example-project',
      );

      expect(isPlaceholderFirebaseOptions(real), isFalse);
      expect(
        isPlaceholderFirebaseOptions(
          FirebaseOptions(
            apiKey: real.apiKey,
            appId: '<$firebaseOptionsPlaceholderMarker>',
            messagingSenderId: real.messagingSenderId,
            projectId: real.projectId,
          ),
        ),
        isTrue,
      );

      for (final options in <FirebaseOptions>[
        real.copyWith(projectId: firebaseOptionsPlaceholderMarker),
        real.copyWith(messagingSenderId: firebaseOptionsPlaceholderMarker),
        real.copyWith(authDomain: firebaseOptionsPlaceholderMarker),
        real.copyWith(storageBucket: firebaseOptionsPlaceholderMarker),
        real.copyWith(measurementId: firebaseOptionsPlaceholderMarker),
        real.copyWith(iosBundleId: firebaseOptionsPlaceholderMarker),
      ]) {
        expect(isPlaceholderFirebaseOptions(options), isTrue);
      }
      expect(
        isPlaceholderFirebaseOptions(
          FirebaseOptions(
            apiKey: '<$firebaseOptionsPlaceholderMarker>',
            appId: real.appId,
            messagingSenderId: real.messagingSenderId,
            projectId: real.projectId,
          ),
        ),
        isTrue,
      );
    });
  });
}
