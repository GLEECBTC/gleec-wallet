part of 'wallet_simple_import.dart';

/// Everything about typing a recovery phrase: its field, the BIP39 word
/// suggestions, and which wallet types the phrase can open.
mixin _RecoveryPhraseEntry on State<WalletSimpleImport> {
  static const int _maxSeedSuggestions = 8;
  final TextEditingController _seedController = TextEditingController(text: '');
  bool _isSeedHidden = true;
  bool _allowCustomSeed = false;
  bool _legacyModeSelected = false;
  bool get _isHdMode => !_legacyModeSelected && _isHdCompatibleWithCurrentSeed;
  List<String> _bip39Words = const [];
  List<String> _seedWordSuggestions = const [];
  int _activeWordStart = -1;
  int _activeWordEnd = -1;

  /// Enter on the phrase field continues the form.
  void _onImport();

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

  Widget _buildSeedSuggestions() {
    return Align(
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
    );
  }

  Widget _buildSeedField() {
    return UiTextFormField(
      key: const Key('import-seed-field'),
      controller: _seedController,
      validator: _validateSeed,
      textInputAction: TextInputAction.done,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      obscureText: _isSeedHidden,
      maxLines: _isSeedHidden ? 1 : null,
      errorMaxLines: 4,
      style: Theme.of(context).textTheme.bodyMedium,
      hintText: LocaleKeys.importSeedEnterSeedPhraseHint.tr(),
      suffixIcon: PasswordVisibilityControl(
        isObscured: _isSeedHidden,
        showLabel: 'authShowRecoveryPhrase'.tr(),
        hideLabel: 'authHideRecoveryPhrase'.tr(),
        onVisibilityChange: (bool isObscured) {
          setState(() {
            _isSeedHidden = isObscured;
            _updateSeedWordSuggestions();
          });
        },
      ),
      onFieldSubmitted: (_) => _onImport(),
    );
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

/// The secondary way in: an encrypted wallet file instead of the phrase.
class _WalletFilePicker extends StatefulWidget {
  const _WalletFilePicker({
    required this.fileLoader,
    required this.onUploadFiles,
  });

  final FileLoader? fileLoader;
  final void Function({required String fileName, required String fileData})
  onUploadFiles;

  @override
  State<_WalletFilePicker> createState() => _WalletFilePickerState();
}

class _WalletFilePickerState extends State<_WalletFilePicker> {
  String? _fileError;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UploadButton(
          buttonText: LocaleKeys.walletCreationUploadFile.tr(),
          uploadFile: _pickWalletFile,
        ),
        if (_fileError case final error?) ...[
          const SizedBox(height: 8),
          WalletAccessNotice(
            key: const Key('wallet-import-file-error'),
            text: error,
            tone: WalletAccessTone.error,
          ),
        ],
      ],
    );
  }

  Future<void> _pickWalletFile() async {
    if (_fileError != null) setState(() => _fileError = null);
    await (widget.fileLoader ?? FileLoader.fromPlatform()).upload(
      onUpload: (fileName, fileData) =>
          widget.onUploadFiles(fileData: fileData ?? '', fileName: fileName),
      onError: (String error) {
        log(
          error,
          path: 'wallet_simple_import => _pickWalletFile => onError',
          isError: true,
        );
        // The loader's reason is English-only and may arrive after the picker
        // has closed; the notice says which file to choose instead.
        if (mounted) {
          setState(() => _fileError = 'authImportFileRejected'.tr());
        }
      },
      fileType: LoadFileType.text,
    );
  }
}
