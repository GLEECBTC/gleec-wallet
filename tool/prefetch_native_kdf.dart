import 'dart:convert';
import 'dart:io';

import 'package:komodo_wallet_build_transformer/src/steps/fetch_defi_api_build_step.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/api/api_artifact_provenance.dart';
import 'package:komodo_wallet_build_transformer/src/steps/models/build_config.dart';
import 'package:komodo_wallet_build_transformer/src/util/cli_util.dart';
import 'package:komodo_wallet_build_transformer/src/util/logging.dart';
import 'package:path/path.dart' as path;

/// Native configuration runs before Flutter's asset transformers on a clean
/// checkout. Prepare the selected engine here, using the transformer's normal
/// checksum, extraction and provenance rules, before CMake or CocoaPods runs.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 ||
      !nativeKdfTargets.containsKey(arguments.single)) {
    stderr.writeln(
      'Usage: dart run tool/prefetch_native_kdf.dart '
      '<windows|macos|linux|ios|android>',
    );
    exitCode = 64;
    return;
  }
  configureLogToConsole('info');
  try {
    final framework = getDependencyDirectory(
      Directory.current.absolute,
      'komodo_defi_framework',
    );
    if (framework == null) {
      throw _NativeKdfPreparationFailure(
        'Framework package is unavailable; run flutter pub get.',
      );
    }
    await prefetchNativeKdf(
      target: arguments.single,
      frameworkDirectory: framework,
      githubToken: Platform.environment['GITHUB_API_PUBLIC_READONLY_TOKEN'],
    );
    stdout.writeln('Verified native KDF preparation for ${arguments.single}.');
  } on Object catch (error) {
    stderr.writeln(describeNativeKdfPreparationFailure(error));
    exitCode = 1;
  }
}

/// Only locally authored failures can expose their actionable explanation.
/// Transport and filesystem failures may contain credentials or local paths.
String describeNativeKdfPreparationFailure(Object error) =>
    error is _NativeKdfPreparationFailure
    ? 'Native KDF preparation failed: ${error.message}'
    : 'Native KDF preparation failed (${error.runtimeType}).';

class _NativeKdfPreparationFailure extends StateError {
  _NativeKdfPreparationFailure(super.message);
}

const nativeKdfTargets = <String, List<String>>{
  'windows': ['windows'],
  'macos': ['macos'],
  'linux': ['linux'],
  'ios': ['ios'],
  'android': ['android-armv7', 'android-aarch64'],
};

const _requiredLibraries = <String, List<String>>{
  'windows': ['kdflib.dll'],
  'macos': ['libkdflib.dylib'],
  // Linux CMake also bundles kdf, but the SDK runtime requires a native
  // library. A verified executable alone cannot satisfy that requirement.
  'linux': ['libkdflib.so', 'libkdflib_static.so'],
  'ios': ['libkdf.a'],
  'android-armv7': ['libkdf.a'],
  'android-aarch64': ['libkdf.a'],
};

/// This deliberately does not invoke the general transformer's coin-update or
/// documentation steps. The canonical manifest remains byte-for-byte unchanged.
Future<void> prefetchNativeKdf({
  required String target,
  required Directory frameworkDirectory,
  String? githubToken,
}) async {
  final platforms = nativeKdfTargets[target];
  if (platforms == null) throw ArgumentError.value(target, 'target');
  final manifest = File(
    path.join(frameworkDirectory.path, 'app_build', 'build_config.json'),
  );
  final originalManifest = await manifest.readAsString();
  final config = BuildConfig.fromJson(
    jsonDecode(originalManifest) as Map<String, dynamic>,
  );
  for (final platform in platforms) {
    if (!config.apiConfig.platforms.containsKey(platform)) {
      throw _NativeKdfPreparationFailure(
        'The pinned manifest does not configure $platform.',
      );
    }
  }
  final fetch = FetchDefiApiStep.withBuildConfig(
    config,
    frameworkDirectory,
    manifest,
    githubToken: githubToken,
  );
  for (final platform in platforms) {
    if (config.apiConfig.fetchAtBuildEnabled) {
      // Explicit selection prevents an unrelated platform's publication gate
      // from blocking this platform, without modifying the manifest policy.
      fetch.selectedPlatform = platform;
      await fetch.updatePlatformWithProgress(platform);
    }
    await verifyNativeKdfArtifact(
      platform: platform,
      frameworkDirectory: frameworkDirectory,
      config: config,
    );
    if (await manifest.readAsString() != originalManifest) {
      throw _NativeKdfPreparationFailure(
        'The KDF manifest changed during native preparation.',
      );
    }
  }
}

/// Reuses the SDK's complete runtime digest and provenance comparison. Platform
/// packaging validators still enforce PE/Mach-O architecture and linking rules.
Future<void> verifyNativeKdfArtifact({
  required String platform,
  required Directory frameworkDirectory,
  required BuildConfig config,
}) async {
  final platformConfig = config.apiConfig.platforms[platform];
  final libraries = _requiredLibraries[platform];
  if (platformConfig == null || libraries == null) {
    throw _NativeKdfPreparationFailure(
      'The pinned manifest does not configure this native platform.',
    );
  }
  final destination = resolveApiArtifactDestination(
    trustedRootFolder: frameworkDirectory.path,
    configuredDestinationPath: platformConfig.path,
  );
  final hasLibrary = libraries.any((name) {
    final filename = path.join(destination, name);
    return FileSystemEntity.typeSync(filename, followLinks: false) ==
            FileSystemEntityType.file &&
        File(filename).lengthSync() > 0;
  });
  if (!hasLibrary) {
    throw _NativeKdfPreparationFailure(
      'The pinned $platform archive has no required native library '
      '(${libraries.join(' or ')}). Executable-only startup is disabled.',
    );
  }
  final marker = File(path.join(destination, '.api_last_updated_$platform'));
  if (FileSystemEntity.typeSync(marker.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw _NativeKdfPreparationFailure(
      'The $platform artifact provenance marker is missing.',
    );
  }
  final provenance = ApiArtifactProvenance.fromJson(
    jsonDecode(await marker.readAsString()) as Map<String, dynamic>,
  );
  final artifactDigest = await calculateExtractedApiArtifactSha256(
    platform: platform,
    destinationFolder: destination,
  );
  final runtimeDigest = await calculateExtractedApiRuntimeSetSha256(
    platform: platform,
    destinationFolder: destination,
  );
  if (!platformConfig.matchingConfig.matches(provenance.archiveFilename) ||
      !provenance.matches(
        expectedCommitHash: config.apiConfig.apiCommitHash,
        expectedChecksums: platformConfig.validZipSha256Checksums,
        observedArtifactSha256: artifactDigest,
        observedRuntimeSetSha256: runtimeDigest,
      )) {
    throw _NativeKdfPreparationFailure(
      'The $platform library does not match its pinned artifact.',
    );
  }
}
