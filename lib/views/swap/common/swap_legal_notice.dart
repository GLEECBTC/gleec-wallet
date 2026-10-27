import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_bloc.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_event.dart';
import 'package:web_dex/bloc/unified_swap/unified_swap_state.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/services/legal_documents/legal_documents_repository.dart';
import 'package:web_dex/shared/swap/swap_services.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_notice.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_view.dart';

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

class SwapLegalConsentNotice extends StatelessWidget {
  const SwapLegalConsentNotice({required this.review, super.key});
  final SwapReview review;
  @override
  Widget build(BuildContext context) {
    final available =
        review.legalSnapshot?.covers(swapConsentDocuments) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          Text(LocaleKeys.swapLegalConsentNotice.tr()),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in [
              (
                LegalDocumentType.eula,
                LocaleKeys.disclaimerAcceptEulaCheckbox.tr(),
              ),
              (
                LegalDocumentType.termsOfService,
                LocaleKeys.disclaimerAcceptTermsAndConditionsCheckbox.tr(),
              ),
            ])
              TextButton(
                onPressed: () => showSwapLegalDocument(
                  context,
                  entry.$1,
                  snapshot: review.legalSnapshot,
                ),
                child: Text(entry.$2),
              ),
          ],
        ),
      ],
    );
  }
}
