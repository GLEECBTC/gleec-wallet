import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart'
    show WalletDeletionCommittedException;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/views/common/wallet_access/wallet_access_feedback.dart';

part 'wallet_deleting_sections.dart';

/// Reviews what removing [wallet] from this device costs, then removes it.
class WalletDeleting extends StatefulWidget {
  const WalletDeleting({
    super.key,
    required this.wallet,
    required this.close,
    this.additionalWarning,
    this.onBackUpFirst,
  });
  final Wallet wallet;
  final VoidCallback close;
  final String? additionalWarning;

  /// Leaves this review to back up [wallet]'s recovery phrase instead.
  ///
  /// Offered as the primary action while the phrase has no confirmed backup.
  /// Without it, keeping the wallet is the primary action.
  final VoidCallback? onBackUpFirst;

  @override
  State<WalletDeleting> createState() => _WalletDeletingState();
}

class _WalletDeletingState extends State<WalletDeleting> {
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _safeActionFocus = FocusNode(
    debugLabel: 'wallet removal safe action',
  );
  bool _isDeleting = false;
  bool _manualPassword = false;
  bool _hasManagedCredential = false;
  bool _acknowledged = false;
  Future<WalletAccessStatus?>? _accessStatus;
  String? _error;
  WalletDeletionReview? _review;
  bool _reviewReady = false;
  bool _loadingReview = false;
  bool _targetChanged = false;
  int _targetGeneration = 0;
  int _reviewGeneration = 0;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// The evidence Security settings uses for "backed up". A hardware wallet's
  /// phrase never reaches the app, so there is nothing here to lose.
  bool get _needsBackup =>
      !widget.wallet.isHW && !widget.wallet.config.hasRecoveryPhrase;

  bool get _typesPassword => !_hasManagedCredential || _manualPassword;

  bool get _canRemove =>
      _reviewReady && !_isDeleting && (!_needsBackup || _acknowledged);

  @override
  void initState() {
    super.initState();
    // A destructive review opens on its safe choice, never on the field or
    // button that removes the wallet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _safeActionFocus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accessStatus ??=
        context.read<WalletAccessService?>()?.statusForWallet(widget.wallet) ??
        Future<WalletAccessStatus?>.value();
    if (!_targetChanged && !_loadingReview && !_reviewReady) _loadReview();
  }

