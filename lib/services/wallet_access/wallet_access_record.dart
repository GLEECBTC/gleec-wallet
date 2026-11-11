import 'wallet_access_types.dart';

/// Non-secret journal. The only encrypted payload is a password-change
/// recovery envelope protected by the user's *new* password.
class WalletAccessRecord {
  const WalletAccessRecord({
    required this.entryId,
    required this.walletName,
    required this.isHd,
    required this.protection,
    required this.requiresAuthentication,
    this.phase = 'provisioning',
    this.pubkeyHash,
    this.managed = true,
    this.generated = true,
    this.manager = PasswordManagerOutcome.unavailable,
    this.rotationEnvelope,
  });
  factory WalletAccessRecord.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['entryId'] is! String ||
        json['walletName'] is! String) {
      throw const WalletAccessException(WalletAccessFailure.invalidResponse);
    }
    return WalletAccessRecord(
      entryId: json['entryId'] as String,
      walletName: json['walletName'] as String,
      isHd: json['isHd'] == true,
      protection: CredentialProtection.parse(json['protection']),
      requiresAuthentication: json['requiresAuthentication'] == true,
      phase: json['phase'] as String? ?? 'provisioning',
      pubkeyHash: json['pubkeyHash'] as String?,
      managed: json['managed'] == true,
      generated: json['generated'] == true,
      manager: PasswordManagerOutcome.values.firstWhere(
        (item) => item.name == json['manager'],
        orElse: () => PasswordManagerOutcome.unknown,
      ),
      rotationEnvelope: json['rotationEnvelope'] as String?,
    );
  }

  final String entryId;
  final String walletName;
  final bool isHd;
  final CredentialProtection protection;
  final bool requiresAuthentication;
  final String phase;
  final String? pubkeyHash;
  final bool managed;
  final bool generated;
  final PasswordManagerOutcome manager;
  final String? rotationEnvelope;
  String get credentialKey => 'gleec.wallet.$entryId';

  WalletAccessRecord copyWith({
    String? walletName,
    String? phase,
    String? pubkeyHash,
    CredentialProtection? protection,
    bool? requiresAuthentication,
    bool? managed,
    bool? generated,
    PasswordManagerOutcome? manager,
    String? rotationEnvelope,
    bool clearRotation = false,
  }) => WalletAccessRecord(
    entryId: entryId,
    walletName: walletName ?? this.walletName,
    isHd: isHd,
    protection: protection ?? this.protection,
    requiresAuthentication:
        requiresAuthentication ?? this.requiresAuthentication,
    phase: phase ?? this.phase,
    pubkeyHash: pubkeyHash ?? this.pubkeyHash,
    managed: managed ?? this.managed,
    generated: generated ?? this.generated,
    manager: manager ?? this.manager,
    rotationEnvelope: clearRotation
        ? null
        : rotationEnvelope ?? this.rotationEnvelope,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'entryId': entryId,
    'walletName': walletName,
    'isHd': isHd,
    'protection': protection.name,
    'requiresAuthentication': requiresAuthentication,
    'phase': phase,
    'pubkeyHash': pubkeyHash,
    'managed': managed,
    'generated': generated,
    'manager': manager.name,
    if (rotationEnvelope != null) 'rotationEnvelope': rotationEnvelope,
  };
}
