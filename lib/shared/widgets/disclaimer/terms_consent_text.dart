import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/shared/widgets/disclaimer/disclaimer.dart';
import 'package:web_dex/shared/widgets/disclaimer/eula.dart';

/// The implicit-consent line: "By continuing you agree to the EULA, Terms".
///
/// Both documents stay one tap away. Continuing is the acceptance, rather than
/// requiring a separate tick before the primary action becomes usable.
/// Acceptance is recorded by the caller; see `LegalDocumentsRepository`.
///
/// The links are spans rather than `.tr(args:)` placeholders because
/// `easy_localization` returns a plain `String`, which cannot carry a
/// [TapGestureRecognizer].
class TermsConsentText extends StatefulWidget {
  const TermsConsentText({super.key, this.leadingText});

  /// Overrides the default "By continuing..." lead-in.
  final String? leadingText;

  @override
  State<TermsConsentText> createState() => _TermsConsentTextState();
}

class _TermsConsentTextState extends State<TermsConsentText> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextStyle(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.primary,
    );

    return Text.rich(
      key: const Key('terms-consent-text'),
      maxLines: 99,
      textAlign: TextAlign.center,
      TextSpan(
        children: [
          TextSpan(
            text: widget.leadingText ?? LocaleKeys.onboardingConsentPrefix.tr(),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: LocaleKeys.disclaimerAcceptEulaCheckbox.tr(),
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = _showEula,
          ),
          const TextSpan(text: ', '),
          TextSpan(
            text: LocaleKeys.disclaimerAcceptTermsAndConditionsCheckbox.tr(),
            style: linkStyle,
            recognizer: TapGestureRecognizer()..onTap = _showDisclaimer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
    );
  }

  void _showDisclaimer() {
    unawaited(
      AppDialog.showWithCallback<void>(
        context: context,
        useRootNavigator: false,
        width: 640,
        childBuilder: (closeDialog) => Disclaimer(onClose: closeDialog),
      ),
    );
  }

  void _showEula() {
    unawaited(
      AppDialog.showWithCallback<void>(
        context: context,
        useRootNavigator: false,
        width: 640,
        childBuilder: (closeDialog) => Eula(onClose: closeDialog),
      ),
    );
  }
}
