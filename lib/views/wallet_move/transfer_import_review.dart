import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart'
    show AuthExceptionType;
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/legal_agreement/legal_agreement_bloc.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/services/wallet_transfer/wallet_transfer_secret.dart';
import 'package:web_dex/shared/widgets/disclaimer/terms_consent_text.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';
import 'package:web_dex/views/settings/widgets/security_settings/security_section_card.dart';
import 'package:web_dex/views/wallet_move/transfer_check_code.dart';

/// The last step of a move or a restore: what will be added, another name
/// when this one is taken here, the terms, then the import.
///
/// Only the import button imports; the keyboard never does. Success is the
/// wallets manager's to finish, as for every other import.
class TransferImportReview extends StatefulWidget {
  const TransferImportReview({
    required this.secret,
    required this.source,
    required this.onCancel,
    this.checkCode,
    this.onCodesDiffer,
    this.onImporting,
    super.key,
  });

  final WalletTransferSecret secret;
  final ManagedImportSource source;
  final VoidCallback onCancel;

  /// A moved wallet's check code, null while it is worked out. Importing is
  /// offered only once it shows, as the user's word that both phones match.
  final String? checkCode;

  /// Set for a move: the codes differ, so the reply came from another phone.
  final VoidCallback? onCodesDiffer;

  /// Told when an import starts (true) and when it came back failed (false).
  final ValueChanged<bool>? onImporting;

  @override
  State<TransferImportReview> createState() => _TransferImportReviewState();
}

class _TransferImportReviewState extends State<TransferImportReview> {
  late final TextEditingController _name = TextEditingController(
    text: widget.secret.walletName,
  );

  /// Whether the name field is shown: only when the wallet's own name cannot
  /// be used here.
  bool _renaming = false;
  String? _nameError;
  String? _importError;
  bool _busy = false;

  /// From dispatch until the bloc answers: nothing here may leave meanwhile.
  bool _dispatched = false;
  late String _lastName = _name.text;

