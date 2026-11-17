import 'package:web_dex/services/wallet_access/wallet_access_service.dart';
import 'package:app_theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart'
    show WalletDeletionCommittedException;
import 'package:web_dex/shared/constants.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/blocs/wallets_repository.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/widgets/password_visibility_control.dart';
import 'package:web_dex/shared/screenshot/screenshot_sensitivity.dart';

class WalletDeleting extends StatefulWidget {
  const WalletDeleting({
    super.key,
    required this.wallet,
    required this.close,
    this.additionalWarning,
  });
  final Wallet wallet;
  final VoidCallback close;
  final String? additionalWarning;

  @override
  State<WalletDeleting> createState() => _WalletDeletingState();
}

class _WalletDeletingState extends State<WalletDeleting> {
  final TextEditingController _passwordController = TextEditingController();
  bool _isDeleting = false;
  bool _manualPassword = false;
  bool _hasManagedCredential = false;
  Future<WalletAccessStatus?>? _accessStatus;
  String? _error;
  WalletDeletionReview? _review;
  bool _reviewReady = false;
  bool _loadingReview = false;
  bool _targetChanged = false;
  int _targetGeneration = 0;
  int _reviewGeneration = 0;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

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
    setState(() => _loadingReview = true);
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WalletAccessStatus?>(
      future: _accessStatus,
      builder: (context, snapshot) {
        _hasManagedCredential = snapshot.data?.hasManagedCredential == true;
        return ScreenshotSensitive(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.only(top: 18.0),
                  child: Text(
                    LocaleKeys.deleteWalletTitle.tr(
                      args: [widget.wallet.displayName],
                    ),
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 16),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(
                    LocaleKeys.deleteWalletInfo.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 20.0),
                  child: _DeletionRecoveryNotice(review: _review),
                ),
                if (widget.additionalWarning case final warning?)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(warning),
                  ),
                if (_loadingReview) const UiSpinner(),
                if (!_targetChanged && !_loadingReview && !_reviewReady)
                  TextButton(
                    onPressed: _loadReview,
                    child: Text(LocaleKeys.tryAgain.tr()),
                  ),
                if (_hasManagedCredential && !_manualPassword) ...[
                  const SizedBox(height: 20),
                  Text('authDeletionAuthorization'.tr()),
                  TextButton(
                    onPressed: _isDeleting
                        ? null
                        : () => setState(() => _manualPassword = true),
                    child: Text('authUsePassword'.tr()),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: _PasswordField(
                      controller: _passwordController,
                      onFieldSubmitted: _isDeleting || !_reviewReady
                          ? null
                          : _deleteWallet,
                      onChanged: _handlePasswordChanged,
                      validator: (password) {
                        if (password == null || password.isEmpty) {
                          return LocaleKeys.passwordIsEmpty.tr();
                        }
                        return null;
                      },
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 25.0),
                  child: _buildButtons(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(0),
          icon: Icon(Icons.chevron_left, color: theme.custom.headerIconColor),
          splashRadius: 15,
          iconSize: 18,
          onPressed: widget.close,
        ),
        Text(
          LocaleKeys.back.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ],
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Flexible(
          child: UiBorderButton(
            text: LocaleKeys.cancel.tr(),
            onPressed: widget.close,
            height: 40,
            width: 150,
            borderWidth: 2,
            borderColor: theme.custom.specificButtonBorderColor,
          ),
        ),
        const SizedBox(width: 8.0),
        Flexible(
          child: UiPrimaryButton(
            backgroundColor: Theme.of(context).colorScheme.error,
            text: LocaleKeys.delete.tr(),
            onPressed: _isDeleting || !_reviewReady ? null : _deleteWallet,
            prefix: _isDeleting ? const UiSpinner() : null,
            height: 40,
            width: 150,
          ),
        ),
      ],
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
    if (_isDeleting || !_reviewReady) return;
    if ((!_hasManagedCredential || _manualPassword) &&
        !(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _isDeleting = true;
      _error = null;
    });
    final walletsRepository = RepositoryProvider.of<WalletsRepository>(context);
    final wallet = widget.wallet;
    final targetGeneration = _targetGeneration;
    bool isCurrent() => mounted && targetGeneration == _targetGeneration;
    try {
      final access = context.read<WalletAccessService?>();
      final supplied = !_hasManagedCredential || _manualPassword
          ? _passwordController.text
          : null;
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
          widget.close();
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
        final messenger = ScaffoldMessenger.maybeOf(context);
        widget.close();
        messenger?.showSnackBar(
          SnackBar(content: Text('authWalletRemovedSettingsPending'.tr())),
        );
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
              widget.close();
              return;
            }
          }
        } catch (_) {
          // The original safe error remains visible when storage is unreadable.
        }
      }
      if (e is AuthException) {
        switch (e.type) {
          case AuthExceptionType.incorrectPassword:
            _error = LocaleKeys.incorrectPassword.tr();
            break;
          case AuthExceptionType.walletNotFound:
            _error = LocaleKeys.walletNotFound.tr();
            break;
          default:
            _error = e.message;
        }
      } else {
        _error = switch (e) {
          WalletAccessException(failure: WalletAccessFailure.canceled) =>
            'authUnlockCanceled'.tr(),
          WalletAccessException(
            failure: WalletAccessFailure.walletMustBeUnlocked,
          ) =>
            'authUnlockWalletBeforeDeletion'.tr(),
          _ => LocaleKeys.passwordNotAccepted.tr(),
        };
      }
    } finally {
      if (isCurrent()) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
}

class _DeletionRecoveryNotice extends StatelessWidget {
  const _DeletionRecoveryNotice({required this.review});
  final WalletDeletionReview? review;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (review?.recoveryStatus == WalletDeletionRecoveryStatus.unavailable)
        Text(LocaleKeys.walletDeletionRecoveryUnavailable.tr()),
      Text(
        LocaleKeys.walletDeletionRecoveryWarning.tr(),
        key: const Key('wallet-deletion-recovery-warning'),
      ),
      for (final transfer
          in review?.transfers ?? const <WalletDeletionTransferSummary>[])
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${transfer.requestedAmount} ${transfer.assetId}\n'
            '${transfer.destinationAddress}\n'
            '${DateFormat.yMd().add_Hm().format(transfer.acceptedAt.toLocal())}',
          ),
        ),
    ],
  );
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.onFieldSubmitted,
    required this.validator,
    this.onChanged,
  });

  final TextEditingController controller;
  final VoidCallback? onFieldSubmitted;
  final String? Function(String?) validator;
  final void Function(String?)? onChanged;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _isObscured = true;

  @override
  Widget build(BuildContext context) {
    return UiTextFormField(
      key: const Key('delete-wallet-password'),
      controller: widget.controller,
      autofocus: true,
      autocorrect: false,
      obscureText: _isObscured,
      validator: widget.validator,
      validationMode: InputValidationMode.eager,
      maxLength: passwordMaxLength,
      counterText: '',
      hintText: LocaleKeys.walletCreationPasswordHint.tr(),
      onChanged: widget.onChanged,
      suffixIcon: PasswordVisibilityControl(
        onVisibilityChange: (v) => setState(() => _isObscured = v),
      ),
      onFieldSubmitted: (_) => widget.onFieldSubmitted?.call(),
    );
  }
}
