part of 'wallet_deleting.dart';

/// Room above and below a label that wraps at large text sizes.
const _removalButtonPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);

/// Outlined buttons shaped and lettered like the kit buttons beside them.
ButtonStyle _removalOutlinedStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      padding: _removalButtonPadding,
      foregroundColor: Theme.of(context).colorScheme.onSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      // From the theme, so the label keeps the app's typeface.
      textStyle: Theme.of(context).textTheme.labelLarge
          ?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
    );

/// Chevron and word are one control, so the visible label is the tap target.
class _RemovalBackControl extends StatelessWidget {
  const _RemovalBackControl({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton.icon(
      key: const Key('wallet-removal-back'),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsetsDirectional.only(end: 12),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        textStyle: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w600, fontSize: 16),
      ),
      onPressed: onPressed,
      icon: Icon(Icons.chevron_left, color: theme.custom.headerIconColor),
      label: Text(LocaleKeys.back.tr()),
    ),
  );
}

class _RemovalTextAction extends StatelessWidget {
  const _RemovalTextAction({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      foregroundColor: Theme.of(context).colorScheme.onSurface,
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}

class _RemovalAcknowledgement extends StatelessWidget {
  const _RemovalAcknowledgement({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const Key('wallet-removal-acknowledge'),
    checked: value,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: UiCheckbox(
        value: value,
        text: 'authRemoveWalletAcknowledge'.tr(),
        textColor: Theme.of(context).colorScheme.onSurface,
        onChanged: onChanged,
      ),
    ),
  );
}

/// The one control that removes the wallet. Filled only when removal is the
/// expected outcome of the review; outlined when a safer action leads.
class _RemoveWalletButton extends StatelessWidget {
  const _RemoveWalletButton({required this.onPressed, required this.filled});
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = 'authRemoveWalletConfirm'.tr();
    if (filled) {
      return UiPrimaryButton(
        key: const Key('wallet-removal-confirm'),
        expandForText: true,
        height: 48,
        padding: _removalButtonPadding,
        backgroundColor: scheme.error,
        text: label,
        onPressed: onPressed,
      );
    }
    Color whenEnabled(Set<WidgetState> states, Color color, double disabled) =>
        states.contains(WidgetState.disabled)
        ? scheme.onSurface.withValues(alpha: disabled)
        : color;
    return OutlinedButton.icon(
      key: const Key('wallet-removal-confirm'),
      // The label keeps full contrast; border and icon carry the danger.
      style: _removalOutlinedStyle(context).copyWith(
        iconColor: WidgetStateProperty.resolveWith(
          (states) => whenEnabled(states, scheme.error, 0.38),
        ),
        side: WidgetStateProperty.resolveWith(
          (states) =>
              BorderSide(color: whenEnabled(states, scheme.error, 0.12)),
        ),
      ),
      onPressed: onPressed,
      icon: const Icon(Icons.delete_outline),
      label: Text(label),
    );
  }
}

/// Transfers the wallet already handed to the network. Removing the wallet
/// does not cancel them, so each one is listed before the user confirms.
class _PendingTransfers extends StatelessWidget {
  const _PendingTransfers({required this.review});
  final WalletDeletionReview? review;

  @override
  Widget build(BuildContext context) {
    final review = this.review;
    if (review == null ||
        review.recoveryStatus == WalletDeletionRecoveryStatus.none) {
      return const SizedBox.shrink();
    }
    // Supporting size throughout: this section informs the decision, it must
    // not outweigh the backup warning above it.
    final supporting = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurface);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (review.transfers.isNotEmpty) ...[
            Semantics(
              header: true,
              child: Text(
                'authRemoveWalletPendingTransfers'.tr(),
                style: supporting?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final transfer in review.transfers)
              _PendingTransferRow(transfer: transfer, style: supporting),
            const SizedBox(height: 8),
          ],
          if (review.recoveryStatus == WalletDeletionRecoveryStatus.unavailable)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                LocaleKeys.walletDeletionRecoveryUnavailable.tr(),
                style: supporting?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          Text(
            LocaleKeys.walletDeletionRecoveryWarning.tr(),
            key: const Key('wallet-deletion-recovery-warning'),
            style: supporting,
          ),
        ],
      ),
    );
  }
}

class _PendingTransferRow extends StatelessWidget {
  const _PendingTransferRow({required this.transfer, required this.style});
  final WalletDeletionTransferSummary transfer;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${transfer.requestedAmount} ${transfer.assetId}',
              style: style?.copyWith(fontWeight: FontWeight.w600),
            ),
            // Label and address stay separate strings: the address must show
            // even where a translation has no slot for it.
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '${'authTransferRecipientLabel'.tr()} '),
                  TextSpan(text: transfer.destinationAddress),
                ],
              ),
              style: style,
            ),
            Text(
              DateFormat.yMMMd().add_Hm().format(transfer.acceptedAt.toLocal()),
              style: style,
            ),
          ],
        ),
      ),
    );
  }
}

class _RemovalPasswordField extends StatefulWidget {
  const _RemovalPasswordField({
    required this.walletName,
    required this.controller,
    required this.onFieldSubmitted,
    required this.validator,
    this.onChanged,
  });

  final String walletName;
  final TextEditingController controller;
  final VoidCallback onFieldSubmitted;
  final String? Function(String?) validator;
  final void Function(String?)? onChanged;

  @override
  State<_RemovalPasswordField> createState() => _RemovalPasswordFieldState();
}

class _RemovalPasswordFieldState extends State<_RemovalPasswordField>
    with WidgetsBindingObserver {
  bool _isObscured = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => _isObscured = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      onDisposeAction: AutofillContextAction.cancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lets a password manager match this wallet without showing a field.
          Offstage(
            child: ExcludeFocus(
              child: UiTextFormField(
                // Rebuilt, not updated, for another wallet: the kit field
                // rewrites its controller mid-build when the value changes.
                key: ValueKey(widget.walletName),
                initialValue: widget.walletName,
                readOnly: true,
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                autofillHints: const [AutofillHints.username],
              ),
            ),
          ),
          UiTextFormField(
            key: const Key('delete-wallet-password'),
            controller: widget.controller,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            obscureText: _isObscured,
            validator: widget.validator,
            validationMode: InputValidationMode.eager,
            maxLength: passwordMaxLength,
            counterText: '',
            hintText: LocaleKeys.walletCreationPasswordHint.tr(),
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onChanged: widget.onChanged,
            suffixIcon: PasswordVisibilityControl(
              isObscured: _isObscured,
              onVisibilityChange: (v) => setState(() => _isObscured = v),
            ),
            onFieldSubmitted: (_) => widget.onFieldSubmitted(),
          ),
        ],
      ),
    );
  }
}
