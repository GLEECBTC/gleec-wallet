import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';

Future<String?> walletRenameDialog(
  BuildContext context, {
  required String initialName,
}) async {
  final TextEditingController controller = TextEditingController(
    text: initialName,
  );
  final walletsRepository = RepositoryProvider.of<WalletsRepository>(context);

  final result = await AppDialog.show<String?>(
    context: context,
    width: isMobile ? null : 360,
    barrierDismissible: false,
    child: _WalletRenameContent(
      controller: controller,
      walletsRepository: walletsRepository,
    ),
  );

  return result;
}

class _WalletRenameContent extends StatefulWidget {
  const _WalletRenameContent({
    required this.controller,
    required this.walletsRepository,
  });

  final TextEditingController controller;
  final WalletsRepository walletsRepository;

  @override
  State<_WalletRenameContent> createState() => _WalletRenameContentState();
}

class _WalletRenameContentState extends State<_WalletRenameContent> {
  String? error;

  @override
  void initState() {
    super.initState();
    // Validate initial name
    error = widget.walletsRepository.validateWalletName(widget.controller.text);
  }

  void _handleTextChange(String? text) {
    setState(() {
      error = widget.walletsRepository.validateWalletName(text ?? '');
    });
  }

  void _handleCancel() {
    Navigator.of(context).pop(null);
  }

  void _handleConfirm() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty && error == null) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: isMobile ? null : const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            LocaleKeys.renameWalletDescription.tr(),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 20),
          UiTextFormField(
            controller: widget.controller,
            autofocus: true,
            autocorrect: false,
            inputFormatters: [LengthLimitingTextInputFormatter(40)],
            errorText: error,
            onChanged: _handleTextChange,
            onFieldSubmitted: (_) => _handleConfirm(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: UiUnderlineTextButton(
                  text: LocaleKeys.cancel.tr(),
                  onPressed: _handleCancel,
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: UiPrimaryButton(
                  text: LocaleKeys.renameWalletConfirm.tr(),
                  onPressed: error != null ? null : _handleConfirm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
