part of 'gnosis_onboarding_steps.dart';

class GnosisPhysicalReviewStep extends StatelessWidget {
  const GnosisPhysicalReviewStep({
    required this.order,
    required this.busy,
    required this.onConfirm,
    required this.onEdit,
    required this.onCancel,
    this.error,
    super.key,
  });

  final PhysicalCardOrder order;
  final bool busy;
  final String? error;
  final VoidCallback onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GnosisStepHeader(
          icon: Icons.receipt_long_outlined,
          title: LocaleKeys.gnosisCard_order_reviewTitle.tr(),
          body: LocaleKeys.gnosisCard_order_reviewBody.tr(),
        ),
        const SizedBox(height: 24),
        _OrderSummary(order: order),
        if (error != null) ...[
          const SizedBox(height: 16),
          GnosisServerErrorBanner(message: error!),
        ],
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('gnosis-order-review-confirm'),
          text: LocaleKeys.gnosisCard_order_placeOrder.tr(),
          onPressed: busy ? null : onConfirm,
        ),
        const SizedBox(height: 12),
        GnosisResponsiveActions(
          primary: UiSecondaryButton(
            text: LocaleKeys.gnosisCard_edit.tr(),
            onPressed: busy ? null : onEdit,
          ),
          secondary: TextButton(
            onPressed: busy || !order.isCancellable
                ? null
                : () => _confirmOrderCancellation(context, onCancel),
            child: Text(LocaleKeys.gnosisCard_order_cancel.tr()),
          ),
        ),
      ],
    ),
  );
}

class GnosisPhysicalPaymentStep extends StatelessWidget {
  const GnosisPhysicalPaymentStep({
    required this.order,
    required this.quote,
    required this.busy,
    required this.onPay,
    required this.onConfirm,
    required this.onCancel,
    this.receipt,
    this.error,
    super.key,
  });

  final PhysicalCardOrder order;
  final CardOrderPaymentQuote? quote;
  final CardOrderPaymentReceipt? receipt;
  final bool busy;
  final String? error;
  final VoidCallback onPay;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final hasAttachedPayment =
        order.status != PhysicalCardOrderStatus.failedTransaction &&
        (receipt != null ||
            order.transactionHash != null ||
            order.status == PhysicalCardOrderStatus.transactionComplete ||
            order.status == PhysicalCardOrderStatus.confirmationRequired);
    return GnosisStepCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GnosisStepHeader(
            icon: Icons.account_balance_wallet_outlined,
            title: LocaleKeys.gnosisCard_payment_title.tr(),
            body: LocaleKeys.gnosisCard_payment_warningBody.tr(),
          ),
          const SizedBox(height: 20),
          GnosisStatusBanner(
            title: LocaleKeys.gnosisCard_payment_warningTitle.tr(),
            message: LocaleKeys.gnosisCard_payment_warningBody.tr(),
            icon: Icons.verified_user_outlined,
          ),
          const SizedBox(height: 16),
          _SummaryRow(
            label: LocaleKeys.gnosisCard_payment_amount.tr(),
            value: quote == null
                ? _money(context, order.feeMinor, order.currency)
                : _money(context, quote!.amountMinor, quote!.currency),
          ),
          if (receipt != null || order.transactionHash != null) ...[
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('gnosisCard.dashboard.technicalDetails'.tr()),
              children: [
                _SummaryRow(
                  label: LocaleKeys.gnosisCard_payment_receipt.tr(),
                  value: _shortHash(
                    receipt?.transactionHash ?? order.transactionHash!,
                  ),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            GnosisServerErrorBanner(message: error!),
          ],
          const SizedBox(height: 24),
          if (hasAttachedPayment && error == null)
            GnosisProgressIndicator(
              label: LocaleKeys.gnosisCard_payment_title.tr(),
            )
          else
            UiPrimaryButton(
              key: const Key('gnosis-payment-submit'),
              text: error == null
                  ? LocaleKeys.gnosisCard_payment_pay.tr()
                  : LocaleKeys.gnosisCard_payment_retry.tr(),
              onPressed: busy
                  ? null
                  : hasAttachedPayment
                  ? onConfirm
                  : onPay,
            ),
          if (order.isCancellable) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy
                  ? null
                  : () => _confirmOrderCancellation(context, onCancel),
              child: Text(LocaleKeys.gnosisCard_order_cancel.tr()),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _confirmOrderCancellation(
  BuildContext context,
  VoidCallback onConfirm,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('gnosisCard.order.cancelTitle'.tr()),
      content: Text('gnosisCard.order.cancelBody'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text('gnosisCard.order.keep'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text('gnosisCard.order.confirmCancel'.tr()),
        ),
      ],
    ),
  );
  if (confirmed == true) onConfirm();
}

class GnosisPhysicalCreationStep extends StatelessWidget {
  const GnosisPhysicalCreationStep({
    required this.busy,
    required this.onCreate,
    this.error,
    super.key,
  });

