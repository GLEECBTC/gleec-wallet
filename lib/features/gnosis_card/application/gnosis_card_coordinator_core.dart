part of 'gnosis_card_coordinator.dart';

abstract class _GnosisCardCoordinatorCore {
  _GnosisCardCoordinatorCore({
    required this.repository,
    required this.signer,
    required this.externalFlowLauncher,
    required this.paymentGateway,
    GnosisWalletReadiness? readiness,
  }) : readiness = readiness ?? _SignerWalletReadiness(signer);

  final GnosisPayRepository repository;
  final SmartAccountSigner signer;

  /// Kept at the composition boundary so callers can use the same injected
  /// launcher for one-shot UI effects. The coordinator only returns flows; it
  /// never opens a browser while handling a BLoC event.
  final ExternalFlowLauncher externalFlowLauncher;
  final CardOrderPaymentGateway paymentGateway;
  final GnosisWalletReadiness readiness;

  GnosisCardSnapshot _snapshot = const GnosisCardSnapshot.initial();
  String? _registeredSafe;
  String? _registeredSafeOwner;
  Future<GnosisCardSnapshot>? _entryFlight;
  Future<GnosisCardSnapshot>? _approvalFlight;
  Future<GnosisCardSnapshot>? _automationFlight;
  var _walletGeneration = 0;
  var _automationGeneration = 0;

  GnosisCardSnapshot get snapshot => _snapshot;

  Future<GnosisCardSnapshot> _refresh({
    GnosisCardSession? session,
    CardOrderPaymentQuote? paymentQuote,
    bool clearPaymentQuote = false,
    bool clearSiweChallenge = false,
  }) async {
    final walletGeneration = _walletGeneration;
    var progress = await _retryTransient(repository.onboardingProgress);
    if (walletGeneration != _walletGeneration) return _snapshot;
    var migration = _snapshot.safeMigration;
    if (progress.isAuthenticated &&
        repository is GnosisSafeMigrationRepository) {
      migration = await _retryTransient(
        (repository as GnosisSafeMigrationRepository).safeMigration,
      );
      if (walletGeneration != _walletGeneration) return _snapshot;
    }
    final configuration = progress.safeConfiguration;
    final configuredSafe = configuration?.safeAddress;
    final effectiveSession = session ?? _snapshot.session;
    final sessionMatchesConfiguration =
        effectiveSession == null ||
        effectiveSession.ownerAddress.toLowerCase() ==
            configuration?.ownerAddress.toLowerCase();
    progress = progress.withSafeRegistration(
      configuredSafe != null &&
          _registeredSafe?.toLowerCase() == configuredSafe.toLowerCase() &&
          _registeredSafeOwner?.toLowerCase() ==
              configuration?.ownerAddress.toLowerCase() &&
          sessionMatchesConfiguration,
    );
    var sourceQuestions = _snapshot.sourceOfFundsQuestions;
    var products = _snapshot.cardProducts;
    var dashboard = _snapshot.dashboard;

    if (progress.nextStage == GnosisOnboardingStage.sourceOfFunds &&
        sourceQuestions.isEmpty) {
      sourceQuestions = await _retryTransient(
        repository.sourceOfFundsQuestions,
      );
      if (walletGeneration != _walletGeneration) return _snapshot;
    }
    if (progress.isSafeReady && products.isEmpty) {
      products = await _retryTransient(repository.cardProducts);
      if (walletGeneration != _walletGeneration) return _snapshot;
    }
    if (progress.cards.isNotEmpty) {
      dashboard = await _retryTransient(repository.dashboard);
      if (walletGeneration != _walletGeneration) return _snapshot;
    }

    if (walletGeneration != _walletGeneration) return _snapshot;
    _snapshot = _snapshot.copyWith(
      progress: progress,
      session: session,
      safeMigration: migration,
      sourceOfFundsQuestions: sourceQuestions,
      cardProducts: products,
      paymentQuote: paymentQuote,
      dashboard: dashboard,
      clearPaymentQuote: clearPaymentQuote,
      clearSiweChallenge: clearSiweChallenge,
      clearDashboard: progress.cards.isEmpty,
    );
    return _snapshot;
  }

