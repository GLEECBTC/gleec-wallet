import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';

String legalDocumentMessage(LegalDocumentStatus status) => switch (status) {
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
  Widget build(BuildContext context) {
    if (status == LegalDocumentStatus.loading) return const SizedBox.shrink();
    final style = NoticeBanner.styleOf(context, NoticeBannerVariant.warning);
    return NoticeBanner(
      icon: status == LegalDocumentStatus.placeholder
          ? Icons.description_outlined
          : Icons.cloud_off_rounded,
      title: status == LegalDocumentStatus.placeholder
          ? LocaleKeys.legalDocumentsPlaceholderTitle.tr()
          : LocaleKeys.legalDocumentsUnavailableTitle.tr(),
      footer: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('legal-documents-retry'),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(LocaleKeys.retryButtonText.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: style.foreground,
                minimumSize: const Size(0, 48),
                side: BorderSide(
                  color: style.foreground.withValues(alpha: 0.5),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  unawaited(launchUrl(Uri.parse(legalDocumentsBaseUrl))),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: Text(LocaleKeys.legalDocumentsWebsite.tr()),
              style: TextButton.styleFrom(
                foregroundColor: style.foreground,
                minimumSize: const Size(0, 48),
              ),
            ),
          ],
        ),
      ),
      child: Semantics(
        liveRegion: true,
        child: Text(
          legalDocumentMessage(status),
          key: const Key('legal-documents-unavailable'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: style.foreground, height: 1.5),
        ),
      ),
    );
  }
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
