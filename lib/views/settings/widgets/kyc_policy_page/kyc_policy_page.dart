import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_view.dart';

class KycPolicyPage extends StatelessWidget {
  const KycPolicyPage({super.key = const Key('kyc-policy-page')});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 20),
      // On mobile the settings wrapper is the card around this page.
      decoration: isMobile ? null : AppSurface.card(palette),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            LocaleKeys.settingsMenuKycPolicy.tr(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const LegalDocumentView(
            document: LegalDocumentType.kycDueDiligencePolicy,
          ),
        ],
      ),
    );
  }
}
