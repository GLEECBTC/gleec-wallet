part of 'auth_bloc.dart';

/// Managed sign-in shows one localised message for every failure, so its
/// cause has to reach the log. Wallet-access errors name only their failure
/// kind, never the stored credential.
extension _ManagedSignInLogging on AuthBloc {
  void _logManagedSignInFailure(
    Object error,
    StackTrace stackTrace, {
    required bool canceled,
    required bool automatic,
  }) {
    final trigger = automatic ? 'automatic' : 'explicit';
    if (canceled) {
      // Routine when an automatic unlock has no user gesture to prompt with.
      _log.info('Managed $trigger sign-in canceled');
      return;
    }
    final cause = switch (error) {
      WalletAccessException(:final failure) => failure.name,
      AuthException(:final type) => type.name,
      _ => error.runtimeType.toString(),
    };
    _log.shout('Managed $trigger sign-in failed ($cause)', null, stackTrace);
  }
}
