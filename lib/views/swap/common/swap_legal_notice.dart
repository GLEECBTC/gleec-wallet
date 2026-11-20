import 'dart:ui' as ui show TextDirection;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/swap/swap_quote.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/swap/swap_terms_repository.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_notice.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_view.dart';
import 'package:web_dex/views/swap/common/swap_buttons.dart';
import 'package:web_dex/views/swap/common/swap_palette.dart';

Future<void> showSwapLegalDocument(
  BuildContext context,
  LegalDocumentType document, {
  LegalConsentSnapshot? snapshot,
}) => AppDialog.showWithCallback<void>(
  context: context,
  useRootNavigator: false,
  width: 640,
  childBuilder: (close) => _SwapDocumentDialog(
    document: document,
    content: snapshot?.documents[document],
    repository: context.read<SwapServices>().terms.legalDocuments,
    onClose: close,
  ),
);

class _SwapDocumentDialog extends StatelessWidget {
  const _SwapDocumentDialog({
    required this.document,
    required this.content,
    required this.repository,
    required this.onClose,
  });
  final LegalDocumentType document;
  final LegalDocumentContent? content;
  final LegalDocumentsRepository repository;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: MediaQuery.sizeOf(context).height * 2 / 3,
        child: LegalDocumentView(
          document: document,
          content: content,
          repository: repository,
          scrollable: true,
        ),
      ),
      TextButton(onPressed: onClose, child: Text(LocaleKeys.close.tr())),
    ],
  );
}

/// The style of the legal copy under a routed swap: quiet, but body-readable.
TextStyle swapLegalTextStyle(BuildContext context) =>
    SwapText.small(context)
        .copyWith(color: SwapPalette.of(context).textSecondary, height: 1.5);

/// What starting a routed swap accepts, or why that cannot be shown yet.
///
/// With [compact], one line that leaves the documents to the
/// [SwapLegalLinks] elsewhere on the screen; otherwise it ends with them.
class SwapLegalConsentNotice extends StatelessWidget {
  const SwapLegalConsentNotice({
    required this.review,
    this.compact = false,
    super.key,
  });
  final SwapReview review;
  final bool compact;

  /// Whether [review] has something to say here: acceptance to ask for, or
  /// documents that could not be read.
  static bool appliesTo(SwapReview review) =>
      review.quote.source == SwapLiquiditySource.routed &&
      !review.isRecovery &&
      (review.showLegalFailure ||
          (review.termsRequired &&
              (review.legalSnapshot?.covers(swapConsentDocuments) ?? false)));

  @override
  Widget build(BuildContext context) {
    final available =
        review.legalSnapshot?.covers(swapConsentDocuments) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (review.showLegalFailure)
          LegalDocumentNotice(
            status:
                review.legalSnapshot?.status ?? LegalDocumentStatus.unavailable,
            onRetry: review.legalLoading
                ? null
                : () => context.read<UnifiedSwapBloc>().add(
                    const UnifiedSwapLegalRequested(retry: true),
                  ),
          )
        else if (available && review.termsRequired)
          Text(
            compact
                ? 'swapLegalConsentCompact'.tr()
                : LocaleKeys.swapLegalConsentNotice.tr(),
            key: const Key('swap-legal-consent'),
            style: swapLegalTextStyle(context),
          ),
        if (!compact) SwapLegalLinks(snapshot: review.legalSnapshot),
      ],
    );
  }
}

/// The documents a routed swap is made under: the provider's terms and the
/// wallet's own, as links in one style on one edge.
class SwapLegalLinks extends StatelessWidget {
  const SwapLegalLinks({
    this.snapshot,
    this.providerLinkKey = const Key('swap-terms-link'),
    super.key,
  });

  final LegalConsentSnapshot? snapshot;

  /// The provider link's key, distinct where two sets can be on screen.
  final Key providerLinkKey;

  @override
  Widget build(BuildContext context) {
    Widget link(LegalDocumentType document, String label, {Key? key}) =>
        SwapLinkButton(
          key: key,
          label: label,
          onPressed: () =>
              showSwapLegalDocument(context, document, snapshot: snapshot),
        );
    final rtl = Directionality.of(context) == ui.TextDirection.rtl;
    // The buttons pad their labels; shifted back, the labels start on the
    // edge of the text above them.
    return Transform.translate(
      offset: Offset(rtl ? 8 : -8, 0),
      child: Wrap(
        spacing: 4,
        children: [
          link(
            LegalDocumentType.lifiTerms,
            LocaleKeys.swapTermsLinkLabel.tr(
              args: [SwapTermsRepository.provider],
            ),
            key: providerLinkKey,
          ),
          link(
            LegalDocumentType.eula,
            LocaleKeys.disclaimerAcceptEulaCheckbox.tr(),
          ),
          link(
            LegalDocumentType.termsOfService,
            LocaleKeys.disclaimerAcceptTermsAndConditionsCheckbox.tr(),
          ),
        ],
      ),
    );
  }
}
