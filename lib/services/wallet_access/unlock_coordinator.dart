import 'dart:async';

import 'package:web_dex/services/wallet_access/wallet_operation_gate.dart';
import 'package:web_dex/services/wallet_access/wallet_access_types.dart';

/// Non-secret app access state, independent of the running wallet engine.
class WalletUnlockState {
  const WalletUnlockState({
    required this.walletEntryId,
    required this.requiresAuthentication,
    required this.isLocked,
    required this.isForeground,
    required this.isObscured,
    required this.unlockInProgress,
    required this.generation,
  });

  final String? walletEntryId;
  final bool requiresAuthentication;
  final bool isLocked;
  final bool isForeground;
  final bool isObscured;
  final bool unlockInProgress;
  final int generation;

  bool get hasWallet => walletEntryId != null;
  bool get coversContent => hasWallet && (isObscured || isLocked);
  bool get canStartUnlock =>
      hasWallet && isForeground && isLocked && !unlockInProgress;
}

/// An opaque single-operation token. It is never persisted between launches.
class UnlockAttempt {
  UnlockAttempt._(this._owner, this._generation, this.walletEntryId);

  final WalletUnlockCoordinator _owner;
  final int _generation;
  final String walletEntryId;
}

/// Coordinates an app lock without stopping KDF or retaining wallet secrets.
///
/// Elapsed time is sampled on resume rather than trusting a background timer.
/// [monotonicNow] is injectable so clock changes and suspended timers can be
/// tested without sleeping. Its origin is arbitrary and must be monotonic.
class WalletUnlockCoordinator {
  WalletUnlockCoordinator({
    Duration Function()? monotonicNow,
    WalletOperationGate? operationGate,
    Duration backgroundGrace = const Duration(seconds: 30),
  }) : _now = monotonicNow ?? _createMonotonicClock(),
       operationGate = operationGate ?? WalletOperationGate.instance,
       _backgroundGrace = _validateGrace(backgroundGrace) {
    // Construction is the app bootstrap boundary: no authenticated wallet is
    // allowed to act before its first explicit attachment.
    this.operationGate.attachWallet(null);
  }

  final Duration Function() _now;
  final WalletOperationGate operationGate;
  // Gate changes are synchronous; notifications are asynchronous so a listener
  // can safely begin the automatic unlock in response to a locked state.
  final _changes = StreamController<WalletUnlockState>.broadcast();
  final _closeSensitiveViews = StreamController<void>.broadcast(sync: true);

  String? _walletEntryId;
  Object? _sessionIdentity;
  bool _requiresAuthentication = false;
  bool _locked = false;
  bool _foreground = true;
  bool _obscured = false;
  bool _automaticAttemptConsumed = false;
  bool _disposed = false;
  int _generation = 0;
  int _authorizationGeneration = 0;
  int _systemPromptDepth = 0;
  int _systemDialogDepth = 0;
  Duration _backgroundGrace;
  Duration? _inactiveAt;
  Duration? _backgroundAt;
  Duration? _completedUnlockAwaitingResumeAt;
  _SystemPromptReturn? _systemPromptReturn;
  UnlockAttempt? _attempt;

  Stream<WalletUnlockState> get changes => _changes.stream;

  /// Secret views close on inactivity, even during a permitted system dialog.
  Stream<void> get sensitiveViewsMustClose => _closeSensitiveViews.stream;

  Duration get backgroundGrace => _backgroundGrace;

  /// Revokes sensitive work independently of expected engine-session attaches.
  int get authorizationGeneration => _authorizationGeneration;
  bool get hasSystemPrompt => _systemPromptDepth > 0 || _attempt != null;

  WalletUnlockState get state => WalletUnlockState(
    walletEntryId: _walletEntryId,
    requiresAuthentication: _requiresAuthentication,
    isLocked: _locked,
    isForeground: _foreground,
    isObscured: _obscured,
    unlockInProgress: hasSystemPrompt,
    generation: _generation,
  );

