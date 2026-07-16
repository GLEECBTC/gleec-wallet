part of 'deterministic_gnosis_pay_repository.dart';

mixin _DeterministicGnosisPayAuthentication
    on _DeterministicGnosisPayRepositoryState, _DeterministicGnosisPaySupport {
  Future<GnosisOnboardingProgress> onboardingProgress() async {
    _requireOnline();
    return _progress;
  }

  Future<GnosisOnboardingStage> onboardingStage() async =>
      (await onboardingProgress()).nextStage;

  Future<GnosisSiweChallenge> createSiweChallenge({
    required String ownerAddress,
  }) async {
    _requireOnline();
    if (!_isAddress(ownerAddress)) {
      throw _invalidInput('KDF did not return a valid Gnosis owner address.');
    }
    final now = DateTime.now().toUtc();
    _outstandingChallenges.removeWhere(
      (_, challenge) =>
          challenge.isExpired ||
          challenge.ownerAddress.toLowerCase() == ownerAddress.toLowerCase(),
    );
    _nonceSequence += 1;
    final expiresAt = now.add(const Duration(minutes: 10));
    final nonce =
        scenario == GnosisCardScenario.nonceReplay && _usedNonces.isNotEmpty
        ? _usedNonces.first
        : 'gleec${_nonceSequence.toString().padLeft(8, '0')}';
    final message =
        'gleec.app wants you to sign in with your Ethereum account:\n'
        '$ownerAddress\n\nSign in to your Gleec card account. No transaction is sent.\n\n'
        'URI: https://gleec.app/card\nVersion: 1\nChain ID: 100\n'
        'Nonce: $nonce\nIssued At: ${now.toIso8601String()}\n'
        'Expiration Time: ${expiresAt.toIso8601String()}';
    final challenge = GnosisSiweChallenge(
      message: message,
      ownerAddress: ownerAddress,
      domain: 'gleec.app',
      uri: Uri.parse('https://gleec.app/card'),
      nonce: nonce,
      chainId: 100,
      issuedAt: now,
      expiresAt: expiresAt,
    );
    _outstandingChallenges[nonce] = challenge;
    return challenge;
  }

  Future<String> createSiweMessage({required String ownerAddress}) async =>
      (await createSiweChallenge(ownerAddress: ownerAddress)).message;

  bool _matchesChallenge(
    GnosisSiweChallenge expected,
    GnosisSiweChallenge actual,
  ) => expected == actual && expected.message == actual.message;

  void _validateChallenge(GnosisSiweChallenge challenge) {
    final expected = _outstandingChallenges[challenge.nonce];
    if (expected == null ||
        _usedNonces.contains(challenge.nonce) ||
        !_matchesChallenge(expected, challenge) ||
        challenge.domain != 'gleec.app' ||
        challenge.uri != Uri.parse('https://gleec.app/card') ||
        challenge.chainId != 100 ||
        challenge.isExpired ||
        challenge.issuedAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        )) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidInput,
        message: 'The secure wallet sign-in request is invalid or expired.',
        recovery: GnosisCardRecovery.retry,
      );
    }
  }

  Future<GnosisCardSession> authenticate({
    required GnosisSiweChallenge challenge,
    required String ownerAddress,
    required String signature,
  }) async {
    _requireOnline();
    if (signature.trim().isEmpty) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.unavailable,
        message: 'KDF returned an empty SIWE signature.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    _validateChallenge(challenge);
    final previousApproval = _signatureApprovals[signature];
    if (previousApproval != null && previousApproval != challenge.approvalId) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidInput,
        message: 'The wallet signature was already used for another request.',
        recovery: GnosisCardRecovery.none,
        isRecoverable: false,
      );
    }
    if (ownerAddress.toLowerCase() != challenge.ownerAddress.toLowerCase()) {
      throw _invalidInput('The wallet owner changed during sign-in.');
    }
    _outstandingChallenges.remove(challenge.nonce);
    _usedNonces.add(challenge.nonce);
    _signatureApprovals[signature] = challenge.approvalId;
    final effectiveOwner = challenge.ownerAddress;
    final normalizedOwner = effectiveOwner.toLowerCase();
    if (_stateOwnerAddress != null && _stateOwnerAddress != normalizedOwner) {
      _resetUserState();
    }
    _stateOwnerAddress = normalizedOwner;
    final expiresImmediately =
        scenario == GnosisCardScenario.expiredSession &&
        !_expiredSessionConsumed;
    if (expiresImmediately) {
      _expiredSessionConsumed = true;
    }
    _session = GnosisCardSession(
      ownerAddress: effectiveOwner,
      expiresAt: expiresImmediately
          ? DateTime.now().subtract(const Duration(minutes: 1))
          : DateTime.now().add(const Duration(hours: 24)),
    );
    _isAuthenticated = !expiresImmediately;
    if (_isMigrationScenario && !_isRegistered) {
      _seedMigrationUser(effectiveOwner);
    }
    return _session!;
  }

  Future<GnosisCardSession?> currentSession({
    required String ownerAddress,
  }) async {
    _requireOnline();
    final session = _session;
    if (session == null || !session.isUsableFor(ownerAddress)) return null;
    return session;
  }

  void invalidateSession() {
    _isAuthenticated = false;
    _session = null;
    _outstandingChallenges.clear();
  }

  Future<GnosisSafeMigration> safeMigration() async {
    _requireSession();
    if (!_isMigrationScenario) {
      return const GnosisSafeMigration.none();
    }
    if (scenario == GnosisCardScenario.migrationFailed) {
      return const GnosisSafeMigration(
        migrationId: 'safe-replacement-2026-06',
        status: GnosisSafeMigrationStatus.failed,
        currentSafe: GnosisSafeReference(
          address: _fixturePreviousSafe,
          chainId: 100,
          tokenSymbol: 'EURe',
        ),
        previousSafe: GnosisSafeReference(
          address: _fixturePreviousSafe,
          chainId: 100,
          tokenSymbol: 'EURe',
        ),
      );
    }
    _migrationPolls += 1;
    final status = switch (_migrationPolls) {
      1 => GnosisSafeMigrationStatus.pending,
      2 => GnosisSafeMigrationStatus.inProgress,
      _ => GnosisSafeMigrationStatus.completed,
    };
    if (status == GnosisSafeMigrationStatus.completed) {
      _safeConfiguration = SafeConfiguration(
        ownerAddress: _session!.ownerAddress,
        isDeployed: true,
        integrity: SafeAccountIntegrity.ok,
        safeAddress: _fixtureMigratedSafe,
        delayModule: _fixtureDelay,
        tokenSymbol: 'EURe',
        fiatSymbol: 'EUR',
      );
    }
    return GnosisSafeMigration(
      migrationId: 'safe-replacement-2026-06',
      status: status,
      currentSafe: GnosisSafeReference(
        address: status == GnosisSafeMigrationStatus.completed
            ? _fixtureMigratedSafe
            : _fixturePreviousSafe,
        chainId: 100,
        tokenSymbol: 'EURe',
      ),
      previousSafe: const GnosisSafeReference(
        address: _fixturePreviousSafe,
        chainId: 100,
        tokenSymbol: 'EURe',
      ),
    );
  }
}
