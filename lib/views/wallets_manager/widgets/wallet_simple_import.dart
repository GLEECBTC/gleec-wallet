import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show MnemonicFailedReason;
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AuthException, AuthExceptionType;
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/disclaimer/terms_consent_text.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/views/wallets_manager/widgets/creation_password_fields.dart';
import 'package:web_dex/views/wallets_manager/widgets/custom_seed_checkbox.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_import_type_dropdown.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/wallet_move/wallet_transfer_import_options.dart';

part 'wallet_simple_import_phrase.dart';

class WalletSimpleImport extends StatefulWidget {
  const WalletSimpleImport({
    required this.onImport,
    required this.onUploadFiles,
    required this.onCancel,
    this.fileLoader,
    this.onMoveFromDevice,
    this.onRestoreFromPasskey,
    super.key,
  });

  final void Function({
    required String name,
    required String password,
    required WalletConfig walletConfig,
  })
  onImport;

  final void Function() onCancel;

  final void Function({required String fileName, required String fileData})
  onUploadFiles;

  /// Picks the encrypted wallet file. Defaults to the platform's picker.
  final FileLoader? fileLoader;

  /// The no-typing ways in; each row shows only where it can work.
  final VoidCallback? onMoveFromDevice;
  final VoidCallback? onRestoreFromPasskey;

  @override
  State<WalletSimpleImport> createState() => _WalletImportWrapperState();
}

enum WalletSimpleImportSteps { nameAndSeed, password }

