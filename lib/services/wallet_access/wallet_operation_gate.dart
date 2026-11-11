/// Denies new user-originated operations when the app is covered or locked.
///
/// This is an application authority, not a cryptographic lock on the wallet
/// engine. Previously submitted swaps and explicitly started automation retain
/// their existing authority and must not acquire a new user-operation permit.
class WalletOperationGate {
  WalletOperationGate();

  static final WalletOperationGate instance = WalletOperationGate();

  bool _installed = false;
  bool _allowed = true;
  String? _walletEntryId;
  Object? _sessionIdentity;
  int _generation = 0;

  bool get isInstalled => _installed;
  bool get allowsOperations =>
      !_installed || (_allowed && _walletEntryId != null);
  int get generation => _generation;

  /// Installs the authority for one authenticated wallet session.
  ///
  /// [sessionIdentity] must change on same-wallet reauthentication. Before the
  /// first installation the gate is permissive for headless callers and older
  /// tests; application bootstrap installs it before exposing wallet actions.
  void attachWallet(
    String? walletEntryId, {
    Object? sessionIdentity,
    bool allowOperations = false,
  }) {
    final allowed = allowOperations && walletEntryId != null;
    if (!_installed ||
        _walletEntryId != walletEntryId ||
        !identical(_sessionIdentity, sessionIdentity) ||
        _allowed != allowed) {
      _generation++;
    }
    _installed = true;
    _walletEntryId = walletEntryId;
    _sessionIdentity = sessionIdentity;
    _allowed = allowed;
  }

  /// Revokes all captured actions, including callbacks waiting on other work.
  void block() {
    _installed = true;
    _allowed = false;
    _generation++;
  }

  void allow({required String walletEntryId}) {
    if (!_installed || _walletEntryId != walletEntryId) {
      throw const WalletOperationDenied(WalletOperationDenial.walletChanged);
    }
    if (!_allowed) _generation++;
    _allowed = true;
  }

  WalletOperationPermit capture({String? expectedWalletEntryId}) {
    _ensureAllowed(expectedWalletEntryId);
    return WalletOperationPermit._(
      this,
      _generation,
      _walletEntryId,
      _sessionIdentity,
    );
  }

  void _ensureAllowed(String? expectedWalletEntryId) {
    if (!_installed) return;
    if (_walletEntryId == null) {
      throw const WalletOperationDenied(WalletOperationDenial.signedOut);
    }
    if (expectedWalletEntryId != null &&
        expectedWalletEntryId != _walletEntryId) {
      throw const WalletOperationDenied(WalletOperationDenial.walletChanged);
    }
    if (!_allowed) {
      throw const WalletOperationDenied(WalletOperationDenial.locked);
    }
  }

  void _ensureCurrent(WalletOperationPermit permit) {
    _ensureAllowed(permit._walletEntryId);
    if (permit._generation != _generation ||
        !identical(permit._sessionIdentity, _sessionIdentity)) {
      throw const WalletOperationDenied(WalletOperationDenial.staleOperation);
    }
  }
}

/// Capture before asynchronous preparation; recheck immediately before dispatch.
///
/// A check after dispatch cannot undo a financial operation. This object never
/// contains a password, seed, RPC credential or biometric result.
class WalletOperationPermit {
  WalletOperationPermit._(
    this._gate,
    this._generation,
    this._walletEntryId,
    this._sessionIdentity,
  );

  final WalletOperationGate _gate;
  final int _generation;
  final String? _walletEntryId;
  final Object? _sessionIdentity;

  void ensureCurrent() => _gate._ensureCurrent(this);
}

enum WalletOperationDenial { locked, signedOut, walletChanged, staleOperation }

class WalletOperationDenied implements Exception {
  const WalletOperationDenied(this.reason);

  final WalletOperationDenial reason;

  @override
  String toString() => 'WalletOperationDenied(${reason.name})';
}
