enum LegalDocumentType {
  eula,
  termsOfService,
  privacyNotice,
  kycDueDiligencePolicy;

  String get title {
    switch (this) {
      case LegalDocumentType.eula:
        return 'End User License Agreement (EULA)';
      case LegalDocumentType.termsOfService:
        return 'Terms of Service';
      case LegalDocumentType.privacyNotice:
        return 'Privacy Notice';
      case LegalDocumentType.kycDueDiligencePolicy:
        return 'KYC and Due Diligence Policy';
    }
  }

  String get assetPath {
    switch (this) {
      case LegalDocumentType.eula:
        return 'assets/legal/eula.md';
      case LegalDocumentType.termsOfService:
        return 'assets/legal/terms-of-service.md';
      case LegalDocumentType.privacyNotice:
        return 'assets/legal/privacy-notice.md';
      case LegalDocumentType.kycDueDiligencePolicy:
        return 'assets/legal/kyc-due-diligence-policy.md';
    }
  }

  String get githubPath {
    switch (this) {
      case LegalDocumentType.eula:
        return 'assets/legal/eula.md';
      case LegalDocumentType.termsOfService:
        return 'assets/legal/terms-of-service.md';
      case LegalDocumentType.privacyNotice:
        return 'assets/legal/privacy-notice.md';
      case LegalDocumentType.kycDueDiligencePolicy:
        return 'assets/legal/kyc-due-diligence-policy.md';
    }
  }

  String get cacheKey {
    switch (this) {
      case LegalDocumentType.eula:
        return 'legal_document_eula';
      case LegalDocumentType.termsOfService:
        return 'legal_document_terms_of_service';
      case LegalDocumentType.privacyNotice:
        return 'legal_document_privacy_notice';
      case LegalDocumentType.kycDueDiligencePolicy:
        return 'legal_document_kyc_due_diligence_policy';
    }
  }
}

enum LegalDocumentSource { bundledAsset, cachedRemote, remote }

class LegalDocumentContent {
  const LegalDocumentContent({
    required this.markdown,
    required this.source,
    this.sha,
    this.fetchedAt,
  });

  final String markdown;
  final LegalDocumentSource source;
  final String? sha;
  final DateTime? fetchedAt;
}

/// The exact documents named by one form's consent notice.
///
/// Both the document links and acceptance use this immutable snapshot so a
/// background refresh cannot change the meaning of an already submitted form.
class LegalConsentSnapshot {
  LegalConsentSnapshot({
    required Map<LegalDocumentType, LegalDocumentContent> documents,
    required Map<String, String> documentShas,
  }) : documents = Map.unmodifiable(documents),
       documentShas = Map.unmodifiable(documentShas);

  final Map<LegalDocumentType, LegalDocumentContent> documents;
  final Map<String, String> documentShas;
}