  /// Attaches a known wallet; only a completed authentication supplies true.
  ///
  /// Reattaching the same session does not reset a background grace period or
  /// clear an existing app lock. This prevents SDK lifecycle repair from
  /// publishing an unlocked session over the app's lock authority.
  void attachWallet(
    String? walletEntryId, {
    required bool requiresAuthentication,
    bool authenticated = false,
    Object? sessionIdentity,
  }) {
    if (_disposed) return;
    final sameSession =
        _walletEntryId == walletEntryId &&
        identical(_sessionIdentity, sessionIdentity);
    if (sameSession && _requiresAuthentication == requiresAuthentication) {
      return;
    }
    _generation++;
    _attempt = null;
    _completedUnlockAwaitingResumeAt = null;
    _systemPromptReturn = null;
    _automaticAttemptConsumed = false;
    _walletEntryId = walletEntryId;
    _sessionIdentity = sessionIdentity;
    _requiresAuthentication = walletEntryId != null && requiresAuthentication;
    _locked = _requiresAuthentication && !authenticated;
    if (authenticated && !_foreground) {
      _completedUnlockAwaitingResumeAt = _now();
    }
    // Preserve an existing background deadline even across wallet changes.
    _obscured = !_foreground;
    operationGate.attachWallet(
      walletEntryId,
      sessionIdentity: sessionIdentity,
      allowOperations: _foreground && !_locked,
    );
    _publish();
  }

  /// Hide content and revoke queued operations at the first interruption.
  /// Android can return from another app without reporting hidden/paused, so
  /// unowned inactivity must start the same deadline as full backgrounding.
  void inactive() {
    if (_disposed) return;
    _inactiveAt ??= _now();
    // New inactivity after a completed ceremony is a separate interruption,
    // not the foreground handoff already awaited by that ceremony.
    final ownsInterruption =
        hasSystemPrompt &&
        _systemPromptReturn == null &&
        _completedUnlockAwaitingResumeAt == null;
    if (!ownsInterruption) {
      _authorizationGeneration++;
      _invalidateAttempt();
    }
    // A destination picker proves no authentication. Its continuation can
    // survive the interruption, but its elapsed time never extends access.
    if (!ownsInterruption || _systemDialogDepth > 0) {
      _backgroundAt ??= _inactiveAt;
      if (_backgroundGrace == Duration.zero) _requireUnlock();
    }
    _foreground = false;
    _obscured = true;
    operationGate.block();
    _closeSensitiveViews.add(null);
    _publish();
  }

  void background() {
    if (_disposed) return;
    _foreground = false;
    _obscured = true;
    _backgroundAt ??= _now();
    operationGate.block();
    _closeSensitiveViews.add(null);
    // Some native credential confirmations launch a separate activity. Their
    // pending challenge remains valid, but nothing can dispatch while hidden.
    if (!hasSystemPrompt ||
        _systemPromptReturn != null ||
        _completedUnlockAwaitingResumeAt != null) {
      _authorizationGeneration++;
      _invalidateAttempt();
    }
    if (_backgroundGrace == Duration.zero) _requireUnlock();
    _publish();
  }

  void resume() {
    if (_disposed) return;
    final awaySince = _backgroundAt;
    final completedAt = _completedUnlockAwaitingResumeAt;
    final promptReturn = _systemPromptReturn;
    // Native dialogs can deliver a verified credential just before `resumed`.
    // Consume that same ceremony on foreground arrival, including immediate
    // lock mode, but do not let a completed background result become a lasting
    // unlocked lease when the user stays in another app.
    final completingUnlockReturn =
        completedAt != null &&
        _now() >= completedAt &&
        _now() - completedAt <= const Duration(seconds: 5);
    final completingPromptReturn =
        promptReturn != null &&
        promptReturn.wasUnlocked &&
        promptReturn.generation == _generation &&
        promptReturn.authorization == _authorizationGeneration &&
        _now() >= promptReturn.completedAt &&
        _now() - promptReturn.completedAt <= const Duration(seconds: 5);
    _completedUnlockAwaitingResumeAt = null;
    _systemPromptReturn = null;
    if (completingUnlockReturn || completingPromptReturn) {
      _locked = false;
    } else if (awaySince != null &&
        _elapsedSince(awaySince) >= _backgroundGrace) {
      _requireUnlock();
    }
    _backgroundAt = null;
    _inactiveAt = null;
    _foreground = true;
    _obscured = false;
    _syncOperationGate();
    _publish();
  }

  /// A user-requested lock must not immediately unlock itself automatically.
  void lock() {
    if (_disposed) return;
    _authorizationGeneration++;
    if (!_requiresAuthentication) return;
    _invalidateAttempt();
    _locked = true;
    _automaticAttemptConsumed = true;
    operationGate.block();
    _closeSensitiveViews.add(null);
    _publish();
  }

