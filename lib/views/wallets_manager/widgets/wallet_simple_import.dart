import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show MnemonicFailedReason;
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/file_loader/file_loader.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/disclaimer/eula_tos_checkboxes.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/shared/widgets/quick_login_switch.dart';
import 'package:web_dex/views/wallets_manager/widgets/creation_password_fields.dart';
import 'package:web_dex/views/wallets_manager/widgets/custom_seed_checkbox.dart';
import 'package:web_dex/views/wallets_manager/widgets/wallet_import_type_dropdown.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

class WalletSimpleImport extends StatefulWidget {
  const WalletSimpleImport({
    required this.onImport,
    required this.onUploadFiles,
    required this.onCancel,
    super.key,
  });

  final void Function({
    required String name,
    required String password,
    required WalletConfig walletConfig,
    required bool rememberMe,
  })
  onImport;

  final void Function() onCancel;

  final void Function({required String fileName, required String fileData})
  onUploadFiles;

  @override
  State<WalletSimpleImport> createState() => _WalletImportWrapperState();
}

enum WalletSimpleImportSteps { nameAndSeed, password }

class _WalletImportWrapperState extends State<WalletSimpleImport> {
  static const int _maxSeedSuggestions = 8;
  WalletSimpleImportSteps _step = WalletSimpleImportSteps.nameAndSeed;
  final TextEditingController _nameController = TextEditingController(text: '');
  final TextEditingController _seedController = TextEditingController(text: '');
  final TextEditingController _passwordController = TextEditingController(
    text: '',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isSeedHidden = true;
  bool _eulaAndTosChecked = false;
  bool _inProgress = false;
  bool _allowCustomSeed = false;
  bool _isHdMode = true;
  bool _rememberMe = false;
  List<String> _bip39Words = const [];
  List<String> _seedWordSuggestions = const [];
  int _activeWordStart = -1;
  int _activeWordEnd = -1;

  bool get _isButtonEnabled {
    final isFormValid = _refreshFormValidationState();

    return _eulaAndTosChecked && !_inProgress && isFormValid;
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthBlocState>(
      listener: (context, state) {
        if (!state.isLoading) {
          setState(() => _inProgress = false);
        }

        if (state.isError) {
          final theme = Theme.of(context);
          final message =
              state.authError?.message ?? LocaleKeys.somethingWrong.tr();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                message,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
              backgroundColor: theme.colorScheme.errorContainer,
            ),
          );
        }
      },
      child: AutofillGroup(
        child: ScreenshotSensitive(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SelectableText(
                _step == WalletSimpleImportSteps.nameAndSeed
                    ? LocaleKeys.walletImportTitle.tr()
                    : LocaleKeys.walletImportCreatePasswordTitle.tr(
                        args: [_nameController.text.trim()],
                      ),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontSize: 20),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _buildFields(),
                    const SizedBox(height: 20),
                    UiPrimaryButton(
                      key: const Key('confirm-seed-button'),
                      text: _inProgress
                          ? '${LocaleKeys.pleaseWait.tr()}...'
                          : LocaleKeys.import.tr(),
                      height: 50,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      onPressed: _isButtonEnabled ? _onImport : null,
                    ),
                    const SizedBox(height: 20),
                    UiUnderlineTextButton(
                      onPressed: _onCancel,
                      text: _step == WalletSimpleImportSteps.nameAndSeed
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

  @override
  void initState() {
    super.initState();
    _seedController.addListener(_onSeedChanged);
    unawaited(_loadBip39Wordlist());
  }

  void _onSeedChanged() {
    _updateSeedWordSuggestions();
    _syncWalletTypeWithSeedCompatibility();
    setState(() {});
  }

  Future<void> _loadBip39Wordlist() async {
    try {
      final wordlist = await rootBundle.loadString(
        'packages/komodo_defi_types/assets/bip-0039/english-wordlist.txt',
      );
      final words = wordlist
          .split('\n')
          .map((word) => word.trim().toLowerCase())
          .where((word) => word.isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _bip39Words = words;
        _updateSeedWordSuggestions();
      });
    } catch (_) {
      // Suggestions are a progressive enhancement; import still works without
      // the wordlist if asset loading fails.
    }
  }

  void _clearSeedWordSuggestions() {
    _seedWordSuggestions = const [];
    _activeWordStart = -1;
    _activeWordEnd = -1;
  }

  void _updateSeedWordSuggestions() {
    if (_allowCustomSeed || _isSeedHidden || _bip39Words.isEmpty) {
      _clearSeedWordSuggestions();
      return;
    }

    final text = _seedController.text.toLowerCase();
    final cursor = _seedController.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) {
      _clearSeedWordSuggestions();
      return;
    }

    int start = cursor;
    while (start > 0 && text[start - 1] != ' ') {
      start--;
    }

    int end = cursor;
    while (end < text.length && text[end] != ' ') {
      end++;
    }

    final prefix = text.substring(start, cursor).trim();
    if (prefix.isEmpty || !RegExp(r'^[a-z]+$').hasMatch(prefix)) {
      _clearSeedWordSuggestions();
      return;
    }

    final suggestions = _bip39Words
        .where((word) => word.startsWith(prefix))
        .take(_maxSeedSuggestions)
        .toList(growable: false);

    if (suggestions.length == 1 && suggestions.first == prefix) {
      _clearSeedWordSuggestions();
      return;
    }

    _seedWordSuggestions = suggestions;
    _activeWordStart = start;
    _activeWordEnd = end;
  }

  void _onSeedSuggestionSelected(String suggestion) {
    if (_activeWordStart < 0 || _activeWordEnd < _activeWordStart) return;

    var nextText = _seedController.text.replaceRange(
      _activeWordStart,
      _activeWordEnd,
      suggestion,
    );
    var nextCursor = _activeWordStart + suggestion.length;

    if (nextCursor == nextText.length || nextText[nextCursor] != ' ') {
      nextText = nextText.replaceRange(nextCursor, nextCursor, ' ');
      nextCursor += 1;
    }

    _seedController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _seedController.dispose();
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
      children: [
        CreationPasswordFields(
          passwordController: _passwordController,
          onFieldSubmitted: !_isButtonEnabled
              ? null
              : (text) {
                  _onImport();
                },
        ),
        const SizedBox(height: 20),
        QuickLoginSwitch(
          value: _rememberMe,
          onChanged: (value) {
            setState(() => _rememberMe = value);
          },
        ),
      ],
    );
  }

  Widget _buildImportFileButton() {
    return UploadButton(
      buttonText: LocaleKeys.walletCreationUploadFile.tr(),
      uploadFile: () async {
        await FileLoader.fromPlatform().upload(
          onUpload: (fileName, fileData) => widget.onUploadFiles(
            fileData: fileData ?? '',
            fileName: fileName,
          ),
          onError: (String error) {
            log(
              error,
              path:
                  'wallet_simple_import => _buildImportFileButton => onErrorUploadFiles',
              isError: true,
            );
          },
          fileType: LoadFileType.text,
        );
      },
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
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _seedWordSuggestions
                  .map(
                    (word) => ActionChip(
                      label: Text(word),
                      onPressed: () => _onSeedSuggestionSelected(word),
                    ),
                  )
                  .toList(),
            ),
          ),
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
        const SizedBox(height: 20),
        UiDivider(text: LocaleKeys.seedOr.tr()),
        const SizedBox(height: 20),
        _buildImportFileButton(),
        const SizedBox(height: 15),
        if (_shouldShowCustomSeedToggle) _buildCheckBoxCustomSeed(),
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
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.username],
      validator: (String? name) =>
          _inProgress ? null : walletsRepository.validateWalletName(name ?? ''),
      inputFormatters: [LengthLimitingTextInputFormatter(40)],
      hintText: LocaleKeys.walletCreationNameHint.tr(),
    );
  }

  Widget _buildSeedField() {
    return UiTextFormField(
      key: const Key('import-seed-field'),
      controller: _seedController,
      autofocus: true,
      validator: _validateSeed,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      obscureText: _isSeedHidden,
      maxLines: _isSeedHidden ? 1 : null,
      errorMaxLines: 4,
      style: Theme.of(context).textTheme.bodyMedium,
      hintText: LocaleKeys.importSeedEnterSeedPhraseHint.tr(),
      suffixIcon: PasswordVisibilityControl(
        onVisibilityChange: (bool isObscured) {
          setState(() {
            _isSeedHidden = isObscured;
            _updateSeedWordSuggestions();
          });
        },
      ),
      onFieldSubmitted: !_isButtonEnabled
          ? null
          : (text) {
              _onImport();
            },
    );
  }

  void _onCancel() {
    if (_step == WalletSimpleImportSteps.password) {
      setState(() {
        _step = WalletSimpleImportSteps.nameAndSeed;
      });
      return;
    }
    widget.onCancel();
  }

  void _onImport() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_step == WalletSimpleImportSteps.nameAndSeed) {
      setState(() {
        _step = WalletSimpleImportSteps.password;
      });
      return;
    }

    final WalletConfig config = WalletConfig(
      type: _isHdMode ? WalletType.hdwallet : WalletType.iguana,
      activatedCoins: enabledByDefaultCoins,
      hasBackup: true,
      seedPhrase: _seedController.text,
    );

    setState(() => _inProgress = true);

    // Async uniqueness check before proceeding
    final repo = context.read<WalletsRepository>();
    final uniquenessError = await repo.validateWalletNameUniqueness(
      _nameController.text,
    );
    if (uniquenessError != null) {
      if (mounted) {
        setState(() => _inProgress = false);
        final theme = Theme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              uniquenessError,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            backgroundColor: theme.colorScheme.errorContainer,
          ),
        );
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onImport(
        name: _nameController.text.trim(),
        password: _passwordController.text,
        walletConfig: config,
        rememberMe: _rememberMe,
      );
    });
  }

  String? _validateSeed(String? seed) {
    if (_allowCustomSeed) {
      return null;
    }

    final maybeFailedReason = context
        .read<KomodoDefiSdk>()
        .mnemonicValidator
        .validateMnemonic(
          seed ?? '',
          minWordCount: 12,
          maxWordCount: 24,
          isHd: _isHdMode,
          allowCustomSeed: _allowCustomSeed,
        );

    if (maybeFailedReason == null) {
      return null;
    }

    return switch (maybeFailedReason) {
      MnemonicFailedReason.empty =>
        LocaleKeys.walletCreationEmptySeedError.tr(),
      MnemonicFailedReason.customNotSupportedForHd =>
        _isHdMode
            ? LocaleKeys.walletCreationHdBip39SeedError.tr()
            : LocaleKeys.walletCreationBip39SeedError.tr(),
      MnemonicFailedReason.customNotAllowed =>
        LocaleKeys.customSeedWarningText.tr(),
      MnemonicFailedReason.invalidWord =>
        LocaleKeys.mnemonicInvalidWordError.tr(),
      MnemonicFailedReason.invalidChecksum =>
        LocaleKeys.mnemonicInvalidChecksumError.tr(),
      MnemonicFailedReason.invalidLength =>
        LocaleKeys.mnemonicInvalidLengthError.tr(),
    };
  }

  bool get _shouldShowCustomSeedToggle {
    if (_isHdMode) return false;
    if (_allowCustomSeed) return true; // keep visible once enabled

    final seed = _seedController.text.trim();
    if (seed.isEmpty) return false;

    final validator = context.read<KomodoDefiSdk>().mnemonicValidator;
    final isBip39 = validator.validateBip39(seed);
    return !isBip39;
  }

  void _syncWalletTypeWithSeedCompatibility() {
    if (_isHdMode && !_isHdCompatibleWithCurrentSeed) {
      _isHdMode = false;
      _allowCustomSeed = false;
    }
  }

  bool get _isHdCompatibleWithCurrentSeed {
    final seed = _seedController.text.trim().toLowerCase();
    if (seed.isEmpty) return true;

    final words = seed.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final int wordCount = words.length;
    if (wordCount == 1) {
      final token = words.first;
      final bool looksLikeBip39Word =
          RegExp(r'^[a-z]+$').hasMatch(token) && token.length <= 8;
      return looksLikeBip39Word;
    }

    if (wordCount < 12) {
      return true;
    }

    final validator = context.read<KomodoDefiSdk>().mnemonicValidator;
    return validator.validateBip39(seed);
  }
}
