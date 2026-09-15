import 'guarded_file_saver_stub.dart'
    if (dart.library.io) 'guarded_file_saver_native.dart'
    if (dart.library.js_interop) 'guarded_file_saver_web.dart'
    as platform;

enum FileSaveOutcome { completed, cancelled, unconfirmed }

/// Saves sensitive exports only after the caller revalidates its session.
///
/// Unlike the general-purpose loader, destination selection does not receive
/// file contents. [beforeWrite] verifies fresh identity asynchronously;
/// [beforeCommit] must synchronously reject a revoked operation/session.
abstract class GuardedFileSaver {
  const GuardedFileSaver();

  factory GuardedFileSaver.fromPlatform() => platform.createGuardedFileSaver();

  Future<FileSaveOutcome> save({
    required String fileName,
    required String data,
    required Future<void> Function() beforeWrite,
    required void Function() beforeCommit,
  });
}
