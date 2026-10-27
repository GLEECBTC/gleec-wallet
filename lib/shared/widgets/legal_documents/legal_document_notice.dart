import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';

String legalDocumentMessage(LegalDocumentStatus status) => switch (status) {
  LegalDocumentStatus.loading => LocaleKeys.legalDocumentsLoading.tr(),
  LegalDocumentStatus.placeholder => LocaleKeys.legalDocumentsPlaceholder.tr(),
  _ => LocaleKeys.legalDocumentsUnavailable.tr(),
};

/// Informational only: neither this message nor opening its link is consent.
class LegalDocumentNotice extends StatelessWidget {
  const LegalDocumentNotice({
    required this.status,
    required this.onRetry,
    super.key,
  });
  final LegalDocumentStatus status;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        liveRegion: true,
        child: Text(
          legalDocumentMessage(status),
          key: const Key('legal-documents-unavailable'),
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: () =>
                unawaited(launchUrl(Uri.parse(legalDocumentsBaseUrl))),
            child: const Text(legalDocumentsBaseUrl),
          ),
          TextButton(
            key: const Key('legal-documents-retry'),
            onPressed: status == LegalDocumentStatus.loading ? null : onRetry,
            child: Text(LocaleKeys.tryAgain.tr()),
          ),
        ],
      ),
    ],
  );
}

/// The child must also use the same decision for its actual onPressed callback.
class LegalActionTooltip extends StatelessWidget {
  const LegalActionTooltip({
    required this.allowed,
    required this.child,
    super.key,
  });
  final bool allowed;
  final Widget child;

  @override
  Widget build(BuildContext context) => allowed
      ? child
      : Tooltip(
          message: LocaleKeys.legalDocumentsUnavailable.tr(),
          child: child,
        );
}
