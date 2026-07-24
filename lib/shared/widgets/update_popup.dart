import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/blocs/update_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';

class UpdatePopUp extends StatelessWidget {
  const UpdatePopUp({
    Key? key,
    required this.versionInfo,
    required this.onAccept,
    required this.onCancel,
  }) : super(key: key);
  final UpdateVersionInfo versionInfo;
  final VoidCallback onCancel;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final bool isUpdateRequired = versionInfo.status == UpdateStatus.required;
    final scrollController = ScrollController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(
          '$assetsPath/logo/update_logo.png',
          height: 150,
          filterQuality: FilterQuality.high,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 30.0),
          child: Text(
            LocaleKeys.updatePopupTitle.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 15),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.whatsNew.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                DexScrollbar(
                  scrollController: scrollController,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: SizedBox(
                      width: double.infinity,
                      child: SizedBox(
                        height: 110,
                        width: 320,
                        child: Markdown(
                          styleSheet: MarkdownStyleSheet(
                            listIndent: 10.0,
                            p: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
                          ),
                          data: versionInfo.changelog,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (!isUpdateRequired)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: UiUnderlineTextButton(
                      text: LocaleKeys.remindLater.tr(),
                      onPressed: () {
                        onCancel();
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ),
              Expanded(
                child: UiPrimaryButton(
                  text: LocaleKeys.updateNow.tr(),
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  onPressed: () async {
                    onAccept();
                    await updateBloc.update();
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