  void deviceLocked() {
    if (_disposed) return;
    _authorizationGeneration++;
    _invalidateAttempt();
    _foreground = false;
    _obscured = true;
    _backgroundAt ??= _now();
    _requireUnlock();
    operationGate.block();
    _closeSensitiveViews.add(null);
    _publish();
  }

  /// Revoke immediately, including an unattended session in another tab.
  /// The access service reloads actual protection before attaching it again.
  void protectionChanged() {
    if (_disposed) return;
    _authorizationGeneration++;
    _invalidateAttempt();
    _requiresAuthentication = _walletEntryId != null;
    _locked = _walletEntryId != null;
    _automaticAttemptConsumed = true;
    operationGate.block();
    _closeSensitiveViews.add(null);
    _publish();
  }

  void setBackgroundGrace(Duration grace) {
    if (_disposed) return;
    _backgroundGrace = _validateGrace(grace);
    final awaySince = _backgroundAt;
    if (awaySince != null && _elapsedSince(awaySince) >= _backgroundGrace) {
      _requireUnlock();
    }
    _syncOperationGate();
    _publish();
  }

  /// Caller starts at most one prompt and holds no password in this object.
  UnlockAttempt? beginUnlock({bool automatic = false}) {
    if (_disposed || !state.canStartUnlock) return null;
    if (automatic && _automaticAttemptConsumed) return null;
    _automaticAttemptConsumed = true;
    final attempt = UnlockAttempt._(this, _generation, _walletEntryId!);
    _attempt = attempt;
    _publish();
    return attempt;
  }

  /// Accepts only the still-owned challenge. Actual credential verification is
  /// the caller's responsibility; a success callback alone is not sufficient.
  bool completeUnlock(UnlockAttempt attempt) {
    if (!_owns(attempt)) return false;
    _attempt = null;
    _locked = !_foreground;
    // A native confirmation may finish before Flutter's resumed notification.
    // Keep the UI locked until that same ceremony reaches the foreground.
    if (!_foreground) {
      _completedUnlockAwaitingResumeAt = _now();
    }
    _syncOperationGate();
    _publish();
    return true;
  }

  void cancelUnlock(UnlockAttempt attempt) {
    if (!_owns(attempt)) return;
    _attempt = null;
    _automaticAttemptConsumed = true;
    _publish();
  }

  /// Marks only dialogs started by this app. It never extends the grace.
  Future<T> runSystemPrompt<T>(
    Future<T> Function() action, {
    bool waitForForeground = false,
  }) => _runOwnedPrompt(
    action,
    waitForForeground: waitForForeground,
    authenticatedReturn: true,
  );

  /// Destination selection proves no authentication. Preserve normal app lock
  /// timing, await only its foreground return, and leave any lock in place.
  Future<T> runSystemDialogAwaitingForeground<T>(Future<T> Function() action) =>
      _runOwnedPrompt(
        action,
        waitForForeground: true,
        authenticatedReturn: false,
      );

  /// Finish only the already verified unlock's bounded foreground handoff.
  Future<void> awaitVerifiedUnlockForeground() async {
    if (_foreground && !_locked) return;
    if (_completedUnlockAwaitingResumeAt == null) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
    await runSystemDialogAwaitingForeground(() async {});
    if (!_foreground || _locked) {
      throw const WalletAccessException(WalletAccessFailure.staleOperation);
    }
  }

