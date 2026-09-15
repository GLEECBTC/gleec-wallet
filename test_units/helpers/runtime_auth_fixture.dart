import 'dart:async';

import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_local_auth/src/auth/auth_session.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

/// Issues real owner-scoped contexts for hand-written auth fixtures.
mixin RuntimeAuthFixture implements KomodoDefiLocalAuth {
  final runtimeSessions = AuthSessionTracker();
  StreamSubscription<KdfUser?>? _source;

  @override
  Stream<KdfUser?> get authStateChanges => const Stream.empty();

  @override
  Future<AuthSessionContext> captureSessionContext() async {
    final epoch = runtimeSessions.epoch;
    final previous = runtimeSessions.current;
    final user = await currentUser;
    final accepted = runtimeSessions.current;
    if (epoch != runtimeSessions.epoch ||
        (accepted != null &&
            !identical(previous, accepted) &&
            user?.walletId != accepted.walletId)) {
      throw const AuthSessionChangedException();
    }
    runtimeSessions.observe(user);
    return runtimeSessions.current ?? (throw AuthException.notSignedIn());
  }

  @override
  bool isSessionContextCurrent(AuthSessionContext context) =>
      runtimeSessions.isCurrent(context);

  @override
  void ensureSessionContextCurrent(AuthSessionContext context) {
    if (!isSessionContextCurrent(context)) {
      throw const AuthSessionChangedException();
    }
  }

  @override
  Stream<AuthSessionContext?> watchSessionContext() {
    _source ??= authStateChanges.listen(runtimeSessions.observe);
    return runtimeSessions.changes;
  }
}
