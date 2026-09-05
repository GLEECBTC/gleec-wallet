import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/disclaimer/disclaimer.dart';
import 'package:web_dex/shared/widgets/disclaimer/eula.dart';

/// The form's normal submission is acceptance; links only open documents.
class TermsConsentText extends StatelessWidget {
  const TermsConsentText({required this.actionLabel, super.key});

  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<LegalAgreementBloc, LegalAgreementStatus>(
      builder: (context, status) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == LegalAgreementStatus.updated) ...[
            Text(
              LocaleKeys.onboardingAgreementsUpdated.tr(),
              key: const Key('legal-agreements-updated'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
          ],
          _AgreementNotice(actionLabel: actionLabel),
        ],
      ),
    );
  }
}

class _AgreementNotice extends StatelessWidget {
  const _AgreementNotice({required this.actionLabel});

  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final notice = LocaleKeys.onboardingAgreementNotice.tr(
      namedArgs: {'action': actionLabel},
    );
    final spans = <InlineSpan>[];

    // Keep the whole sentence translatable, including the order of its links.
    notice.splitMapJoin(
      RegExp(r'\{(eula|terms)\}'),
      onMatch: (match) {
        final isEula = match.group(1) == 'eula';
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            // WidgetSpan already scales its entire child with the paragraph.
            // Avoid applying the user's text scale a second time inside it.
            child: MediaQuery.withNoTextScaling(
              child: MergeSemantics(
                key: Key(
                  isEula ? 'agreement-eula-link' : 'agreement-terms-link',
                ),
                child: Semantics(
                  link: true,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      textStyle: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                          ),
                    ),
                    onPressed: () => _showDocument(context, isEula: isEula),
                    child: Text(
                      isEula
                          ? LocaleKeys.disclaimerAcceptEulaCheckbox.tr()
                          : LocaleKeys
                                .disclaimerAcceptTermsAndConditionsCheckbox
                                .tr(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return '';
      },
      onNonMatch: (text) {
        spans.add(TextSpan(text: text));
        return '';
      },
    );

    return Text.rich(
      TextSpan(children: spans),
      key: const Key('legal-agreement-notice'),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
    );
  }

  Future<void> _showDocument(
    BuildContext context, {
    required bool isEula,
  }) async {
    await AppDialog.showWithCallback<void>(
      context: context,
      useRootNavigator: false,
      width: 640,
      childBuilder: (closeDialog) => isEula
          ? Eula(onClose: closeDialog)
          : Disclaimer(onClose: closeDialog),
    );
    // A document may have refreshed while it was open.
    if (context.mounted) {
      context.read<LegalAgreementBloc>().add(const LegalAgreementOpened());
    }
  }
}
