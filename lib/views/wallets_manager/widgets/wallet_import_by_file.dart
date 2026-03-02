import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/shared/ui/ui_gradient_icon.dart';
import 'package:web_dex/shared/utils/encryption_tool.dart';
import 'package:web_dex/shared/widgets/disclaimer/eula_tos_checkboxes.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/shared/widgets/quick_login_switch.dart';
import 'package:web_dex/views/wallets_manager/widgets/custom_seed_checkbox.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_import_type_dropdown.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_rename_dialog.dart';

class WalletFileData {
  const WalletFileData({required this.content, required this.name});
  final String content;
  final String name;
}

class WalletImportByFile extends StatefulWidget {
  const WalletImportByFile({
    super.key,
    required this.fileData,
    required this.onImport,
    required this.onCancel,
  });
  final WalletFileData fileData;

  final void Function({
    required String name,
    required String password,
    required WalletConfig walletConfig,
    required bool rememberMe,
  })
  onImport;
  final void Function() onCancel;

  @override
  State<WalletImportByFile> createState() => _WalletImportByFileState();
}

class _WalletImportByFileState extends State<WalletImportByFile> {
  final TextEditingController _filePasswordController = TextEditingController(
    text: '',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isObscured = true;
  bool _isHdMode = true;
  bool _isHdOptionEnabled = true;
  bool _eulaAndTosChecked = false;
  bool _rememberMe = false;
  bool _allowCustomSeed = false;
  bool _showCustomSeedToggle = false;

  String? _filePasswordError;
  String? _commonError;

  bool get _isValidData {
    return _filePasswordError == null;
  }

  // Intentionally do not check wallet name here, because it is done on button
  // click and a dialog is shown to rename the wallet if there are issues.
  bool get _isButtonEnabled => _eulaAndTosChecked;

  @override
  Widget build(BuildContext context) {
    return ScreenshotSensitive(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            LocaleKeys.walletImportByFileTitle.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleLarge!.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 20),
          Text(
            LocaleKeys.walletImportByFileDescription.tr(),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  UiTextFormField(
                    key: const Key('file-password-field'),
                    controller: _filePasswordController,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableInteractiveSelection: true,
                    obscureText: _isObscured,
                    maxLength: passwordMaxLength,
                    counterText: '',
                    autofillHints: const [AutofillHints.password],
                    validator: (_) {
                      return _filePasswordError;
                    },
                    errorMaxLines: 6,
                    hintText: LocaleKeys.walletCreationPasswordHint.tr(),
                    suffixIcon: PasswordVisibilityControl(
                      onVisibilityChange: (bool isPasswordObscured) {
                        setState(() {
                          _isObscured = isPasswordObscured;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      const UiGradientIcon(icon: Icons.folder, size: 32),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.fileData.name,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (_commonError != null)
                    Align(
                      alignment: const Alignment(-1, 0),
                      child: SelectableText(
                        _commonError ?? '',
                        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 30),
                  WalletImportTypeDropdown(
                    selectedType: _isHdMode
                        ? WalletType.hdwallet
                        : WalletType.iguana,
                    isHdOptionEnabled: _isHdOptionEnabled,
                    onChanged: (walletType) {
                      setState(() {
                        _isHdMode = walletType == WalletType.hdwallet;
                        _commonError = null;
                        _allowCustomSeed = false;
                        _showCustomSeedToggle = false;
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  if (_shouldShowCustomSeedToggle)
                    CustomSeedCheckbox(
                      value: _allowCustomSeed,
                      onChanged: (value) {
                        setState(() {
                          _allowCustomSeed = value;
                        });
                      },
                    ),
                  const SizedBox(height: 15),
                  EulaTosCheckboxes(
                    key: const Key('import-wallet-eula-checks'),
                    isChecked: _eulaAndTosChecked,
                    onCheck: (isChecked) {
                      setState(() {
                        _eulaAndTosChecked = isChecked;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  QuickLoginSwitch(
                    value: _rememberMe,
                    onChanged: (value) {
                      setState(() => _rememberMe = value);
                    },
                  ),
                  const SizedBox(height: 30),
                  UiPrimaryButton(
                    key: const Key('confirm-password-button'),
                    height: 50,
                    text: LocaleKeys.import.tr(),
                    onPressed: _isButtonEnabled ? _onImport : null,
                  ),
                  const SizedBox(height: 20),
                  UiUnderlineTextButton(
                    onPressed: widget.onCancel,
                    text: LocaleKeys.back.tr(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _filePasswordController.dispose();

    super.dispose();
  }

  // TODO? Investigate if using this instead of a getter may have limitations
  // or issues with multi-instance support
  late final KomodoDefiSdk _sdk = context.read<KomodoDefiSdk>();

  Future<void> _onImport() async {
    // Clear any previous common error before starting a new import attempt
    if (_commonError != null) {
      setState(() {
        _commonError = null;
      });
    }
    final EncryptionTool encryptionTool = EncryptionTool();
    final String? fileData = await encryptionTool.decryptData(
      _filePasswordController.text,
      widget.fileData.content,
    );
    if (fileData == null) {
      setState(() {
        _filePasswordError = LocaleKeys.incorrectPassword.tr();
      });
      _formKey.currentState?.validate();
      return;
    } else {
      setState(() {
        _filePasswordError = null;
      });
    }
    _formKey.currentState?.validate();
    try {
      final WalletConfig walletConfig = WalletConfig.fromJson(
        json.decode(fileData),
      );
      walletConfig.type = _isHdMode ? WalletType.hdwallet : WalletType.iguana;

      final String? decryptedSeed = await encryptionTool.decryptData(
        _filePasswordController.text,
        walletConfig.seedPhrase,
      );
      if (decryptedSeed == null) return;
      if (!_isValidData) return;

      final bool isBip39 = _sdk.mnemonicValidator.validateBip39(decryptedSeed);
      if (!isBip39) {
        if (_isHdMode) {
          setState(() {
            _isHdMode = false;
            _isHdOptionEnabled = false;
            _allowCustomSeed = false;
            _commonError = LocaleKeys.walletCreationBip39SeedError.tr();
            _showCustomSeedToggle = true;
          });
          return;
        }
        if (_isHdOptionEnabled) {
          setState(() {
            _isHdOptionEnabled = false;
          });
        }
        if (!_allowCustomSeed) {
          setState(() {
            _commonError = LocaleKeys.walletCreationBip39SeedError.tr();
            _showCustomSeedToggle = true;
          });
          return;
        }
        // Non-HD and custom seed allowed: continue without setting an error
      }

      walletConfig.seedPhrase = decryptedSeed;
      String name = widget.fileData.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      if (!mounted) return;
      final walletsRepository = RepositoryProvider.of<WalletsRepository>(
        context,
      );

      // Check both validation and uniqueness
      String? validationError = walletsRepository.validateWalletName(name);
      String? uniquenessError = await walletsRepository
          .validateWalletNameUniqueness(name);

      // If either validation or uniqueness fails, prompt for renaming
      if (validationError != null || uniquenessError != null) {
        if (!mounted) return;
        final newName = await walletRenameDialog(context, initialName: name);
        if (newName == null) {
          return;
        }
        // Re-validate to protect against TOCTOU (name taken while dialog open)
        final postValidation = walletsRepository.validateWalletName(newName);
        if (postValidation != null) {
          return;
        }
        // Async uniqueness check before proceeding with renamed value
        final postUniquenessError = await walletsRepository
            .validateWalletNameUniqueness(newName);
        if (postUniquenessError != null) {
          return;
        }
        name = newName.trim();
      }
      // Close autofill context after successfully validating password & before import
      TextInput.finishAutofillContext(shouldSave: false);
      widget.onImport(
        name: name,
        password: _filePasswordController.text,
        walletConfig: walletConfig,
        rememberMe: _rememberMe,
      );
    } catch (_) {
      setState(() {
        _commonError = LocaleKeys.somethingWrong.tr();
      });
    }
  }

  bool get _shouldShowCustomSeedToggle {
    if (_isHdMode) return false;
    if (_allowCustomSeed) return true; // keep visible once enabled
    if (_showCustomSeedToggle) {
      return true; // show after first non-HD BIP39 failure
    }
    return false;
  }
}
