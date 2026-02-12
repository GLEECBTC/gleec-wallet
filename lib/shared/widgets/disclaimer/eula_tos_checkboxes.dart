import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';

import 'package:web_dex/shared/widgets/disclaimer/disclaimer.dart';
import 'package:web_dex/shared/widgets/disclaimer/eula.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class EulaTosCheckboxes extends StatefulWidget {
  const EulaTosCheckboxes({
    super.key,
    this.isChecked = false,
    required this.onCheck,
  });

  final bool isChecked;
  final void Function(bool) onCheck;

  @override
  State<EulaTosCheckboxes> createState() => _EulaTosCheckboxesState();
}

class _EulaTosCheckboxesState extends State<EulaTosCheckboxes> {
  bool _checkBox = false;

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.primary,
    );

    return UiCheckbox(
      checkboxKey: const Key('checkbox-eula-tos'),
      value: _checkBox,
      onChanged: (bool? value) {
        setState(() {
          _checkBox = value ?? false;
        });
        _onCheck();
      },
      textWidget: Text.rich(
        maxLines: 99,
        TextSpan(
          children: [
            TextSpan(text: LocaleKeys.disclaimerAcceptDescription.tr()),
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
          ],
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  @override
  void initState() {
    _checkBox = widget.isChecked;
    super.initState();
  }

  void _onCheck() {
    widget.onCheck(_checkBox);
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
        childBuilder: (closeDialog) => Eula(onClose: closeDialog),
      ),
    );
  }
}
