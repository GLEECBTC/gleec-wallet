import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

const legalDocumentsBaseUrl = 'https://privacy.gleec.com/';
const legalPlaceholderMarker = '<!-- gleec-legal-status: placeholder -->';
const walletConsentDocuments = [
  LegalDocumentType.eula,
  LegalDocumentType.termsOfService,
];
const swapConsentDocuments = [
  ...walletConsentDocuments,
  LegalDocumentType.lifiTerms,
];

enum LegalDocumentType {
  eula,
  termsOfService,
  privacyNotice,
  kycDueDiligencePolicy,
  lifiTerms;

  String get title => switch (this) {
    eula => 'End User License Agreement (EULA)',
    termsOfService => 'Terms of Service',
    privacyNotice => 'Privacy Notice',
    kycDueDiligencePolicy => 'KYC and Due Diligence Policy',
    lifiTerms => 'LI.FI swap legal documentation',
  };

  String get filename => switch (this) {
    eula => 'eula_gleec_wallet.md',
    termsOfService => 'tos_gleec_wallet.md',
    privacyNotice => 'privacy_notice_gleec_wallet.md',
    kycDueDiligencePolicy => 'kyc_due_diligence_policy_gleec_wallet.md',
    lifiTerms => 'tos_lifi_gleec_wallet.md',
  };

  String get url => '$legalDocumentsBaseUrl$filename';

  String get cacheKey => switch (this) {
    eula => 'legal_document_eula',
    termsOfService => 'legal_document_terms_of_service',
    privacyNotice => 'legal_document_privacy_notice',
    kycDueDiligencePolicy => 'legal_document_kyc_due_diligence_policy',
    lifiTerms => 'legal_document_lifi_terms',
  };

  /// Identity of the assets shipped before remote-only hosting. Legacy
  /// acceptance records used the literal "bundled" instead of a content hash.
  String? get legacyBundledSha => switch (this) {
    eula => 'a34507cab4663f718cd126ff32d2c045c7bad755',
    termsOfService => '8922a38ea6f88795ba4f4fa747db92f6ca8c2206',
    _ => null,
  };
}

enum LegalDocumentSource { cachedRemote, remote, none }

enum LegalDocumentStatus { loading, available, unavailable, placeholder }

/// Git blob hashes retain compatibility with previously accepted GitHub text.
String legalContentSha(String markdown) {
  final bytes = utf8.encode(markdown);
  return sha1.convert([
    ...utf8.encode('blob ${bytes.length}\u0000'),
    ...bytes,
  ]).toString();
}

bool isLegalMarkdown(String text) {
  final trimmed = text.replaceFirst('\uFEFF', '').trim();
  if (trimmed.isEmpty ||
      RegExp(
        r'<(?:!doctype\s+html|html|head|body)(?:\s|>)',
        caseSensitive: false,
      ).hasMatch(trimmed) ||
      trimmed.startsWith('<?xml')) {
    return false;
  }
  // A Markdown document can start with a link; reject actual JSON, not '['.
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    try {
      jsonDecode(trimmed);
      return false;
    } on FormatException {
      // Not JSON; continue with Markdown.
    }
  }
  return true;
}

class LegalDocumentContent extends Equatable {
  const LegalDocumentContent({
    required this.markdown,
    required this.source,
    this.status = LegalDocumentStatus.available,
    this.sha,
    this.fetchedAt,
    this.etag,
  });

  const LegalDocumentContent.unavailable({
    this.status = LegalDocumentStatus.unavailable,
  }) : markdown = '',
       source = LegalDocumentSource.none,
       sha = null,
       fetchedAt = null,
       etag = null;

  final String markdown;
  final LegalDocumentSource source;
  final LegalDocumentStatus status;
  final String? sha;
  final DateTime? fetchedAt;
  final String? etag;

  @override
  List<Object?> get props => [markdown, source, status, sha, fetchedAt, etag];

  bool get isAvailable =>
      status == LegalDocumentStatus.available &&
      isLegalMarkdown(markdown) &&
      !markdown.contains(legalPlaceholderMarker);
}

/// The document links and submission use the same immutable content snapshot.
class LegalConsentSnapshot extends Equatable {
  LegalConsentSnapshot({
    required Map<LegalDocumentType, LegalDocumentContent> documents,
    required Map<String, String> documentShas,
    List<LegalDocumentType> requiredDocuments = walletConsentDocuments,
  }) : documents = Map.unmodifiable(documents),
       documentShas = Map.unmodifiable(documentShas),
       requiredDocuments = List.unmodifiable(requiredDocuments);

  factory LegalConsentSnapshot.fromDocuments(
    Map<LegalDocumentType, LegalDocumentContent> documents, {
    List<LegalDocumentType> requiredDocuments = walletConsentDocuments,
  }) => LegalConsentSnapshot(
    documents: documents,
    requiredDocuments: List.unmodifiable(requiredDocuments),
    documentShas: {
      for (final entry in documents.entries)
        if (entry.value.isAvailable)
          entry.key.cacheKey: legalContentSha(entry.value.markdown),
    },
  );

  final Map<LegalDocumentType, LegalDocumentContent> documents;
  final Map<String, String> documentShas;
  final List<LegalDocumentType> requiredDocuments;

  @override
  List<Object?> get props => [documents, documentShas, requiredDocuments];

  bool covers(Iterable<LegalDocumentType> required) => required.every((type) {
    final content = documents[type];
    return content != null &&
        content.isAvailable &&
        documentShas[type.cacheKey] == legalContentSha(content.markdown);
  });

  bool get isAvailable => covers(requiredDocuments);
  LegalDocumentStatus get status => isAvailable
      ? LegalDocumentStatus.available
      : documents.values.any((d) => d.status == LegalDocumentStatus.placeholder)
      ? LegalDocumentStatus.placeholder
      : LegalDocumentStatus.unavailable;
}
