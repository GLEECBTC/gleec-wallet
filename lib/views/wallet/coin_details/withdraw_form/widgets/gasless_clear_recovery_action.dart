import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';

/// Requires explicit acknowledgement before forgetting an unknown transfer.
/// The callback is bound to the transfer shown when the dialog was opened.
class GaslessClearRecoveryAction extends StatelessWidget {
  const GaslessClearRecoveryAction({
    required this.recipientAddress,
    required this.amount,
    required this.assetName,
    required this.isBusy,
    required this.onConfirmed,
    this.submittedAt,
    super.key,
  });

  final String recipientAddress;
  final String amount;
  final String assetName;
  final DateTime? submittedAt;
  final bool isBusy;
  final VoidCallback onConfirmed;

  Future<void> _confirm(BuildContext context) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => _ClearRecoveryDialog(
        recipientAddress: recipientAddress,
        amount: amount,
        assetName: assetName,
        submittedAt: submittedAt,
      ),
    );
    if (approved == true && context.mounted) onConfirmed();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('withdraw-gasless-clear-recovery'),
    onPressed: isBusy ? null : () => _confirm(context),
    child: Text(
      LocaleKeys.withdrawGaslessClearRecoveryAction.tr(),
      textAlign: TextAlign.center,
    ),
  );
}

class _ClearRecoveryDialog extends StatefulWidget {
  const _ClearRecoveryDialog({
    required this.recipientAddress,
    required this.amount,
    required this.assetName,
    required this.submittedAt,
  });

  final String recipientAddress;
  final String amount;
  final String assetName;
  final DateTime? submittedAt;

  @override
  State<_ClearRecoveryDialog> createState() => _ClearRecoveryDialogState();
}

class _ClearRecoveryDialogState extends State<_ClearRecoveryDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final submittedAt = widget.submittedAt?.toLocal();
    final localizations = MaterialLocalizations.of(context);
    return AlertDialog(
      scrollable: true,
      title: Text(LocaleKeys.withdrawGaslessClearRecoveryTitle.tr()),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(LocaleKeys.withdrawGaslessClearRecoveryWarning.tr()),
          const SizedBox(height: 20),
          _TransferDetail(
            label: LocaleKeys.recipientAddress.tr(),
            value: widget.recipientAddress,
          ),
          _TransferDetail(label: LocaleKeys.amount.tr(), value: widget.amount),
          _TransferDetail(
            label: LocaleKeys.asset.tr(),
            value: widget.assetName,
          ),
          if (submittedAt != null)
            _TransferDetail(
              label: LocaleKeys.withdrawGaslessClearRecoverySubmittedAt.tr(),
              value:
                  '${localizations.formatFullDate(submittedAt)}, '
                  '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(submittedAt))}',
            ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const Key('withdraw-gasless-clear-recovery-acknowledgement'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _acknowledged,
            onChanged: (value) =>
                setState(() => _acknowledged = value ?? false),
            title: Text(
              LocaleKeys.withdrawGaslessClearRecoveryAcknowledgement.tr(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('withdraw-gasless-clear-recovery-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(LocaleKeys.cancel.tr()),
        ),
        FilledButton(
          key: const Key('withdraw-gasless-clear-recovery-confirm'),
          onPressed: _acknowledged
              ? () => Navigator.of(context).pop(true)
              : null,
          child: Text(LocaleKeys.withdrawGaslessClearRecoveryAction.tr()),
        ),
      ],
    );
  }
}

class _TransferDetail extends StatelessWidget {
  const _TransferDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SelectableText(value),
      ],
    ),
  );
}