  @override
  void didUpdateWidget(covariant WalletDeleting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wallet != widget.wallet) {
      _targetGeneration++;
      _isDeleting = false;
      _passwordController.clear();
      _manualPassword = false;
      _hasManagedCredential = false;
      _acknowledged = false;
      _accessStatus =
          context.read<WalletAccessService?>()?.statusForWallet(
            widget.wallet,
          ) ??
          Future<WalletAccessStatus?>.value();
      _error = null;
      _review = null;
      _reviewReady = false;
      _loadingReview = false;
      _targetChanged = false;
      _loadReview();
    }
  }

  Future<void> _loadReview() async {
    final wallet = widget.wallet;
    final targetGeneration = _targetGeneration;
    final reviewGeneration = ++_reviewGeneration;
    bool isCurrent() =>
        mounted &&
        targetGeneration == _targetGeneration &&
        reviewGeneration == _reviewGeneration;
    setState(() {
      _loadingReview = true;
      _error = null;
    });
    try {
      final review = await context
          .read<WalletsRepository>()
          .prepareWalletDeletion(wallet);
      if (!isCurrent()) return;
      setState(() {
        _review = review;
        _reviewReady = true;
        _error = null;
      });
    } catch (_) {
      if (isCurrent()) {
        setState(() => _error = LocaleKeys.walletDeletionReviewFailed.tr());
      }
    } finally {
      if (isCurrent()) {
        setState(() => _loadingReview = false);
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _safeActionFocus.dispose();
    // A removed wallet's password must not be offered to a password manager.
    TextInput.finishAutofillContext(shouldSave: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WalletAccessStatus?>(
      future: _accessStatus,
      builder: (context, snapshot) {
        final status = snapshot.data;
        _hasManagedCredential = status?.hasManagedCredential == true;
        final textTheme = Theme.of(context).textTheme;
        return ScreenshotSensitive(
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): widget.close,
            },
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RemovalBackControl(onPressed: widget.close),
                  const SizedBox(height: 8),
                  Semantics(
                    header: true,
                    child: Text(
                      'authRemoveWalletDialogTitle'.tr(
                        args: [widget.wallet.displayName],
                      ),
                      style: textTheme.titleLarge?.copyWith(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Emphasis runs title, backup status, what is removed, then
                  // pending transfers: the phrase is what decides whether
                  // removal is recoverable.
                  if (_needsBackup)
                    ..._backUpFirst()
                  else
                    WalletAccessNotice(
                      key: const Key('wallet-removal-backed-up-reminder'),
                      text: 'authRemoveWalletBackedUpReminder'.tr(),
                      announce: false,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'authRemoveWalletDialogBody'.tr(),
                    style: textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.additionalWarning case final warning?) ...[
                    const SizedBox(height: 12),
                    WalletAccessNotice(
                      text: warning,
                      tone: WalletAccessTone.warning,
                      announce: false,
                    ),
                  ],
                  _PendingTransfers(review: _review),
                  if (_loadingReview) ...[
                    const SizedBox(height: 16),
                    WalletAccessProgress(
                      label: 'authRemoveWalletChecking'.tr(),
                      showLabel: true,
                    ),
                  ],
                  if (_needsBackup) ...[
                    const SizedBox(height: 12),
                    _RemovalAcknowledgement(
                      value: _acknowledged,
                      onChanged: (value) =>
                          setState(() => _acknowledged = value),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildAuthorization(status),
                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    WalletAccessNotice(
                      key: const Key('wallet-removal-error'),
                      text: error,
                      tone: WalletAccessTone.error,
                    ),
                  ],
                  if (!_targetChanged && !_loadingReview && !_reviewReady)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _RemovalTextAction(
                        label: LocaleKeys.tryAgain.tr(),
                        onPressed: _loadReview,
                      ),
                    ),
                  if (_isDeleting) ...[
                    const SizedBox(height: 16),
                    WalletAccessProgress(
                      label: 'authRemovingWallet'.tr(),
                      showLabel: true,
                    ),
                  ],
                  const SizedBox(height: 24),
                  _buildActions(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The warning and its remedy, kept together above the removal controls.
  List<Widget> _backUpFirst() {
    final backUp = widget.onBackUpFirst;
    return [
      NoticeBanner(
        key: const Key('wallet-removal-not-backed-up'),
        variant: NoticeBannerVariant.critical,
        child: WalletAccessNotice(
          text: 'authRemoveWalletNotBackedUp'.tr(),
          tone: WalletAccessTone.warning,
        ),
      ),
      const SizedBox(height: 12),
      UiPrimaryButton(
        key: const Key('wallet-removal-safe-action'),
        focusNode: _safeActionFocus,
        expandForText: true,
        height: 48,
        padding: _removalButtonPadding,
        text: backUp == null
            ? LocaleKeys.cancel.tr()
            : 'authBackUpRecoveryPhraseFirst'.tr(),
        onPressed: backUp ?? widget.close,
      ),
      const SizedBox(height: 16),
      const UiDivider(),
    ];
  }

  Widget _buildAuthorization(WalletAccessStatus? status) {
    if (!_typesPassword) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status?.requiresAuthentication == true)
            Text('authRemoveWalletDeviceConfirmation'.tr()),
          _RemovalTextAction(
            label: 'authUsePassword'.tr(),
            onPressed: () => setState(() {
              _manualPassword = true;
              _error = null;
            }),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RemovalPasswordField(
          walletName: widget.wallet.name,
          controller: _passwordController,
          onFieldSubmitted: _deleteWallet,
          onChanged: _handlePasswordChanged,
          validator: (password) => password == null || password.isEmpty
              ? LocaleKeys.enterThePassword.tr()
              : null,
        ),
        if (_hasManagedCredential)
          _RemovalTextAction(
            label: 'authUseDeviceUnlock'.tr(),
            onPressed: () => setState(() {
              _manualPassword = false;
              _passwordController.clear();
              _error = null;
            }),
          ),
      ],
    );
  }

  Widget _buildActions() {
    // Stays pressable while removing so keyboard focus is not thrown away;
    // `_deleteWallet` ignores the repeat.
    final onRemove = _canRemove || _isDeleting ? _deleteWallet : null;
    if (_needsBackup) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RemoveWalletButton(onPressed: onRemove, filled: false),
          if (widget.onBackUpFirst != null) ...[
            const SizedBox(height: 8),
            UiUnderlineTextButton(
              key: const Key('wallet-removal-cancel'),
              text: LocaleKeys.cancel.tr(),
              onPressed: widget.close,
            ),
          ],
        ],
      );
    }
    final cancel = OutlinedButton(
      key: const Key('wallet-removal-cancel'),
      focusNode: _safeActionFocus,
      style: _removalOutlinedStyle(context),
      onPressed: widget.close,
      child: Text(LocaleKeys.cancel.tr()),
    );
    final remove = _RemoveWalletButton(onPressed: onRemove, filled: true);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth < 320 * scale) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [remove, const SizedBox(height: 8), cancel],
          );
        }
        return Row(
          children: [
            Expanded(child: cancel),
            const SizedBox(width: 8),
            Expanded(child: remove),
          ],
        );
      },
    );
  }

  void _handlePasswordChanged(String? value) {
    // Clear the error when user starts typing a new password
    if (_error != null) {
      setState(() {
        _error = null;
      });
    }
  }

  Future<void> _deleteWallet() async {
    if (!_canRemove) return;
    final typesPassword = _typesPassword;
    if (typesPassword && !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _isDeleting = true;
      _error = null;
    });
    final walletsRepository = RepositoryProvider.of<WalletsRepository>(context);
    // The dialog is gone by the time a removal can be confirmed.
    final messenger = ScaffoldMessenger.maybeOf(context);
    final wallet = widget.wallet;
    final targetGeneration = _targetGeneration;
    bool isCurrent() => mounted && targetGeneration == _targetGeneration;
    void closeAfterRemoval(String message) {
      widget.close();
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }

    try {
      final access = context.read<WalletAccessService?>();
      final supplied = typesPassword ? _passwordController.text : null;
      final password = access == null
          ? supplied!
          : await access.credentialForDeletion(wallet, password: supplied);
      _passwordController.clear();
      if (!isCurrent()) return;
      final result = await walletsRepository.deleteWallet(
        wallet,
        password: password,
        acknowledgedReview: _review,
      );
      if (!isCurrent()) return;
      switch (result.status) {
        case WalletDeletionStatus.deleted:
          closeAfterRemoval('authWalletRemoved'.tr());
        case WalletDeletionStatus.busy:
          _error = LocaleKeys.walletDeletionSubmissionBusy.tr();
        case WalletDeletionStatus.reviewChanged:
          _review = result.review;
          _error = LocaleKeys.walletDeletionReviewChanged.tr();
        case WalletDeletionStatus.targetChanged:
          _reviewReady = false;
          _targetChanged = true;
          _error = LocaleKeys.walletDeletionTargetChanged.tr();
      }
    } catch (e) {
      if (!mounted || !isCurrent()) return;
      if (e is WalletDeletionCommittedException) {
        closeAfterRemoval('authWalletRemovedSettingsPending'.tr());
        return;
      }
      final access = context.read<WalletAccessService?>();
      if (e is WalletAccessException &&
          e.failure == WalletAccessFailure.storageFailed &&
          access != null) {
        try {
          final pendingCleanup = await access.hasPendingCredentialCleanup;
          if (!isCurrent()) return;
          if (pendingCleanup) {
            final remaining = await walletsRepository.refreshWallets();
            if (!isCurrent()) return;
            if (!remaining.any((candidate) => candidate.name == wallet.name)) {
              closeAfterRemoval('authWalletRemoved'.tr());
              return;
            }
          }
        } catch (_) {
          // The original safe error remains visible when storage is unreadable.
        }
      }
      _error = switch (e) {
        WalletAccessException(
          failure: WalletAccessFailure.walletMustBeUnlocked,
        ) =>
          'authUnlockWalletBeforeDeletion'.tr(),
        AuthException(type: AuthExceptionType.walletNotFound) =>
          LocaleKeys.walletNotFound.tr(),
        _ => walletAccessFailureText(
          e,
          passwordEntered: typesPassword,
          unlocking: false,
        ),
      };
    } finally {
      if (isCurrent()) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
}