  final bool busy;
  final String? error;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GnosisStepHeader(
          icon: Icons.credit_card_outlined,
          title: LocaleKeys.gnosisCard_product_physicalTitle.tr(),
          body: LocaleKeys.gnosisCard_product_physicalBody.tr(),
        ),
        if (error != null) ...[
          const SizedBox(height: 20),
          GnosisServerErrorBanner(message: error!),
        ],
        const SizedBox(height: 24),
        if (error == null || busy)
          GnosisProgressIndicator(
            label: LocaleKeys.gnosisCard_product_physicalTitle.tr(),
          )
        else
          UiPrimaryButton(
            key: const Key('gnosis-physical-create'),
            text: LocaleKeys.gnosisCard_retrySafely.tr(),
            onPressed: onCreate,
          ),
      ],
    ),
  );
}

class GnosisPhysicalPinStep extends StatelessWidget {
  const GnosisPhysicalPinStep({
    required this.busy,
    required this.onOpen,
    this.wasHandoffCancelled = false,
    this.error,
    super.key,
  });

  final bool busy;
  final bool wasHandoffCancelled;
  final String? error;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => GnosisStepCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GnosisStepHeader(
          icon: Icons.pin_outlined,
          title: LocaleKeys.gnosisCard_pin_title.tr(),
          body: LocaleKeys.gnosisCard_pin_body.tr(),
        ),
        if (wasHandoffCancelled) ...[
          const SizedBox(height: 20),
          GnosisStatusBanner(
            title: LocaleKeys.gnosisCard_order_resumePin.tr(),
            message: LocaleKeys.gnosisCard_pin_cancelled.tr(),
            icon: Icons.restore,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 20),
          GnosisServerErrorBanner(message: error!),
        ],
        const SizedBox(height: 24),
        UiPrimaryButton(
          key: const Key('gnosis-pin-open'),
          text: LocaleKeys.gnosisCard_pin_open.tr(),
          onPressed: busy ? null : onOpen,
        ),
      ],
    ),
  );
}

class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.order});

  final PhysicalCardOrder order;

  @override
  Widget build(BuildContext context) {
    final address = order.shippingAddress;
    final addressLines = [
      address.address1,
      if ((address.address2 ?? '').isNotEmpty) address.address2!,
      '${address.postalCode} ${address.city}',
      'gnosisCard.countries.${address.country}'.tr(),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: _gnosisBorderColor(context)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow(
            label: LocaleKeys.gnosisCard_order_shippingTo.tr(),
            value: '${order.embossedName}\n${addressLines.join('\n')}',
          ),
          const SizedBox(height: 12),
          _SummaryRow(
            label: LocaleKeys.gnosisCard_order_cardFee.tr(),
            value: _money(context, order.feeMinor, order.currency),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stack =
          constraints.maxWidth < 480 ||
          MediaQuery.textScalerOf(context).scale(1) >= 1.4;
      final valueText = Text(
        value,
        textAlign: stack ? TextAlign.start : TextAlign.end,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      );
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Text(label), const SizedBox(height: 4), valueText],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Expanded(child: valueText),
        ],
      );
    },
  );
}

String _safeStatusLabel(SafeDeploymentStatus status) => switch (status) {
  SafeDeploymentStatus.accepted => LocaleKeys.gnosisCard_safe_accepted.tr(),
  SafeDeploymentStatus.processing => LocaleKeys.gnosisCard_safe_processing.tr(),
  SafeDeploymentStatus.ok => LocaleKeys.gnosisCard_safe_ready.tr(),
  SafeDeploymentStatus.failed => LocaleKeys.gnosisCard_safe_failed.tr(),
  SafeDeploymentStatus.timedOut => LocaleKeys.gnosisCard_safe_timeout.tr(),
};

String _safeStatusBody(SafeDeploymentStatus status) => switch (status) {
  SafeDeploymentStatus.accepted => LocaleKeys.gnosisCard_safe_accepted.tr(),
  SafeDeploymentStatus.processing => LocaleKeys.gnosisCard_safe_processing.tr(),
  SafeDeploymentStatus.ok => LocaleKeys.gnosisCard_safe_configuration.tr(),
  SafeDeploymentStatus.failed => LocaleKeys.gnosisCard_safe_failed.tr(),
  SafeDeploymentStatus.timedOut => LocaleKeys.gnosisCard_safe_timeout.tr(),
};

String _shortAddress(String? value) {
  if (value == null || value.length < 14) return value ?? '—';
  return '${value.substring(0, 8)}…${value.substring(value.length - 6)}';
}

String _shortHash(String value) {
  if (value.length < 18) return value;
  return '${value.substring(0, 10)}…${value.substring(value.length - 8)}';
}

String _money(BuildContext context, int minor, String currency) =>
    NumberFormat.simpleCurrency(
      name: currency,
      locale: context.locale.toString(),
    ).format(minor / 100);

String? _emptyAsNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

Color _gnosisBorderColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFB8ADBF)
    : const Color(0xFF64798C);
