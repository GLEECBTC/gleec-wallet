part of 'deterministic_gnosis_pay_repository.dart';

mixin _DeterministicGnosisPayIdentity
    on _DeterministicGnosisPayRepositoryState, _DeterministicGnosisPaySupport {
  Future<List<GnosisTerm>> requiredTerms() async {
    _requireSession();
    return List.unmodifiable(_terms);
  }

  Future<void> signUp({required String email}) async {
    _requireSession();
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      throw _invalidInput('Enter a valid email address.');
    }
    _email = normalized;
    _isRegistered = true;
  }

  Future<void> acceptTerms(List<GnosisTermAcceptance> acceptances) async {
    _requireSession();
    if (!_isRegistered) {
      throw _invalidTransition(
        'Create the card account before accepting terms.',
      );
    }
    final accepted = {for (final value in acceptances) value.id: value.version};
    if (_terms.any((term) => accepted[term.id] != term.version)) {
      throw _invalidInput('Accept every current agreement to continue.');
    }
    _terms = [for (final term in _terms) term.copyWith(isAccepted: true)];
  }

  Future<GnosisExternalFlow> kycIntegration() async {
    _requireSession();
    _requireAccount();
    _kycLaunched = true;
    if (_kycStatus == GnosisKycStatus.notStarted ||
        _kycStatus == GnosisKycStatus.documentsRequested) {
      _kycStatus = GnosisKycStatus.pending;
    } else if (_kycStatus == GnosisKycStatus.resubmissionRequested) {
      _kycRecoveryOpened = true;
      _kycStatus = GnosisKycStatus.pending;
    }
    return const GnosisExternalFlow(
      id: 'kyc-mock-flow',
      kind: GnosisExternalFlowKind.kyc,
      url: 'https://mock.gnosispay.com/kyc/gleec-applicant',
    );
  }

  Future<GnosisKycStatus> pollKyc() async {
    _requireSession();
    _requireAccount();
    if (!_kycLaunched) return _kycStatus;
    if (scenario == GnosisCardScenario.kycRejected) {
      return _kycStatus = GnosisKycStatus.rejected;
    }
    if (scenario == GnosisCardScenario.kycRequiresAction) {
      return _kycStatus = GnosisKycStatus.requiresAction;
    }
    if (_isKycResubmissionScenario && !_kycResubmissionShown) {
      _kycResubmissionShown = true;
      return _kycStatus = GnosisKycStatus.resubmissionRequested;
    }
    if (_isKycResubmissionScenario && !_kycRecoveryOpened) {
      return _kycStatus;
    }
    if (_kycStatus == GnosisKycStatus.pending && !_isKycResubmissionScenario) {
      return _kycStatus = GnosisKycStatus.processing;
    }
    return _kycStatus = GnosisKycStatus.approved;
  }

  Future<GnosisExternalFlow> supportFlow() async {
    _requireOnline();
    return const GnosisExternalFlow(
      id: 'support-mock-flow',
      kind: GnosisExternalFlowKind.support,
      url: 'https://mock.gnosispay.com/support',
    );
  }

  Future<List<SourceOfFundsQuestion>> sourceOfFundsQuestions() async {
    _requireSession();
    _requireKycApproved();
    return const [
      SourceOfFundsQuestion(
        id: 'primary-source',
        title: 'What is the primary source of funds for this card?',
        answers: ['Salary', 'Savings', 'Investments', 'Business income'],
      ),
      SourceOfFundsQuestion(
        id: 'expected-use',
        title: 'How do you expect to use the card?',
        answers: [
          'Everyday spending',
          'Travel',
          'Online purchases',
          'Business',
        ],
      ),
    ];
  }

  Future<void> submitSourceOfFunds(List<SourceOfFundsAnswer> answers) async {
    _requireSession();
    final questions = await sourceOfFundsQuestions();
    final byId = {for (final answer in answers) answer.questionId: answer};
    for (final question in questions) {
      final answer = byId[question.id];
      if (answer == null || !question.answers.contains(answer.answer)) {
        throw _invalidInput('Answer every source-of-funds question.');
      }
    }
    _isSourceOfFundsAnswered = true;
  }

  Future<PhoneOtpChallenge> requestPhoneOtp({
    required String phoneNumber,
  }) async {
    _requireSession();
    _requireIdentityPrerequisites();
    final normalized = phoneNumber.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized)) {
      throw _invalidInput('Enter a valid E.164 phone number.');
    }
    _phoneNumber = normalized;
    return _phoneChallenge = _newPhoneChallenge(normalized);
  }

  Future<PhoneOtpChallenge> resendPhoneOtp() async {
    _requireSession();
    final challenge = _phoneChallenge;
    if (challenge == null || _phoneNumber == null) {
      throw _invalidTransition('Request a phone code before resending it.');
    }
    if (!challenge.canResend) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.resendCooldown,
        message: 'Wait for the resend cooldown before requesting another code.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    return _phoneChallenge = _newPhoneChallenge(_phoneNumber!);
  }

  Future<void> verifyPhoneOtp({required String code}) async {
    _requireSession();
    final challenge = _phoneChallenge;
    if (challenge == null) {
      throw _invalidTransition('Request a phone code before verifying it.');
    }
    if (!DateTime.now().isBefore(challenge.expiresAt) ||
        challenge.attemptsRemaining <= 0) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidOtp,
        message: 'This phone verification code expired.',
        recovery: GnosisCardRecovery.editInput,
      );
    }
    if (scenario == GnosisCardScenario.invalidOtp && !_invalidOtpConsumed) {
      _invalidOtpConsumed = true;
      _phoneChallenge = challenge.copyWith(
        attemptsRemaining: challenge.attemptsRemaining - 1,
      );
      throw _invalidOtp();
    }
    if (code != challenge.demoCode) {
      _phoneChallenge = challenge.copyWith(
        attemptsRemaining: challenge.attemptsRemaining - 1,
      );
      throw _invalidOtp();
    }
    _isPhoneValidated = true;
    _phoneChallenge = null;
  }

  Future<void> clearPhoneOtp() async {
    _requireSession();
    _phoneChallenge = null;
    _phoneNumber = null;
    _isPhoneValidated = false;
  }

  Future<SafeDeployment?> safeDeployment({required String ownerAddress}) async {
    _requireSession();
    _validateOwner(ownerAddress);
    return _deployment;
  }

  Future<SafeDeployment> requestSafeDeployment({
    required String ownerAddress,
  }) async {
    _requireSession();
    _requireSafePrerequisites();
    _validateOwner(ownerAddress);
    final current = _deployment;
    // Deployment is provider-owned and idempotent. Once accepted, the
    // provider's status remains authoritative; the client never destroys and
    // recreates the account as a recovery shortcut.
    if (current != null) return current;
    _deploymentPolls = 0;
    return _deployment = SafeDeployment(
      requestId: 'deploy-gleec-0001',
      ownerAddress: ownerAddress,
      status: SafeDeploymentStatus.accepted,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  Future<SafeDeployment> pollSafeDeployment({
    required String ownerAddress,
  }) async {
    _requireSession();
    _validateOwner(ownerAddress);
    final current = _deployment;
    if (current == null) {
      throw _invalidTransition('Start Safe deployment before checking it.');
    }
    if (current.status == SafeDeploymentStatus.failed ||
        current.status == SafeDeploymentStatus.timedOut ||
        current.status == SafeDeploymentStatus.ok) {
      return current;
    }
    _deploymentPolls += 1;
    if (_deploymentPolls == 1) {
      return _deployment = current.copyWith(
        status: SafeDeploymentStatus.processing,
        updatedAt: DateTime.now().toUtc(),
        clearFailureReason: true,
      );
    }
    if (scenario == GnosisCardScenario.slowDeployment && _deploymentPolls < 5) {
      return _deployment = current.copyWith(
        status: SafeDeploymentStatus.processing,
        updatedAt: DateTime.now().toUtc(),
        clearFailureReason: true,
      );
    }
    if (scenario == GnosisCardScenario.deploymentFailure &&
        !_deploymentFailureConsumed) {
      _deploymentFailureConsumed = true;
      return _deployment = current.copyWith(
        status: SafeDeploymentStatus.failed,
        updatedAt: DateTime.now().toUtc(),
        failureReason: 'The API could not complete Safe deployment.',
      );
    }
    return _deployment = current.copyWith(
      status: SafeDeploymentStatus.ok,
      updatedAt: DateTime.now().toUtc(),
      clearFailureReason: true,
    );
  }

  Future<SafeConfiguration> safeConfiguration({
    required String ownerAddress,
  }) async {
    _requireSession();
    _validateOwner(ownerAddress);
    if (_deployment?.status != SafeDeploymentStatus.ok) {
      throw _invalidTransition('The Safe is not deployed yet.');
    }
    final current = _safeConfiguration;
    if (current != null &&
        current.ownerAddress.toLowerCase() == ownerAddress.toLowerCase()) {
      return current;
    }
    final integrity =
        scenario == GnosisCardScenario.safeIntegrityFailure &&
            !_integrityFailureConsumed
        ? SafeAccountIntegrity.safeMisconfigured
        : SafeAccountIntegrity.ok;
    if (integrity == SafeAccountIntegrity.safeMisconfigured) {
      _integrityFailureConsumed = true;
    }
    return _safeConfiguration = SafeConfiguration(
      ownerAddress: ownerAddress,
      isDeployed: true,
      integrity: integrity,
      safeAddress: _activeSafeAddress,
      delayModule: _fixtureDelay,
      tokenSymbol: 'EURe',
      fiatSymbol: 'EUR',
    );
  }

  Future<void> validateSafeIntegrity(SafeConfiguration configuration) async {
    _requireSession();
    if (!configuration.isValid ||
        configuration.safeAddress != _activeSafeAddress ||
        configuration.delayModule != _fixtureDelay ||
        configuration.ownerAddress != _session!.ownerAddress) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.safeIntegrityFailed,
        message: 'The returned Safe configuration failed integrity checks.',
        recovery: GnosisCardRecovery.contactSupport,
      );
    }
  }
}
