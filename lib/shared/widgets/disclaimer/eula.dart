import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/shared/widgets/legal_documents/legal_document_view.dart';

class Eula extends StatelessWidget {
  const Eula({super.key, required this.onClose, this.content});
  final VoidCallback onClose;
  final LegalDocumentContent? content;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: MediaQuery.of(context).size.height * 2 / 3,
          child: LegalDocumentView(
            document: LegalDocumentType.eula,
            content: content,
            scrollable: true,
          ),
        ),
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('close-disclaimer'),
          onPressed: onClose,
          width: 300,
          text: LocaleKeys.close.tr(),
        ),
      ],
    );
  }
}
