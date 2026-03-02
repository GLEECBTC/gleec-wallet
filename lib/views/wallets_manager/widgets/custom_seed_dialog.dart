import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/dispatchers/popup_dispatcher.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

Future<bool> customSeedDialog(BuildContext context) async {
  late PopupDispatcher popupManager;
  bool isOpen = false;
  bool isConfirmed = false;

  void close() {
    popupManager.close();
    isOpen = false;
  }

  popupManager = PopupDispatcher(
    context: context,
    barrierDismissible: false,
    popupContent: StatefulBuilder(
      builder: (context, setState) {
        return Container(
          constraints: isMobile ? null : const BoxConstraints(maxWidth: 360),
          child: Column(
            children: [
              Text(
                LocaleKeys.customSeedWarningText.tr(),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              TextField(
                key: const Key('custom-seed-dialog-input'),
                autofocus: true,
                onChanged: (String text) {
                  setState(() {
                    isConfirmed =
                        text.trim().toLowerCase() ==
                        LocaleKeys.customSeedIUnderstand.tr().toLowerCase();
                  });
                },
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: UiUnderlineTextButton(
                      key: const Key('custom-seed-dialog-cancel-button'),
                      text: LocaleKeys.cancel.tr(),
                      onPressed: () {
                        setState(() => isConfirmed = false);
                        close();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: UiPrimaryButton(
                      key: const Key('custom-seed-dialog-ok-button'),
                      text: LocaleKeys.ok.tr(),
                      onPressed: !isConfirmed ? null : close,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  isOpen = true;
  popupManager.show();

  while (isOpen) {
    await Future<dynamic>.delayed(const Duration(milliseconds: 100));
  }

  return isConfirmed;
}
