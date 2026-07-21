part of 'gnosis_card_models.dart';

class GnosisSafeReference extends Equatable {
  const GnosisSafeReference({
    required this.address,
    required this.chainId,
    required this.tokenSymbol,
  });

  final String address;
  final int chainId;
  final String tokenSymbol;

  @override
  List<Object?> get props => [address, chainId, tokenSymbol];
}

/// API-shaped Safe replacement state. A null [status] means no migration is
/// active for the authenticated user.
class GnosisSafeMigration extends Equatable {
  const GnosisSafeMigration({
    required this.migrationId,
    required this.status,
    this.currentSafe,
    this.previousSafe,
  });

  const GnosisSafeMigration.none()
    : migrationId = null,
      status = null,
      currentSafe = null,
      previousSafe = null;

  final String? migrationId;
  final GnosisSafeMigrationStatus? status;
  final GnosisSafeReference? currentSafe;
  final GnosisSafeReference? previousSafe;

  bool get isActive =>
      status == GnosisSafeMigrationStatus.pending ||
      status == GnosisSafeMigrationStatus.inProgress;

  bool get hasAddressChanged =>
      previousSafe != null &&
      currentSafe != null &&
      previousSafe!.address.toLowerCase() != currentSafe!.address.toLowerCase();

  @override
  List<Object?> get props => [migrationId, status, currentSafe, previousSafe];
}

class GnosisTerm extends Equatable {
  const GnosisTerm({
    required this.id,
    required this.title,
    required this.version,
    required this.documentUrl,
    required this.isAccepted,
  });

  final String id;
  final String title;
  final String version;
  final String documentUrl;
  final bool isAccepted;

  GnosisTerm copyWith({bool? isAccepted}) => GnosisTerm(
    id: id,
    title: title,
    version: version,
    documentUrl: documentUrl,
    isAccepted: isAccepted ?? this.isAccepted,
  );

  @override
  List<Object?> get props => [id, title, version, documentUrl, isAccepted];
}

class GnosisTermAcceptance extends Equatable {
  const GnosisTermAcceptance({required this.id, required this.version});

  final String id;
  final String version;

  @override
  List<Object?> get props => [id, version];
}

class GnosisExternalFlow extends Equatable {
  const GnosisExternalFlow({
    required this.id,
    required this.kind,
    required this.url,
  });

  final String id;
  final GnosisExternalFlowKind kind;
  final String url;

  @override
  List<Object?> get props => [id, kind, url];
}

class SourceOfFundsQuestion extends Equatable {
  const SourceOfFundsQuestion({
    required this.id,
    required this.title,
    required this.answers,
  });

  final String id;
  final String title;
  final List<String> answers;

  @override
  List<Object?> get props => [id, title, answers];
}

class SourceOfFundsAnswer extends Equatable {
  const SourceOfFundsAnswer({
    required this.questionId,
    required this.question,
    required this.answer,
  });

  final String questionId;
  final String question;
  final String answer;

  @override
  List<Object?> get props => [questionId, question, answer];
}

class PhoneOtpChallenge extends Equatable {
  const PhoneOtpChallenge({
    required this.id,
    required this.phoneNumber,
    required this.expiresAt,
    required this.resendAvailableAt,
    required this.attemptsRemaining,
    this.demoCode,
  });

  final String id;
  final String phoneNumber;
  final DateTime expiresAt;
  final DateTime resendAvailableAt;
  final int attemptsRemaining;

  /// Populated only by the explicit deterministic mock adapter.
  final String? demoCode;

  bool get canResend => !DateTime.now().isBefore(resendAvailableAt);

  PhoneOtpChallenge copyWith({
    DateTime? expiresAt,
    DateTime? resendAvailableAt,
    int? attemptsRemaining,
  }) => PhoneOtpChallenge(
    id: id,
    phoneNumber: phoneNumber,
    expiresAt: expiresAt ?? this.expiresAt,
    resendAvailableAt: resendAvailableAt ?? this.resendAvailableAt,
    attemptsRemaining: attemptsRemaining ?? this.attemptsRemaining,
    demoCode: demoCode,
  );

  @override
  List<Object?> get props => [
    id,
    phoneNumber,
    expiresAt,
    resendAvailableAt,
    attemptsRemaining,
    demoCode,
  ];
}

class SafeDeployment extends Equatable {
  const SafeDeployment({
    required this.requestId,
    required this.ownerAddress,
    required this.status,
    required this.updatedAt,
    this.failureReason,
  });

  final String requestId;
  final String ownerAddress;
  final SafeDeploymentStatus status;
  final DateTime updatedAt;
  final String? failureReason;

  SafeDeployment copyWith({
    SafeDeploymentStatus? status,
    DateTime? updatedAt,
    String? failureReason,
    bool clearFailureReason = false,
  }) => SafeDeployment(
    requestId: requestId,
    ownerAddress: ownerAddress,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
    failureReason: clearFailureReason
        ? null
        : failureReason ?? this.failureReason,
  );

  @override
  List<Object?> get props => [
    requestId,
    ownerAddress,
    status,
    updatedAt,
    failureReason,
  ];
}

class SafeConfiguration extends Equatable {
  const SafeConfiguration({
    required this.ownerAddress,
    required this.isDeployed,
    required this.integrity,
    required this.safeAddress,
    required this.delayModule,
    required this.tokenSymbol,
    required this.fiatSymbol,
  });

  final String ownerAddress;
  final bool isDeployed;
  final SafeAccountIntegrity integrity;
  final String? safeAddress;
  final String? delayModule;
  final String? tokenSymbol;
  final String? fiatSymbol;

  bool get isValid =>
      isDeployed &&
      integrity.isValid &&
      safeAddress != null &&
      delayModule != null;

  @override
  List<Object?> get props => [
    ownerAddress,
    isDeployed,
    integrity,
    safeAddress,
    delayModule,
    tokenSymbol,
    fiatSymbol,
  ];
}