class _WalletImportWrapperState extends State<WalletSimpleImport>
    with WidgetsBindingObserver, _RecoveryPhraseEntry {
  WalletSimpleImportSteps _step = WalletSimpleImportSteps.nameAndSeed;
  final TextEditingController _nameController = TextEditingController(text: '');
  final TextEditingController _passwordController = TextEditingController(
    text: '',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _inProgress = false;
  bool _waitingForLegal = false;
  bool _checkingName = false;
  bool _arePasswordsValid = false;
  String? _nameTakenError;
  String? _importError;
  String _lastName = '';

  bool get _isStepValid {
    if (_step == WalletSimpleImportSteps.password) return _arePasswordsValid;
    return _nameTakenError == null &&
        _nameController.text.isNotEmpty &&
        _seedController.text.isNotEmpty &&
        context.read<WalletsRepository>().validateWalletName(
              _nameController.text,
            ) ==
            null &&
        _validateSeed(_seedController.text) == null;
  }

  @override
  Widget build(BuildContext context) {
    final isFirstStep = _step == WalletSimpleImportSteps.nameAndSeed;
    return BlocListener<AuthBloc, AuthBlocState>(
      listener: (context, state) {
        if (!state.isLoading) {
          setState(() => _inProgress = false);
        }
        if (state.isError) _showImportFailure(state.authError);
      },
      child: AutofillGroup(
        child: ScreenshotSensitive(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  isFirstStep
                      ? LocaleKeys.walletImportTitle.tr()
                      : LocaleKeys.walletImportCreatePasswordTitle.tr(
                          args: [_nameController.text.trim()],
                        ),
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontSize: 20),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildFields(),
                    const SizedBox(height: 20),
                    if (_importError case final error?) ...[
                      WalletAccessNotice(
                        key: const Key('wallet-import-error'),
                        text: error,
                        tone: WalletAccessTone.error,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!isFirstStep) ...[
                      TermsConsentText(actionLabel: LocaleKeys.import.tr()),
                      const SizedBox(height: 12),
                    ],
                    LegalConsentAction(
                      enforce: !isFirstStep,
                      builder: (allowed) => UiPrimaryButton(
                        key: const Key('confirm-seed-button'),
                        text: _inProgress
                            ? '${LocaleKeys.pleaseWait.tr()}...'
                            : isFirstStep
                            ? LocaleKeys.continueText.tr()
                            : LocaleKeys.import.tr(),
                        expandForText: true,
                        height: 50,
                        textStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        // Stays pressable while importing so keyboard focus
                        // is kept; `_onImport` ignores the repeat.
                        onPressed: allowed && (_isStepValid || _inProgress)
                            ? _onImport
                            : null,
                      ),
                    ),
                    if (isFirstStep) ...[
                      const SizedBox(height: 20),
                      UiDivider(text: LocaleKeys.seedOr.tr()),
                      const SizedBox(height: 20),
                      _WalletFilePicker(
                        fileLoader: widget.fileLoader,
                        onUploadFiles: widget.onUploadFiles,
                      ),
                      WalletTransferImportOptions(
                        onMoveFromDevice: widget.onMoveFromDevice,
                        onRestoreFromPasskey: widget.onRestoreFromPasskey,
                      ),
                    ],
                    const SizedBox(height: 20),
                    UiUnderlineTextButton(
                      onPressed: _onCancel,
                      text: isFirstStep
                          ? LocaleKeys.cancel.tr()
                          : LocaleKeys.back.tr(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImportFailure(AuthException? error) {
    final nameTaken = error?.type == AuthExceptionType.walletAlreadyExists;
    setState(() {
      if (nameTaken) {
        _showNameTaken();
      } else {
        _importError = 'authImportFailed'.tr();
      }
    });
  }

  /// Returns to the name field: the error belongs beside what must change.
  void _showNameTaken() {
    _nameTakenError = LocaleKeys.walletImportNameTaken.tr(
      args: [_nameController.text.trim()],
    );
    _step = WalletSimpleImportSteps.nameAndSeed;
    _arePasswordsValid = false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nameController.addListener(_onNameChanged);
    _seedController.addListener(_onSeedChanged);
    unawaited(_loadBip39Wordlist());
  }

  // Continue depends on the name too, and the name field rebuilds nothing
  // else. Cursor moves are reported here as well; only an edit retires the
  // messages about the previous attempt.
  void _onNameChanged() {
    if (_nameController.text == _lastName) return;
    _lastName = _nameController.text;
    setState(() {
      _nameTakenError = null;
      _importError = null;
    });
  }

  void _onSeedChanged() {
    _updateSeedWordSuggestions();
    _syncWalletTypeWithSeedCompatibility();
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || !mounted) return;
    setState(() {
      _isSeedHidden = true;
      _clearSeedWordSuggestions();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _seedController.removeListener(_onSeedChanged);
    _seedController.clear();
    _seedController.dispose();
    _passwordController.clear();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _buildCheckBoxCustomSeed() {
    return CustomSeedCheckbox(
      value: _allowCustomSeed,
      onChanged: (value) {
        setState(() {
          _allowCustomSeed = value;
          _updateSeedWordSuggestions();
        });

        _refreshFormValidationState();
      },
    );
  }

  bool _refreshFormValidationState() {
    final nameHasValue = _nameController.text.isNotEmpty;
    final seedHasValue = _seedController.text.isNotEmpty;

    if (seedHasValue && nameHasValue) {
      return _formKey.currentState!.validate();
    }

    return false;
  }

  Widget _buildFields() {
    switch (_step) {
      case WalletSimpleImportSteps.nameAndSeed:
        return _buildNameAndSeed();
      case WalletSimpleImportSteps.password:
        return _buildPasswordStep();
    }
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('authImportPasswordPurpose'.tr()),
        const SizedBox(height: 16),
        CreationPasswordFields(
          passwordController: _passwordController,
          autofocus: true,
          onValidityChanged: (isValid) {
            setState(() => _arePasswordsValid = isValid);
          },
          onFieldSubmitted: (_) => _onImport(),
        ),
      ],
    );
  }

  Widget _buildNameAndSeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNameField(),
        const SizedBox(height: 16),
        _buildSeedField(),
        if (_seedWordSuggestions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildSeedSuggestions(),
        ],
        const SizedBox(height: 16),
        WalletImportTypeDropdown(
          selectedType: _isHdMode ? WalletType.hdwallet : WalletType.iguana,
          isHdOptionEnabled: _isHdCompatibleWithCurrentSeed,
          onChanged: (walletType) {
            setState(() {
              _isHdMode = walletType == WalletType.hdwallet;
              _allowCustomSeed = false;
              _updateSeedWordSuggestions();
            });
            _refreshFormValidationState();
          },
        ),
        const SizedBox(height: 8),
        Text(
          'authImportDerivationHint'.tr(),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        if (_shouldShowCustomSeedToggle) ...[
          const SizedBox(height: 12),
          _buildCheckBoxCustomSeed(),
        ],
      ],
    );
  }

  Widget _buildNameField() {
    final walletsRepository = RepositoryProvider.of<WalletsRepository>(context);
    return UiTextFormField(
      key: const Key('name-wallet-field'),
      controller: _nameController,
      autofocus: true,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username],
      validator: (String? name) =>
          _inProgress ? null : walletsRepository.validateWalletName(name ?? ''),
      errorText: _nameTakenError,
      errorMaxLines: 4,
      inputFormatters: [LengthLimitingTextInputFormatter(40)],
      hintText: LocaleKeys.walletCreationNameHint.tr(),
    );
  }

  void _onCancel() {
    if (_step == WalletSimpleImportSteps.password) {
      setState(() {
        _step = WalletSimpleImportSteps.nameAndSeed;
        _arePasswordsValid = false;
      });
      return;
    }
    widget.onCancel();
  }

  @override
  void _onImport() async {
    if (_inProgress || _waitingForLegal || _checkingName) return;
    // Enter on the last field lands here too: show what still needs fixing.
    if (!(_formKey.currentState?.validate() ?? false) || !_isStepValid) {
      return;
    }
    final repo = context.read<WalletsRepository>();

    if (_step == WalletSimpleImportSteps.nameAndSeed) {
      // Checked here, while the name field is still on screen to correct.
      final name = _nameController.text;
      _checkingName = true;
      final bool taken;
      try {
        taken = await repo.validateWalletNameUniqueness(name) != null;
      } finally {
        _checkingName = false;
      }
      if (!mounted ||
          name != _nameController.text ||
          _step != WalletSimpleImportSteps.nameAndSeed) {
        return;
      }
      setState(() {
        if (taken) {
          _showNameTaken();
        } else {
          _step = WalletSimpleImportSteps.password;
        }
      });
      return;
    }

    _waitingForLegal = true;
    final agreement = await awaitLegalAgreement(context);
    _waitingForLegal = false;
    if (!mounted ||
        agreement == null ||
        _step != WalletSimpleImportSteps.password ||
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final consentSnapshot = agreement.snapshot;

    final WalletConfig config = WalletConfig(
      type: _isHdMode ? WalletType.hdwallet : WalletType.iguana,
      activatedCoins: enabledByDefaultCoins,
      // The user typed every word, which is stronger evidence of holding the
      // phrase than the confirmation quiz asks for. File import is the case
      // that must not claim this - see `wallet_import_by_file.dart`.
      hasBackup: true,
      seedPhrase: _seedController.text,
    );

    setState(() {
      _inProgress = true;
      _importError = null;
    });

    // The name may have been taken since the first step (another tab).
    final taken =
        await repo.validateWalletNameUniqueness(_nameController.text) != null;
    if (taken) {
      if (mounted) {
        setState(() {
          _inProgress = false;
          _showNameTaken();
        });
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !context.read<LegalAgreementBloc>().canComplete) return;
      context.read<LegalAgreementBloc>().add(
        LegalAgreementSubmitted(
          'wallet-import-seed',
          snapshot: consentSnapshot,
        ),
      );
      widget.onImport(
        name: _nameController.text.trim(),
        password: _passwordController.text,
        walletConfig: config,
      );
    });
  }
}