  Future<SmartAccountOwner> _validateAndRegister(
    SafeConfiguration configuration,
  ) async {
    final walletGeneration = _walletGeneration;
    await repository.validateSafeIntegrity(configuration);
    final safeAddress = configuration.safeAddress;
    if (safeAddress == null) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.safeIntegrityFailed,
        message: 'The verified Safe address is missing.',
        recovery: GnosisCardRecovery.contactSupport,
      );
    }
    final owner = await signer.owner();
    if (owner.address.toLowerCase() !=
        configuration.ownerAddress.toLowerCase()) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The active KDF owner changed. Sign in again to continue.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    if (walletGeneration != _walletGeneration) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The active wallet changed before card account registration.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    await signer.registerSafe(safeAddress, expectedOwner: owner);
    final currentOwner = await signer.owner();
    if (currentOwner.address.toLowerCase() != owner.address.toLowerCase()) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The active wallet changed during card account registration.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    if (walletGeneration != _walletGeneration) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.sessionExpired,
        message: 'The active wallet changed during card account registration.',
        recovery: GnosisCardRecovery.reauthenticate,
      );
    }
    _registeredSafe = safeAddress;
    _registeredSafeOwner = owner.address;
    return owner;
  }

  Future<void> _restoreVerifiedSafe() async {
    if (_snapshot.safeMigration.isActive ||
        _snapshot.safeMigration.status == GnosisSafeMigrationStatus.failed) {
      return;
    }
    if (_snapshot.safeMigration.status == GnosisSafeMigrationStatus.completed &&
        !_migrationConfigurationIsAuthoritative) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.serviceUnavailable,
        message: 'The updated card account is still synchronizing.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    final configuration = _snapshot.progress.safeConfiguration;
    if (configuration?.isValid ?? false) {
      await _validateAndRegister(configuration!);
      await _refresh();
    }
  }

  void _validateSiweChallenge(
    GnosisSiweChallenge challenge,
    SmartAccountOwner owner,
  ) {
    final now = DateTime.now().toUtc();
    final parsed = RegExp(
      r'^([^\n]+) wants you to sign in with your Ethereum account:\n'
      r'(0x[a-fA-F0-9]{40})\n\n'
      r'(?:([^\n]+)\n\n)?'
      r'URI: ([^\n]+)\n'
      r'Version: ([^\n]+)\n'
      r'Chain ID: ([^\n]+)\n'
      r'Nonce: ([^\n]+)\n'
      r'Issued At: ([^\n]+)\n'
      r'Expiration Time: ([^\n]+)$',
    ).firstMatch(challenge.message);
    final valid =
        parsed != null &&
        parsed.group(0) == challenge.message &&
        challenge.ownerAddress.toLowerCase() == owner.address.toLowerCase() &&
        challenge.domain == 'gleec.app' &&
        challenge.uri == Uri.parse('https://gleec.app/card') &&
        challenge.chainId == 100 &&
        RegExp(r'^[a-zA-Z0-9]{8,}$').hasMatch(challenge.nonce) &&
        !challenge.isExpired &&
        !challenge.issuedAt.isAfter(now.add(const Duration(minutes: 1))) &&
        parsed.group(1) == challenge.domain &&
        parsed.group(2)?.toLowerCase() ==
            challenge.ownerAddress.toLowerCase() &&
        parsed.group(3) ==
            'Sign in to your Gleec card account. No transaction is sent.' &&
        parsed.group(4) == challenge.uri.toString() &&
        parsed.group(5) == '1' &&
        parsed.group(6) == challenge.chainId.toString() &&
        parsed.group(7) == challenge.nonce &&
        parsed.group(8) == challenge.issuedAt.toIso8601String() &&
        parsed.group(9) == challenge.expiresAt.toIso8601String();
    if (!valid) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidInput,
        message: 'The secure wallet sign-in request could not be verified.',
        recovery: GnosisCardRecovery.none,
        isRecoverable: false,
      );
    }
  }

  Future<String> _ownerAddress() async {
    final session = _snapshot.session;
    if (session != null) {
      if (!session.isUsableFor(session.ownerAddress)) {
        throw const GnosisCardFailure(
          code: GnosisCardFailureCode.sessionExpired,
          message: 'The card session expired. Sign in again to continue.',
          recovery: GnosisCardRecovery.reauthenticate,
        );
      }
      return session.ownerAddress;
    }
    return (await signer.owner()).address;
  }

  GnosisCardProduct _requireSelectedProduct(GnosisCardKind kind) {
    final product = _snapshot.progress.selectedProduct;
    if (product == null || product.kind != kind) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'Select the matching card product before continuing.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    return product;
  }

  PhysicalCardOrder _requirePhysicalOrder() {
    final order = _snapshot.progress.physicalOrder;
    if (order == null) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'There is no physical-card order to update.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    return order;
  }

  void _requireNoActiveMigration() {
    final status = _snapshot.safeMigration.status;
    if (status == GnosisSafeMigrationStatus.failed) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.migrationFailed,
        message: 'Your card account update needs support.',
        recovery: GnosisCardRecovery.contactSupport,
      );
    }
    if (_snapshot.safeMigration.isActive) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'Your card account is still updating. Try again later.',
        recovery: GnosisCardRecovery.retry,
      );
    }
    if (status == GnosisSafeMigrationStatus.completed &&
        !_migrationConfigurationIsAuthoritative) {
      throw const GnosisCardFailure(
        code: GnosisCardFailureCode.invalidTransition,
        message: 'Your updated card account is still synchronizing.',
        recovery: GnosisCardRecovery.retry,
      );
    }
  }

  bool get _migrationConfigurationIsAuthoritative {
    final migration = _snapshot.safeMigration;
    if (migration.status != GnosisSafeMigrationStatus.completed) return true;
    final currentSafe = migration.currentSafe;
    final configuration = _snapshot.progress.safeConfiguration;
    return currentSafe != null &&
        currentSafe.chainId == 100 &&
        configuration != null &&
        configuration.isValid &&
        configuration.safeAddress?.toLowerCase() ==
            currentSafe.address.toLowerCase() &&
        configuration.tokenSymbol == currentSafe.tokenSymbol;
  }

  Future<GnosisCardSnapshot> _updateDashboard(
    Future<GnosisCardDashboard> Function() operation, {
    bool Function(GnosisCardDashboard dashboard)? isReconciled,
  }) async {
    final walletGeneration = _walletGeneration;
    try {
      final dashboard = await operation();
      if (walletGeneration != _walletGeneration) return _snapshot;
      return _snapshot = _snapshot.copyWith(dashboard: dashboard);
    } catch (_) {
      if (isReconciled != null) {
        try {
          final dashboard = await repository.dashboard();
          if (walletGeneration != _walletGeneration) return _snapshot;
          if (isReconciled(dashboard)) {
            return _snapshot = _snapshot.copyWith(dashboard: dashboard);
          }
        } catch (_) {
          // Preserve the original mutation or connectivity failure.
        }
      }
      rethrow;
    }
  }

  Future<T> _retryTransient<T>(Future<T> Function() operation) async {
    const maxAttempts = 3;
    for (var attempt = 1; ; attempt += 1) {
      try {
        return await operation();
      } on GnosisCardFailure catch (failure) {
        final transient = const {
          GnosisCardFailureCode.rateLimited,
          GnosisCardFailureCode.serviceUnavailable,
        }.contains(failure.code);
        if (!transient || attempt >= maxAttempts) rethrow;
        final baseMilliseconds = 200 * (1 << (attempt - 1));
        final jitter = Random(attempt + _walletGeneration).nextInt(100);
        await Future<void>.delayed(
          Duration(milliseconds: baseMilliseconds + jitter),
        );
      }
    }
  }
}

class _SignerWalletReadiness implements GnosisWalletReadiness {
  const _SignerWalletReadiness(this._signer);

  final SmartAccountSigner _signer;

  @override
  void invalidate() {
    if (_signer case final GnosisWalletReadiness readiness) {
      readiness.invalidate();
    }
  }

  @override
  Future<SmartAccountOwner> ensureReady() => _signer.owner();
}
