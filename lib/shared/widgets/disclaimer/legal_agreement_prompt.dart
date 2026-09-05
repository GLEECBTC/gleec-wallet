import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/disclaimer/disclaimer.dart';
import 'package:web_dex/shared/widgets/disclaimer/eula.dart';

/// Acceptance belongs to the button; opening either document never accepts it.
class LegalAgreementPrompt extends StatelessWidget {
  const LegalAgreementPrompt({required this.onAgree, super.key});

  final VoidCallback onAgree;

  @override
  Widget build(BuildContext context) {
    final action = LocaleKeys.onboardingAgreeAndContinue.tr();
    final notice = LocaleKeys.onboardingAgreementNotice.tr(
      namedArgs: {'action': action},
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(children: spans),
          key: const Key('legal-agreement-notice'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14),
        ),
        const SizedBox(height: 12),
        UiPrimaryButton(
          key: const Key('agree-and-continue-button'),
          height: 56 * MediaQuery.textScalerOf(context).scale(14) / 14,
          text: action,
          onPressed: onAgree,
        ),
      ],
    );
  }

  void _showDocument(BuildContext context, {required bool isEula}) {
    unawaited(
      AppDialog.showWithCallback<void>(
        context: context,
        useRootNavigator: false,
        width: 640,
        childBuilder: (closeDialog) => isEula
            ? Eula(onClose: closeDialog)
            : Disclaimer(onClose: closeDialog),
      ),
    );
  }
}
