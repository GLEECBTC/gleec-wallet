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

/// A step in the wallet-setup funnel.
///
/// [index] is a stable property of the slug, **not** a position in the user's
/// actual path. Assign an index once, never renumber it, and leave a permanent
/// gap when a step is deleted. That is the whole reason the funnel stays
/// comparable across a redesign: a step that disappears shows up as a gap
/// rather than silently shifting every step after it. Values are spaced by 10
/// so a step can be inserted without touching its neighbours.
///
/// Several steps deliberately share an index. [createForm], [importSeedEntry]
/// and [importFileUnlock] are the same *depth* and are mutually exclusive; the
/// `flow` parameter is what tells them apart.
enum OnboardingStep {
  /// The wallet manager opened. Permanent funnel anchor - this is the event
  /// that means "the user saw the setup surface", which `onboarding_start`
  /// does not (that one means "the user committed to a branch").
  walletManagerOpened('wallet_manager_opened', 0),

  /// The wallet-type router screen.
  ///
  /// Retired by the merged entry screen, which leaves index 10 permanently
  /// unused. That gap is the point: it is the evidence the screen was dropped.
  walletTypeSelect('wallet_type_select', 10),

  /// The create-or-import decision.
  setupActionSelect('setup_action_select', 20),

  createForm('create_form', 30),
  importSeedEntry('import_seed_entry', 30),
  importFileUnlock('import_file_unlock', 30),

  importPassword('import_password', 40),

  /// Credentials submitted; waiting on KDF.
  authSubmitted('auth_submitted', 50);

  const OnboardingStep(this.slug, this.stepIndex);

  final String slug;

  /// Named `stepIndex` rather than `index` because every Dart enum already
  /// declares `index` as its declaration ordinal, which is exactly the
  /// position-in-the-list meaning this value must not have.
  final int stepIndex;
}

/// Which branch of wallet setup the user is in.
///
/// Deliberately not [AuthFlow]: steps 0-20 happen before the branch exists, and
/// [AuthFlow] has no value meaning "not decided yet".
enum OnboardingFlowKind {
  undecided('undecided'),
  create('create'),
  importSeed('import_seed'),
  importFile('import_file'),
  hardware('hardware');

  const OnboardingFlowKind(this.value);

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
///
/// Note this is **not** the same milestone as `onboarding_start`: that one
/// fires when the user commits to create-or-import, whereas
/// `onboarding_step_viewed` with `step_index: 0` is the screen-entry event.
/// Keeping both in one series is what makes entry-to-branch drop-off a
/// single-series computation instead of a join across two event names.
class OnboardingStepViewedEventData extends AnalyticsEventData {
  const OnboardingStepViewedEventData({
    required this.step,
    required this.stepIndex,
    required this.flow,
    required this.entryPoint,
    this.existingWalletCount,
  });

  final String step;
  final int stepIndex;
  final String flow;

  /// Which surface the user opened setup from (`header`, `dex`, `nft`, ...).
  /// Without it the funnel cannot be segmented by entry point at all.
  final String entryPoint;

  /// Wallets already stored on this device. `0` means a genuine first run.
  ///
  /// This is the only way to separate new users from returning ones, and the
  /// create-vs-import question is only answerable conditional on that. Null
  /// when the wallets cache has not resolved yet, rather than guessing `0`.
  final int? existingWalletCount;

  @override
  String get name => 'onboarding_step_viewed';

  @override
  JsonMap get parameters => {
    'step': step,
    'step_index': stepIndex,
    'flow': flow,
    'entry_point': entryPoint,
    if (existingWalletCount != null)
      'existing_wallet_count': existingWalletCount!,
  };
}

/// A setup step was completed and the user advanced.
class OnboardingStepCompletedEventData extends AnalyticsEventData {
  const OnboardingStepCompletedEventData({
    required this.step,
    required this.stepIndex,
    required this.flow,
    required this.entryPoint,
    this.existingWalletCount,
  });

  final String step;
  final int stepIndex;
  final String flow;
  final String entryPoint;
  final int? existingWalletCount;

  @override
  String get name => 'onboarding_step_completed';

  @override
  JsonMap get parameters => {
    'step': step,
    'step_index': stepIndex,
    'flow': flow,
    'entry_point': entryPoint,
    if (existingWalletCount != null)
      'existing_wallet_count': existingWalletCount!,
  };
}

/// The user left a setup step without completing it.
///
/// Abandonment is detected from widget disposal, which does **not** run on a
/// web tab close or an app kill. Treat these counts as a lower bound: the true
/// drop-off is `viewed` minus `completed` per `(step, step_index)`. What this
/// event adds over that subtraction is the distinction between a deliberate
/// back-out and a user who simply vanished.
class OnboardingStepAbandonedEventData extends AnalyticsEventData {
  const OnboardingStepAbandonedEventData({
    required this.step,
    required this.stepIndex,
    required this.flow,
    required this.entryPoint,
    this.existingWalletCount,
  });

  final String step;
  final int stepIndex;
  final String flow;
  final String entryPoint;
  final int? existingWalletCount;

  @override
  String get name => 'onboarding_step_abandoned';

  @override
  JsonMap get parameters => {
    'step': step,
    'step_index': stepIndex,
    'flow': flow,
    'entry_point': entryPoint,
    if (existingWalletCount != null)
      'existing_wallet_count': existingWalletCount!,
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
