import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/prepared_legacy_migration.dart';
import 'package:web_dex/shared/widgets/app_dialog.dart';
import 'package:web_dex/views/wallets_manager/widgets/creation_password_fields.dart';

class LegacyMigrationCompatibilityResult {
  const LegacyMigrationCompatibilityResult({
    required this.targetWalletName,
    this.kdfPassword,
  });

  final String targetWalletName;
  final String? kdfPassword;
}

Future<LegacyMigrationCompatibilityResult?> legacyMigrationCompatibilityDialog(
  BuildContext context, {
  required WalletsRepository walletsRepository,
  required PreparedLegacyMigration migration,
}) {
  return AppDialog.show<LegacyMigrationCompatibilityResult?>(
    context: context,
    width: isMobile ? null : 420,
    barrierDismissible: false,
    child: LegacyMigrationCompatibilityContent(
      walletsRepository: walletsRepository,
      migration: migration,
    ),
  );
}

class LegacyMigrationCompatibilityContent extends StatefulWidget {
  const LegacyMigrationCompatibilityContent({
    required this.walletsRepository,
    required this.migration,
  });

  final WalletsRepository walletsRepository;
  final PreparedLegacyMigration migration;

  @override
  State<LegacyMigrationCompatibilityContent> createState() =>
      _LegacyMigrationCompatibilityContentState();
}

class _LegacyMigrationCompatibilityContentState
    extends State<LegacyMigrationCompatibilityContent> {
  late final TextEditingController _walletNameController;
  final TextEditingController _kdfPasswordController = TextEditingController();
  String? _walletNameError;
  bool _isPasswordValid = false;

  @override
  void initState() {
    super.initState();
    _walletNameController = TextEditingController(
      text: widget.migration.suggestedTargetWalletName,
    );
    _walletNameError = _validateWalletName(
      widget.migration.suggestedTargetWalletName,
    );
  }

  @override
  void dispose() {
    _walletNameController.dispose();
    _kdfPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: isMobile ? null : const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            LocaleKeys.legacyMigrationTitle.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(_description, style: Theme.of(context).textTheme.bodyMedium),
          if (widget.migration.requiresNameConfirmation) ...[
            const SizedBox(height: 20),
            UiTextFormField(
              key: const Key('legacy-migration-wallet-name-field'),
              controller: _walletNameController,
              autofocus: true,
              autocorrect: false,
              inputFormatters: [LengthLimitingTextInputFormatter(40)],
              errorText: _walletNameError,
              counterText: '',
              onChanged: (value) {
                setState(() {
                  _walletNameError = _validateWalletName(value ?? '');
                });
              },
            ),
          ],
          if (widget.migration.requiresNewKdfPassword) ...[
            const SizedBox(height: 20),
            CreationPasswordFields(
              key: const Key('legacy-migration-password-fields'),
              passwordController: _kdfPasswordController,
              forceStrictValidation: true,
              onValidityChanged: (isValid) {
                setState(() {
                  _isPasswordValid = isValid;
                });
              },
            ),
          ],
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
                  text: LocaleKeys.continueText.tr(),
                  onPressed: _canConfirm ? _handleConfirm : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String get _description {
    final requiresName = widget.migration.requiresNameConfirmation;
    final requiresPassword = widget.migration.requiresNewKdfPassword;
    if (requiresName && requiresPassword) {
      return LocaleKeys.legacyMigrationDescriptionNameAndPassword.tr();
    }
    if (requiresName) {
      return LocaleKeys.legacyMigrationDescriptionNameOnly.tr();
    }
    return LocaleKeys.legacyMigrationDescriptionPasswordOnly.tr();
  }

  bool get _canConfirm {
    final bool nameValid =
        !widget.migration.requiresNameConfirmation || _walletNameError == null;
    final bool passwordValid =
        !widget.migration.requiresNewKdfPassword || _isPasswordValid;
    return nameValid && passwordValid;
  }

  String? _validateWalletName(String value) {
    return widget.walletsRepository.validateLegacyMigrationTargetName(
      name: value,
      sourceWallet: widget.migration.sourceWallet,
    );
  }

  void _handleCancel() {
    Navigator.of(context).pop(null);
  }

  void _handleConfirm() {
    Navigator.of(context).pop(
      LegacyMigrationCompatibilityResult(
        targetWalletName: widget.migration.requiresNameConfirmation
            ? _walletNameController.text.trim()
            : widget.migration.suggestedTargetWalletName,
        kdfPassword: widget.migration.requiresNewKdfPassword
            ? _kdfPasswordController.text
            : null,
      ),
    );
  }
}
