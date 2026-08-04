import 'package:get_it/get_it.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';
import 'package:web_dex/bloc/analytics/analytics_repo.dart';

/// How the user proved they may open this wallet.
///
/// Today only [password] occurs. The rest exist so the sign-in funnel keeps a
/// single event name as unlock methods land, rather than forking into
/// incomparable `auth_signin` and `auth_unlock` series.
enum AuthMethod {
  password('password'),
  biometric('biometric'),
  passkey('passkey'),
  passcode('passcode'),
  hardwareWallet('hardware_wallet');

  const AuthMethod(this.value);

  final String value;
}

/// Which flow the user arrived through. `wallet_created`/`wallet_imported`
/// already cover the outcome; this is the auth leg of each.
enum AuthFlow {
  signIn('sign_in'),
  register('register'),
  restore('restore'),
  legacyMigration('legacy_migration'),
  sessionRestore('session_restore');

  const AuthFlow(this.value);

  final String value;
}

/// Why the user is no longer signed in.
enum LogoutReason {
  /// The user chose to log out.
  userInitiated('user_initiated'),

  /// Auth failed partway and the session was torn down.
  authFailure('auth_failure');

  const LogoutReason(this.value);

  final String value;
}

/// Sign-in succeeded.
///
/// [durationMs] is the auth window only - `signin_started` to `signed_in` - not
/// time to a usable wallet. `time_to_first_balance` is the number that answers
/// "when could the user see their money"; this one isolates the auth leg so a
/// regression can be attributed to auth rather than to activation.
class AuthSignInSucceededEventData extends AnalyticsEventData {
  const AuthSignInSucceededEventData({
    required this.method,
    required this.flow,
    required this.hdType,
    required this.durationMs,
  });

  final String method;
  final String flow;
  final String hdType;
  final int durationMs;

  @override
  String get name => 'auth_signin_succeeded';

  @override
  JsonMap get parameters => {
    'method': method,
    'flow': flow,
    'hd_type': hdType,
    'duration_ms': durationMs,
  };
}

/// Sign-in failed. No failure event existed before this, so every abandoned
/// login looked identical to a user who never tried.
///
/// [failureType] is the `AuthExceptionType` name, which is a closed set - it
/// never carries a wallet name, a password, or a free-form message.
class AuthSignInFailedEventData extends AnalyticsEventData {
  const AuthSignInFailedEventData({
    required this.method,
    required this.flow,
    required this.failureType,
  });

  final String method;
  final String flow;
  final String failureType;

  @override
  String get name => 'auth_signin_failed';

  @override
  JsonMap get parameters => {
    'method': method,
    'flow': flow,
    'failure_type': failureType,
  };
}

/// The session ended. Pairs with the sign-in events so session length is
/// answerable; previously logout emitted nothing at all.
class AuthLogoutEventData extends AnalyticsEventData {
  const AuthLogoutEventData({required this.reason});

  final String reason;

  @override
  String get name => 'auth_logout';

  @override
  JsonMap get parameters => {'reason': reason};
}

/// A step in the wallet-setup funnel became visible.
///
/// `onboarding_start` and `wallet_created` exist, with nothing in between, so a
/// drop-off could be located only to "somewhere in onboarding". [step] is a
/// stable slug, and [stepIndex] keeps ordering answerable when steps change.
class OnboardingStepViewedEventData extends AnalyticsEventData {
  const OnboardingStepViewedEventData({
    required this.step,
    required this.stepIndex,
    required this.flow,
  });

  final String step;
  final int stepIndex;
  final String flow;

  @override
  String get name => 'onboarding_step_viewed';

  @override
  JsonMap get parameters => {
    'step': step,
    'step_index': stepIndex,
    'flow': flow,
  };
}

/// A setup step was completed and the user advanced.
class OnboardingStepCompletedEventData extends AnalyticsEventData {
  const OnboardingStepCompletedEventData({
    required this.step,
    required this.stepIndex,
    required this.flow,
  });

  final String step;
  final int stepIndex;
  final String flow;

  @override
  String get name => 'onboarding_step_completed';

  @override
  JsonMap get parameters => {
    'step': step,
    'step_index': stepIndex,
    'flow': flow,
  };
}

/// The user left a setup step without completing it.
class OnboardingStepAbandonedEventData extends AnalyticsEventData {
  const OnboardingStepAbandonedEventData({
    required this.step,
    required this.stepIndex,
    required this.flow,
  });

  final String step;
  final int stepIndex;
  final String flow;

  @override
  String get name => 'onboarding_step_abandoned';

  @override
  JsonMap get parameters => {
    'step': step,
    'step_index': stepIndex,
    'flow': flow,
  };
}

/// Sends an auth event without letting analytics break authentication.
///
/// `AnalyticsRepo` is registered during bootstrap, but auth can run before that
/// in tests and on the session-restore path, and a missing analytics singleton
/// must never be the reason a user cannot open their wallet. Unregistered is a
/// no-op rather than a throw.
void logAuthEvent(AnalyticsEventData data) {
  if (!GetIt.I.isRegistered<AnalyticsRepo>()) return;
  GetIt.I<AnalyticsRepo>().queueEvent(data).ignore();
}
