/// A record that the user accepted the legal documents.
///
/// Consent used to be a per-form checkbox held in memory and written nowhere,
/// so the app could not answer "did this user agree, and to which version".
/// With acceptance now implicit in continuing, having the record matters more,
/// not less.
///
/// [documentShas] pins *which* text was accepted. The documents refresh from
/// GitHub and their SHAs are already cached, so a genuine change to the EULA or
/// Terms invalidates the record on its own, without anyone remembering to bump
/// a version. [termsVersion] is the manual override for the cases a SHA cannot
/// see - a policy change that does not touch those two files.
class LegalAcceptance {
  const LegalAcceptance({
    required this.termsVersion,
    required this.acceptedAt,
    required this.surface,
    required this.documentShas,
  });

  /// Tolerant by design: a record that cannot be parsed must read as "version
  /// 0, nothing accepted" so the user is re-prompted, never as a throw that
  /// takes the setup screen down with it.
  factory LegalAcceptance.fromJson(Map<String, dynamic> json) {
    final rawVersion = json['terms_version'];
    final rawAcceptedAt = json['accepted_at'];
    final rawSurface = json['surface'];
    final rawShas = json['document_shas'];

    return LegalAcceptance(
      termsVersion: switch (rawVersion) {
        final num n => n.toInt(),
        final String s => int.tryParse(s) ?? 0,
        _ => 0,
      },
      acceptedAt:
          (rawAcceptedAt is String ? DateTime.tryParse(rawAcceptedAt) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      surface: rawSurface is String ? rawSurface : 'unknown',
      documentShas: rawShas is Map
          ? rawShas.map((k, v) => MapEntry('$k', '$v'))
          : const <String, String>{},
    );
  }

  /// Bumped manually to force re-acceptance.
  final int termsVersion;

  final DateTime acceptedAt;

  /// Where consent was given ('onboarding', 'wallet-creation', ...). Useful
  /// when reconstructing what the user was actually shown.
  final String surface;

  /// Document cache key to the content SHA that was live at acceptance time.
  final Map<String, String> documentShas;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'terms_version': termsVersion,
    'accepted_at': acceptedAt.toIso8601String(),
    'surface': surface,
    'document_shas': documentShas,
  };
}