  Future<T> _runOwnedPrompt<T>(
    Future<T> Function() action, {
    required bool waitForForeground,
    required bool authenticatedReturn,
  }) async {
    if (_disposed) throw StateError('Unlock coordinator is disposed');
    final generation = _generation;
    final authorization = _authorizationGeneration;
    final wasUnlocked = !_locked;
    _SystemPromptReturn? returnMarker;
    bool isCurrent() =>
        !_disposed &&
        generation == _generation &&
        authorization == _authorizationGeneration;
    _systemPromptDepth++;
    if (!authenticatedReturn) _systemDialogDepth++;
    _publish();
    try {
      final result = await action();
      if (waitForForeground && !isCurrent()) {
        throw const WalletAccessException(WalletAccessFailure.staleOperation);
      }
      // Some OS versions deliver resumed before the successful credential
      // callback. Complete the same still-owned ceremony in either order.
      if (waitForForeground &&
          authenticatedReturn &&
          _foreground &&
          wasUnlocked &&
          _locked) {
        _locked = false;
        _syncOperationGate();
        _publish();
      }
      // Opt-in callers must have verified the protected operation's success.
      // Native authentication can reply before Flutter receives `resumed`.
      // Keep ownership only through that bounded handoff, never dispatch while
      // hidden or turn a canceled/stale ceremony into a new app unlock lease.
      if (waitForForeground && !_foreground) {
        if (!isCurrent()) {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        }
        returnMarker = _SystemPromptReturn(
          generation: generation,
          authorization: authorization,
          completedAt: _now(),
          wasUnlocked: authenticatedReturn && wasUnlocked,
        );
        _systemPromptReturn = returnMarker;
        final returned = Completer<void>();
        final subscription = changes.listen(
          (_) {
            if ((_foreground || !isCurrent()) && !returned.isCompleted) {
              returned.complete();
            }
          },
          onDone: () {
            if (!returned.isCompleted) returned.complete();
          },
        );
        try {
          await returned.future.timeout(const Duration(seconds: 5));
        } on Object {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        } finally {
          await subscription.cancel();
        }
        if (!isCurrent() ||
            !_foreground ||
            (authenticatedReturn && _locked) ||
            _now() < returnMarker.completedAt ||
            _now() - returnMarker.completedAt > const Duration(seconds: 5)) {
          throw const WalletAccessException(WalletAccessFailure.staleOperation);
        }
      }
      if (!authenticatedReturn && _locked) {
        // The export continuation owns any explicit reauthorization. An
        // automatic unlock listener must not race it on dialog return.
        _automaticAttemptConsumed = true;
      }
      return result;
    } finally {
      if (identical(_systemPromptReturn, returnMarker)) {
        _systemPromptReturn = null;
      }
      _systemPromptDepth--;
      if (!authenticatedReturn) _systemDialogDepth--;
      // Owned dialogs only exempt their live interaction. If one finishes
      // while the app stays inactive, retain the original interruption time;
      // a missing resumed event must not leave an indefinite unlocked lease.
      if (!hasSystemPrompt && !_foreground && _inactiveAt != null) {
        _backgroundAt ??= _inactiveAt;
        if (_elapsedSince(_backgroundAt!) >= _backgroundGrace) _requireUnlock();
      }
      _publish();
    }
  }

  bool _owns(UnlockAttempt attempt) =>
      !_disposed &&
      identical(attempt._owner, this) &&
      identical(_attempt, attempt) &&
      attempt._generation == _generation &&
      attempt.walletEntryId == _walletEntryId;

  void _invalidateAttempt() {
    _generation++;
    _attempt = null;
    _completedUnlockAwaitingResumeAt = null;
    _systemPromptReturn = null;
  }

  void _requireUnlock() {
    if (!_requiresAuthentication || _walletEntryId == null) return;
    if (!_locked) {
      if (!hasSystemPrompt) _authorizationGeneration++;
      _automaticAttemptConsumed = false;
    }
    _locked = true;
  }

  void _syncOperationGate() {
    final walletId = _walletEntryId;
    if (walletId != null && _foreground && !_locked) {
      operationGate.allow(walletEntryId: walletId);
    } else {
      operationGate.block();
    }
  }

  Duration _elapsedSince(Duration start) {
    final elapsed = _now() - start;
    // A faulty clock injection must never prolong an existing unlocked lease.
    return elapsed.isNegative ? _backgroundGrace : elapsed;
  }

  void _publish() {
    if (!_disposed) _changes.add(state);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _authorizationGeneration++;
    _invalidateAttempt();
    operationGate.block();
    await _changes.close();
    await _closeSensitiveViews.close();
  }

  static Duration _validateGrace(Duration grace) {
    if (grace.isNegative) throw ArgumentError.value(grace, 'backgroundGrace');
    return grace;
  }

  static Duration Function() _createMonotonicClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }
}

class _SystemPromptReturn {
  const _SystemPromptReturn({
    required this.generation,
    required this.authorization,
    required this.completedAt,
    required this.wasUnlocked,
  });
  final int generation;
  final int authorization;
  final Duration completedAt;
  final bool wasUnlocked;
}
