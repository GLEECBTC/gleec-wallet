import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/legal_documents/legal_document.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/shared/ui/ui_gradient_icon.dart';
import 'package:web_dex/shared/utils/encryption_tool.dart';
import 'package:web_dex/shared/widgets/disclaimer/terms_consent_text.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
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
  })
  onImport;
  final void Function() onCancel;

  @override
  State<WalletImportByFile> createState() => _WalletImportByFileState();
}

class _WalletImportByFileState extends State<WalletImportByFile>
    with WidgetsBindingObserver {
  final TextEditingController _filePasswordController = TextEditingController(
    text: '',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isObscured = true;
  bool _isHdMode = true;
  bool _isHdOptionEnabled = true;
  bool _waitingForLegal = false;
  bool _importing = false;
  bool _allowCustomSeed = false;
  bool _showCustomSeedToggle = false;

  String? _filePasswordError;
  String? _commonError;
  String _lastFilePassword = '';

  bool get _isValidData {
    return _filePasswordError == null;
  }

  // Intentionally do not check wallet name here, because it is done on button
  // click and a dialog is shown to rename the wallet if there are issues.
  //
  // This used to be gated on the EULA checkbox alone, so the button was live
  // with an empty password and the flow failed later at decryption. With
  // consent now implicit, the password being present is the real precondition.
  bool get _isButtonEnabled => _filePasswordController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The field has no onChanged, so the button needs a listener to re-enable.
    _filePasswordController.addListener(_onFilePasswordChanged);
  }

  void _onFilePasswordChanged() {
    // The controller also reports cursor moves; only an edit re-enables the
    // button or retires a rejected password's message.
    final password = _filePasswordController.text;
    if (!mounted || password == _lastFilePassword) return;
    _lastFilePassword = password;
    setState(() => _filePasswordError = null);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthBlocState>(
      // Nothing else reports a failed import of this form.
      listenWhen: (previous, current) => current.isError,
      listener: (context, state) => setState(
        () => _commonError =
            state.authError?.type == AuthExceptionType.walletAlreadyExists
            ? LocaleKeys.walletCreationExistNameError.tr()
            : 'authImportFailed'.tr(),
      ),
      child: ScreenshotSensitive(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                LocaleKeys.walletImportByFileTitle.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 20),
              ),
            ),
            const SizedBox(height: 20),
            // Opaque, like the phrase import's instructions: the theme's
            // bodyLarge is half-transparent.
            Text(
              LocaleKeys.walletImportByFileDescription.tr(),
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 20),
            AutofillGroup(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // The file comes first: it is what the password belongs to.
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
                    const SizedBox(height: 16),
                    UiTextFormField(
                      key: const Key('file-password-field'),
                      controller: _filePasswordController,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableIMEPersonalizedLearning: false,
                      enableInteractiveSelection: true,
                      obscureText: _isObscured,
                      maxLength: passwordMaxLength,
                      counterText: '',
                      autofillHints: const [AutofillHints.password],
                      errorText: _filePasswordError,
                      errorMaxLines: 6,
                      hintText: LocaleKeys.walletCreationPasswordHint.tr(),
                      onFieldSubmitted: (_) => _onImport(),
                      suffixIcon: PasswordVisibilityControl(
                        isObscured: _isObscured,
                        onVisibilityChange: (bool isPasswordObscured) {
                          setState(() {
                            _isObscured = isPasswordObscured;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 24),
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
                    const SizedBox(height: 8),
                    Text(
                      'authImportDerivationHint'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (_shouldShowCustomSeedToggle) ...[
                      const SizedBox(height: 12),
                      CustomSeedCheckbox(
                        value: _allowCustomSeed,
                        onChanged: (value) {
                          setState(() {
                            _allowCustomSeed = value;
                          });
                        },
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (_commonError case final error?) ...[
                      WalletAccessNotice(
                        key: const Key('wallet-import-error'),
                        text: error,
                        tone: WalletAccessTone.error,
                      ),
                      const SizedBox(height: 12),
                    ],
                    TermsConsentText(actionLabel: LocaleKeys.import.tr()),
                    const SizedBox(height: 12),
                    LegalConsentAction(
                      builder: (allowed) => UiPrimaryButton(
                        key: const Key('confirm-password-button'),
                        expandForText: true,
                        height: 50,
                        text: LocaleKeys.import.tr(),
                        onPressed: allowed && _isButtonEnabled
                            ? _onImport
                            : null,
                      ),
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
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => _isObscured = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _filePasswordController.removeListener(_onFilePasswordChanged);
    _filePasswordController.clear();
    _filePasswordController.dispose();

    super.dispose();
  }

  // TODO? Investigate if using this instead of a getter may have limitations
  // or issues with multi-instance support
  late final KomodoDefiSdk _sdk = context.read<KomodoDefiSdk>();

  Future<void> _onImport() async {
    if (_waitingForLegal || _importing || !_isButtonEnabled) return;
    _waitingForLegal = true;
    final agreement = await awaitLegalAgreement(context);
    _waitingForLegal = false;
    if (!mounted || agreement == null) return;
    _importing = true;
    try {
      await _decryptAndImport(agreement.snapshot);
    } catch (_) {
      if (mounted) setState(() => _commonError = 'authImportFailed'.tr());
    } finally {
      _importing = false;
    }
  }

  Future<void> _decryptAndImport(LegalConsentSnapshot? consentSnapshot) async {
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
    if (!mounted) return;
    // The same outcome for a wrong password and for a file that was never an
    // encrypted wallet, so the message has to cover both.
    setState(
      () => _filePasswordError = fileData == null
          ? 'authImportFileNotOpened'.tr()
          : null,
    );
    if (fileData == null) return;

    final WalletConfig walletConfig = WalletConfig.fromJson(
      json.decode(fileData),
    );
    walletConfig.type = _isHdMode ? WalletType.hdwallet : WalletType.iguana;
    // Holding an encrypted file is not the same as holding the recovery
    // phrase, and `has_backup` in that file is whatever a previous session
    // self-reported. Importing one is evidence of a file, so the backup
    // prompt stays on until the phrase itself is confirmed. The typed-phrase
    // import path keeps `true` - there the user demonstrably has the words.
    walletConfig.hasBackup = false;

    final String? decryptedSeed = await encryptionTool.decryptData(
      _filePasswordController.text,
      walletConfig.seedPhrase,
    );
    if (!mounted) return;
    if (decryptedSeed == null) {
      setState(() => _commonError = 'authImportFailed'.tr());
      return;
    }
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
    final walletsRepository = RepositoryProvider.of<WalletsRepository>(context);

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
      final renameError =
          walletsRepository.validateWalletName(newName) ??
          await walletsRepository.validateWalletNameUniqueness(newName);
      if (renameError != null) {
        if (mounted) setState(() => _commonError = renameError);
        return;
      }
      name = newName.trim();
    }
    // Close autofill context after successfully validating password & before import
    TextInput.finishAutofillContext(shouldSave: false);
    if (!mounted || !context.read<LegalAgreementBloc>().canComplete) return;
    context.read<LegalAgreementBloc>().add(
      LegalAgreementSubmitted('wallet-import-file', snapshot: consentSnapshot),
    );
    widget.onImport(
      name: name,
      password: _filePasswordController.text,
      walletConfig: walletConfig,
    );
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
