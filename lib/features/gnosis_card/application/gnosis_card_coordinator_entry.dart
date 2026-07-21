part of 'gnosis_card_coordinator.dart';

abstract class _GnosisCardCoordinatorEntry extends _GnosisCardCoordinatorCore {
  _GnosisCardCoordinatorEntry({
    required super.repository,
    required super.signer,
    required super.externalFlowLauncher,
    required super.paymentGateway,
    super.readiness,
  });

  Future<GnosisCardSnapshot> initialize() async {
    await _refresh();
    final configuration = _snapshot.progress.safeConfiguration;
    if (configuration?.isValid ?? false) {
      await _validateAndRegister(configuration!);
      await _refresh();
    }
    return _snapshot;
  }

  /// Prepares the signer and either restores a valid same-owner session or
  /// returns an exact SIWE challenge for the presentation layer to approve.
  Future<GnosisCardSnapshot> prepareEntry() {
    final active = _entryFlight;
    if (active != null) return active;
    late final Future<GnosisCardSnapshot> flight;
    flight = _prepareEntry().whenComplete(() {
      if (identical(_entryFlight, flight)) _entryFlight = null;
    });
    _entryFlight = flight;
    return flight;
  }

  Future<GnosisCardSnapshot> _prepareEntry() async {
    final generation = _walletGeneration;
    final owner = await readiness.ensureReady();
    if (generation != _walletGeneration) return _snapshot;
    var session = _snapshot.session;
    if (!(session?.isUsableFor(owner.address) ?? false)) {
      session = await _retryTransient(
        () => repository.currentSession(ownerAddress: owner.address),
      );
    }
    if (generation != _walletGeneration) return _snapshot;
    if (session?.isUsableFor(owner.address) ?? false) {
      await _refresh(session: session, clearSiweChallenge: true);
      if (generation != _walletGeneration) return _snapshot;
      await _restoreVerifiedSafe();
      return _snapshot;
    }
    final challenge = await _retryTransient(
      () => repository.createSiweChallenge(ownerAddress: owner.address),
    );
    if (generation != _walletGeneration) return _snapshot;
    _validateSiweChallenge(challenge, owner);
    _snapshot = _snapshot.copyWith(
      siweChallenge: challenge,
      clearSession: true,
    );
    return _snapshot;
  }

  Future<GnosisCardSnapshot> approveSignIn({required String approvalId}) {
    final active = _approvalFlight;
    if (active != null) return active;
    late final Future<GnosisCardSnapshot> flight;
    flight = _approveSignIn(approvalId).whenComplete(() {
      if (identical(_approvalFlight, flight)) _approvalFlight = null;
    });
    _approvalFlight = flight;
    return flight;
  }

  Future<GnosisCardSnapshot> _approveSignIn(String approvalId) async {
    final generation = _walletGeneration;
    final challenge = _snapshot.siweChallenge;
    if (challenge == null) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'The wallet approval request is no longer available.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    if (challenge.approvalId != approvalId) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'The wallet approval request changed before it was approved.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    final expectedOwner = await readiness.ensureReady();
    _validateSiweChallenge(challenge, expectedOwner);
    final signature = await signer.signPersonalMessage(
      challenge.message,
      expectedOwner: expectedOwner,
    );
    if (generation != _walletGeneration) return _snapshot;
    final currentOwner = await signer.owner();
    if (currentOwner.address.toLowerCase() !=
        expectedOwner.address.toLowerCase()) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The active wallet changed during sign-in.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    if (generation != _walletGeneration) return _snapshot;
    final session = await repository.authenticate(
      challenge: challenge,
      ownerAddress: expectedOwner.address,
      signature: signature,
    );
    if (generation != _walletGeneration) return _snapshot;
    if (!session.isUsableFor(
      expectedOwner.address,
      expirySkew: Duration.zero,
    )) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The card session expired. Sign in again to continue.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    final previousOwner = _snapshot.session?.ownerAddress;
    if (previousOwner != null &&
        previousOwner.toLowerCase() != session.ownerAddress.toLowerCase()) {
      _registeredSafe = null;
      _registeredSafeOwner = null;
    }
    await repository.requiredTerms();
    await _refresh(session: session, clearSiweChallenge: true);
    await _restoreVerifiedSafe();
    return _snapshot;
  }

  GnosisCardSnapshot declineSignIn() =>
      _snapshot = _snapshot.copyWith(clearSiweChallenge: true);

  Future<GnosisCardSnapshot> signIn() async {
    await prepareEntry();
    final challenge = _snapshot.siweChallenge;
    if (challenge == null) return _snapshot;
    return approveSignIn(approvalId: challenge.approvalId);
  }
}