  bool get _comparesCode => widget.onCodesDiffer != null;
  String get _chosenName => _renaming ? _name.text : widget.secret.walletName;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameEdited);
    _checkOwnName();
  }

  @override
  void dispose() {
    _name.removeListener(_onNameEdited);
    _name.dispose();
    super.dispose();
  }

  Future<void> _checkOwnName() async {
    final name = widget.secret.walletName;
    final error = await _nameProblem(name);
    if (!mounted || error == null) return;
    setState(() {
      _renaming = true;
      _nameError = error;
    });
  }

  Future<String?> _nameProblem(String name) async {
    final wallets = context.read<WalletsRepository>();
    final invalid = wallets.validateWalletName(name);
    if (invalid != null) return invalid;
    return await wallets.validateWalletNameUniqueness(name) == null
        ? null
        : _takenText(name);
  }

  /// The keyboard's Done: says whether the name works, and nothing more.
  Future<void> _checkTypedName() async {
    final name = _name.text;
    final error = await _nameProblem(name);
    if (!mounted || name != _name.text) return;
    setState(() => _nameError = error);
  }

  // Cursor moves are reported too; only an edit retires the messages.
  void _onNameEdited() {
    if (_name.text == _lastName) return;
    _lastName = _name.text;
    if (_nameError == null && _importError == null) return;
    setState(() {
      _nameError = null;
      _importError = null;
    });
  }

  String _takenText(String name) =>
      LocaleKeys.walletImportNameTaken.tr(args: [name.trim()]);

  Future<void> _import() async {
    // Left pressable while busy so it keeps focus; repeats end here.
    if (_busy || (_comparesCode && widget.checkCode == null)) return;
    final name = _chosenName;
    setState(() {
      _busy = true;
      _importError = null;
    });
    final problem = await _nameProblem(name);
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _busy = false;
        _renaming = true;
        _nameError = problem;
      });
      return;
    }
    final agreement = await awaitLegalAgreement(context);
    if (!mounted) return;
    final legal = context.read<LegalAgreementBloc>();
    if (agreement == null || !legal.canComplete) {
      setState(() => _busy = false);
      return;
    }
    legal.add(
      LegalAgreementSubmitted(
        widget.source == ManagedImportSource.movedFromDevice
            ? 'wallet-import-move'
            : 'wallet-import-passkey-backup',
        snapshot: agreement.snapshot,
      ),
    );
    setState(() => _dispatched = true);
    widget.onImporting?.call(true);
    context.read<AuthBloc>().add(
      AuthManagedImportRequested(
        secret: widget.secret,
        walletName: name,
        source: widget.source,
      ),
    );
  }

  void _onAuth(BuildContext context, AuthBlocState state) {
    if (!_dispatched || state.isLoading || state.isSignedIn) return;
    widget.onImporting?.call(false);
    setState(() {
      _dispatched = false;
      _busy = false;
      if (!state.isError) return;
      if (state.authError?.type == AuthExceptionType.walletAlreadyExists) {
        _renaming = true;
        _nameError = _takenText(_chosenName);
      } else {
        _importError = 'authImportFailed'.tr();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final secret = widget.secret;
    final importLabel = _comparesCode
        ? 'walletMoveReviewCodesMatch'.tr()
        : LocaleKeys.import.tr();
    final codeShown = !_comparesCode || widget.checkCode != null;
    return PopScope(
      canPop: !_dispatched,
      // The wallets manager closes this sheet with maybePop once the wallet
      // opens, before this state hears of it: let that close through.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && context.read<AuthBloc>().state.isSignedIn) {
          Navigator.of(context).pop();
        }
      },
      child: BlocListener<AuthBloc, AuthBlocState>(
        listenWhen: (previous, current) =>
            previous.status != current.status ||
            previous.authError != current.authError,
        listener: _onAuth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                'walletTransferReviewTitle'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontSize: 20),
              ),
            ),
            const SizedBox(height: 20),
            if (_comparesCode) ...[
              TransferCheckCode(code: widget.checkCode),
              const SizedBox(height: 12),
              Text(
                'walletMoveReviewCheckHint'.tr(),
                style: SecuritySectionText.body(context),
              ),
              const SizedBox(height: 16),
            ],
            if (!_renaming)
              _ReviewRow(
                label: 'walletTransferReviewName'.tr(),
                value: secret.walletName,
              ),
            _ReviewRow(
              label: 'walletTransferReviewType'.tr(),
              value: switch (secret.type) {
                TransferWalletType.hd => 'walletImportTypeHdLabel'.tr(),
                TransferWalletType.legacy => 'walletImportTypeLegacyLabel'.tr(),
              },
            ),
            if (_renaming) ...[
              const SizedBox(height: 8),
              UiTextFormField(
                key: const Key('transfer-review-name'),
                controller: _name,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                textInputAction: TextInputAction.done,
                inputFormatters: [LengthLimitingTextInputFormatter(40)],
                labelText: 'walletTransferReviewNewName'.tr(),
                hintText: LocaleKeys.walletCreationNameHint.tr(),
                errorText: _nameError,
                errorMaxLines: 4,
                onFieldSubmitted: (_) => _checkTypedName(),
              ),
            ],
            const SizedBox(height: 16),
            if (!secret.phraseConfirmed) ...[
              WalletAccessNotice(
                key: const Key('transfer-review-phrase-unconfirmed'),
                text: 'walletTransferPhraseNotConfirmed'.tr(),
                tone: WalletAccessTone.warning,
                announce: false,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.source == ManagedImportSource.passkeyBackup) ...[
              WalletAccessNotice(
                text: 'walletTransferKeepPhrase'.tr(),
                announce: false,
              ),
              const SizedBox(height: 12),
            ],
            if (_importError case final error?) ...[
              WalletAccessNotice(
                key: const Key('transfer-review-error'),
                text: error,
                tone: WalletAccessTone.error,
              ),
              const SizedBox(height: 12),
            ],
            if (_busy) ...[
              WalletAccessProgress(
                label: 'walletTransferOpening'.tr(),
                showLabel: true,
              ),
              const SizedBox(height: 12),
            ],
            // Said before the system asks, not after.
            WalletAccessNotice(
              key: const Key('transfer-review-screen-lock'),
              text: 'walletTransferScreenLockNote'.tr(),
              announce: false,
            ),
            const SizedBox(height: 12),
            TermsConsentText(actionLabel: importLabel),
            const SizedBox(height: 12),
            LegalConsentAction(
              builder: (allowed) => UiPrimaryButton(
                key: const Key('transfer-review-import'),
                text: importLabel,
                expandForText: true,
                height: 50,
                onPressed: allowed && codeShown ? _import : null,
              ),
            ),
            if (!_dispatched) ...[
              if (widget.onCodesDiffer case final differ?) ...[
                const SizedBox(height: 12),
                SecuritySecondaryButton(
                  key: const Key('transfer-review-codes-differ'),
                  text: 'walletMoveReviewCodesDiffer'.tr(),
                  onPressed: _busy ? null : differ,
                ),
              ],
              const SizedBox(height: 12),
              UiUnderlineTextButton(
                key: const Key('transfer-review-cancel'),
                text: LocaleKeys.cancel.tr(),
                expandForText: true,
                onPressed: widget.onCancel,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One labelled fact, read as a single sentence by screen readers.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
