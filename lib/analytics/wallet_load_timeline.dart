import 'package:logging/logging.dart';

/// Named marks on the path from process start to "the user can see their
/// money".
///
/// Each mark is recorded at most once per session. The reference point differs
/// per mark because the useful question differs per mark - see
/// [WalletLoadTimeline.mark].
enum WalletLoadMark {
  /// Flutter has painted. Everything awaited before `runApp` lands on this
  /// number, which is why it is the gate for moving work off that chain.
  appFirstFrame('app_first_frame'),

  /// The wallet secret has been recovered from its seal and sign-in can be
  /// attempted. Not yet reached on any platform - the vault lands in S2 - so
  /// this mark is simply absent until then, rather than being faked.
  vaultUnsealed('vault_unsealed'),

  /// A sign-in attempt has begun. The start of the auth window.
  signInStarted('signin_started'),

  /// `AuthBlocState.loggedIn` has been emitted. The end of the auth window.
  signedIn('signed_in'),

  /// The first frame in which a wallet total in USD can be computed, i.e. at
  /// least one asset has both a balance and a price.
  firstBalance('first_balance');

  const WalletLoadMark(this.eventName);

  /// Snake-case name, so log lines and bench keys match the analytics vocabulary.
  final String eventName;
}

/// Wall-clock anchor for "how long until the user could see their money".
///
/// The app already measures page-interactive delay (`page_interactive_delay`,
/// hidden loading logo) and list scrolling
/// (`wallet_list_half_viewport_reached`), and neither answers the question
/// users actually complained about: balances took minutes to appear. A page can
/// be interactive, and a list can be scrolled, while every row still shows a
/// placeholder.
///
/// So this anchors on sign-in and stops at the first moment a wallet total in
/// USD can be computed. That is the first frame in which the number the user
/// came for is on screen.
///
/// Deliberately a process-global rather than a bloc: the marks are observed in
/// `main`, in the auth layer and in a widget several routes away, and threading
/// timestamps between them through app state would be a much larger change for
/// something that is pure instrumentation.
class WalletLoadTimeline {
  WalletLoadTimeline._();

  static final WalletLoadTimeline instance = WalletLoadTimeline._();

  final _log = Logger('WalletLoadTimeline');

  /// Process start. Survives [reset] - a second login in the same process does
  /// not restart the app.
  DateTime? _processStart;

  final Map<WalletLoadMark, DateTime> _marks = {};

  bool _reported = false;

  /// Anchors the process-scoped marks. Call as early in `main` as possible.
  /// Idempotent, and falls back to the first mark recorded if never called, so
  /// a missed call degrades the numbers rather than crashing.
  void markProcessStart() => _processStart ??= DateTime.now();

  /// Records [mark] and logs it at INFO, so the numbers are readable in a
  /// release build without an analytics backend.
  ///
  /// First write wins: the interactive login and the session-restore paths both
  /// reach [WalletLoadMark.signedIn], and the earliest one is the honest start.
  void mark(WalletLoadMark mark) {
    if (_marks.containsKey(mark)) return;
    final now = DateTime.now();
    _processStart ??= now;
    _marks[mark] = now;

    final reference = _referenceFor(mark);
    final referenceAt = reference == null ? _processStart! : _marks[reference];
    // A mark whose reference was never recorded is still worth logging - it
    // just cannot be expressed as a delta.
    if (referenceAt == null) {
      _log.info('${mark.eventName} reached (no ${reference!.eventName} mark)');
      return;
    }
    final elapsedMs = now.difference(referenceAt).inMilliseconds;
    final from = reference?.eventName ?? 'process_start';
    _log.info('${mark.eventName} reached ${elapsedMs}ms after $from');
  }

  /// What each mark is measured against. Process-scoped marks measure from
  /// process start; the auth window measures from its own start; and
  /// time-to-first-balance measures from sign-in, which is the number the
  /// `time_to_first_balance` event has always reported.
  WalletLoadMark? _referenceFor(WalletLoadMark mark) => switch (mark) {
    WalletLoadMark.appFirstFrame => null,
    WalletLoadMark.vaultUnsealed => null,
    WalletLoadMark.signInStarted => null,
    WalletLoadMark.signedIn => WalletLoadMark.signInStarted,
    WalletLoadMark.firstBalance => WalletLoadMark.signedIn,
  };

  /// Starts the window. Idempotent within a session: the interactive login and
  /// the session-restore paths both reach this, and the first one is the honest
  /// start.
  void markSignedIn() => mark(WalletLoadMark.signedIn);

  /// Ends the session so the next login measures itself, not the last one.
  /// Process-scoped state - [markProcessStart] and
  /// [WalletLoadMark.appFirstFrame] - is deliberately kept: logging out does
  /// not restart the app, and re-recording either on the next login would
  /// report a startup cost that was never paid.
  void reset() {
    _marks.removeWhere((mark, _) => mark != WalletLoadMark.appFirstFrame);
    _reported = false;
  }

  /// Milliseconds since sign-in, or null if the window is closed or already
  /// reported.
  ///
  /// Returns non-null exactly once per session, so the caller can fire the
  /// analytics event straight from a `build` method without its own latch.
  int? takeElapsedMs() {
    final signedInAt = _marks[WalletLoadMark.signedIn];
    if (signedInAt == null || _reported) return null;
    _reported = true;
    mark(WalletLoadMark.firstBalance);
    return DateTime.now().difference(signedInAt).inMilliseconds;
  }

  /// Milliseconds between two recorded marks, or null if either is missing.
  /// For tests and the bench harness, which assert on deltas rather than
  /// scraping log lines.
  int? elapsedMsBetween(WalletLoadMark from, WalletLoadMark to) {
    final start = _marks[from];
    final end = _marks[to];
    if (start == null || end == null) return null;
    return end.difference(start).inMilliseconds;
  }

  /// Every recorded mark as milliseconds since process start. Absent marks are
  /// absent from the map rather than zero - a stage that never ran and a stage
  /// that took no time are different results.
  Map<String, int> snapshotMsSinceProcessStart() {
    final processStart = _processStart;
    if (processStart == null) return const {};
    return {
      for (final entry in _marks.entries)
        entry.key.eventName: entry.value
            .difference(processStart)
            .inMilliseconds,
    };
  }
}
