import 'dart:async' show Timer;

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/komodo_ui.dart';
import 'package:komodo_ui_kit/komodo_ui_kit.dart';
import 'package:web_dex/analytics/events/transaction_events.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/common/screen.dart';
import 'package:web_dex/bloc/auth_bloc/auth_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/coins_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_bloc.dart';
import 'package:web_dex/bloc/transaction_history/transaction_history_event.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/utils/extensions/kdf_user_extensions.dart';
import 'package:web_dex/shared/utils/utils.dart';
import 'package:web_dex/shared/widgets/asset_amount_with_fiat.dart';
import 'package:web_dex/shared/widgets/copied_text.dart'
    show CopiedText, CopiedTextV2;
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fill_form_memo.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/trezor_withdraw_progress_dialog.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/withdraw_form_header.dart';

bool _isMemoSupportedProtocol(Asset asset) {
  final protocol = asset.protocol;
  return protocol is TendermintProtocol || protocol is ZhtlcProtocol;
}

AssetId _resolveFeeAssetId(BuildContext context, Asset asset, FeeInfo fee) {
  if (fee.coin.isEmpty || fee.coin == asset.id.id) {
    return asset.id;
  }

  return context.sdk.getSdkAsset(fee.coin).id;
}

class WithdrawForm extends StatefulWidget {
  final Asset asset;
  final VoidCallback onSuccess;
  final VoidCallback? onBackButtonPressed;

  const WithdrawForm({
    required this.asset,
    required this.onSuccess,
    this.onBackButtonPressed,
    super.key,
  });

  @override
  State<WithdrawForm> createState() => _WithdrawFormState();
}

class _WithdrawFormState extends State<WithdrawForm> {
  late final WithdrawFormBloc _formBloc;
  late final _sdk = context.read<KomodoDefiSdk>();
  bool _suppressPreviewError = false;
  late final _mm2Api = context.read<Mm2Api>();
  Timer? _transactionRefreshTimer;

  @override
  void initState() {
    super.initState();
    final authBloc = context.read<AuthBloc>();
    final walletType = authBloc.state.currentUser?.wallet.config.type;
    _formBloc = WithdrawFormBloc(
      asset: widget.asset,
      sdk: _sdk,
      mm2Api: _mm2Api,
      walletType: walletType,
    );
  }

  @override
  void dispose() {
    _transactionRefreshTimer?.cancel();
    _formBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _formBloc,
      child: MultiBlocListener(
        listeners: [
          BlocListener<WithdrawFormBloc, WithdrawFormState>(
            listenWhen: (prev, curr) =>
                prev.previewError != curr.previewError &&
                curr.previewError != null,
            listener: (context, state) async {
              // If a preview failed and the user entered essentially their entire
              // spendable balance (but didn't select Max), offer to deduct the fee
              // by switching to max withdrawal.
              if (state.isMaxAmount) return;

              final spendable = state.selectedSourceAddress?.balance.spendable;
              Decimal? entered;
              try {
                entered = Decimal.parse(state.amount);
              } catch (_) {
                entered = null;
              }

              bool amountsMatchWithTolerance(Decimal a, Decimal b) {
                // Use a tiny epsilon to account for formatting/rounding differences
                const epsStr = '0.000000000000000001';
                final epsilon = Decimal.parse(epsStr);
                final diff = (a - b).abs();
                return diff <= epsilon;
              }

              if (spendable != null &&
                  entered != null &&
                  amountsMatchWithTolerance(entered, spendable)) {
                if (mounted) {
                  setState(() {
                    _suppressPreviewError = true;
                  });
                }
                final bloc = context.read<WithdrawFormBloc>();
                final agreed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(LocaleKeys.userActionRequired.tr()),
                    content: const Text(
                      'Since you\'re sending your full amount, the network fee will be deducted from the amount. Do you agree?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(LocaleKeys.cancel.tr()),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(LocaleKeys.ok.tr()),
                      ),
                    ],
                  ),
                );

                if (mounted) {
                  setState(() {
                    _suppressPreviewError = false;
                  });
                }

                if (agreed == true) {
                  bloc.add(const WithdrawFormMaxAmountEnabled(true));
                  bloc.add(const WithdrawFormPreviewSubmitted());
                }
              }
            },
          ),
          BlocListener<WithdrawFormBloc, WithdrawFormState>(
            listenWhen: (prev, curr) =>
                prev.step != curr.step && curr.step == WithdrawFormStep.success,
            listener: (context, state) async {
              final authBloc = context.read<AuthBloc>();
              final walletType = authBloc.state.currentUser?.type ?? '';
              context.read<AnalyticsBloc>().logEvent(
                SendSucceededEventData(
                  asset: state.asset.id.id,
                  network: state.asset.id.subClass.name,
                  amount: double.tryParse(state.amount) ?? 0.0,
                  hdType: walletType,
                ),
              );

              final coin = context
                  .read<CoinsBloc>()
                  .state
                  .coins
                  .values
                  .firstWhereOrNull((coin) => coin.id == state.asset.id);
              if (coin == null) return;

              _transactionRefreshTimer?.cancel();
              _transactionRefreshTimer = Timer(const Duration(seconds: 2), () {
                if (!mounted) return;
                if (!hasTxHistorySupport(coin)) return;
                context.read<TransactionHistoryBloc>().add(
                  TransactionHistorySubscribe(coin: coin),
                );
              });
            },
          ),
          BlocListener<WithdrawFormBloc, WithdrawFormState>(
            listenWhen: (prev, curr) =>
                prev.step != curr.step && curr.step == WithdrawFormStep.failed,
            listener: (context, state) {
              final authBloc = context.read<AuthBloc>();
              final walletType = authBloc.state.currentUser?.type ?? '';
              final reason = state.transactionError?.message ?? 'unknown';
              context.read<AnalyticsBloc>().logEvent(
                SendFailedEventData(
                  asset: state.asset.id.id,
                  network: state.asset.protocol.subClass.name,
                  failureReason: reason,
                  hdType: walletType,
                ),
              );
            },
          ),
          BlocListener<WithdrawFormBloc, WithdrawFormState>(
            listenWhen: (prev, curr) =>
                prev.isAwaitingTrezorConfirmation !=
                curr.isAwaitingTrezorConfirmation,
            listener: (context, state) {
              if (state.isAwaitingTrezorConfirmation) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => TrezorWithdrawProgressDialog(
                    message: LocaleKeys.trezorTransactionInProgressMessage.tr(),
                    onCancel: () {
                      Navigator.of(context).pop();
                      context.read<WithdrawFormBloc>().add(
                        const WithdrawFormCancelled(),
                      );
                    },
                  ),
                );
              } else {
                // Dismiss dialog if it's open
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
        ],
        child: WithdrawFormContent(
          onBackButtonPressed: widget.onBackButtonPressed,
          suppressPreviewError: _suppressPreviewError,
          onSuccess: widget.onSuccess,
        ),
      ),
    );
  }
}

class WithdrawFormContent extends StatelessWidget {
  final VoidCallback? onBackButtonPressed;
  final bool suppressPreviewError;
  final VoidCallback onSuccess;

  const WithdrawFormContent({
    required this.onSuccess,
    required this.suppressPreviewError,
    this.onBackButtonPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      buildWhen: (prev, curr) => prev.step != curr.step,
      builder: (context, state) {
        return Column(
          children: [
            WithdrawFormHeader(
              asset: state.asset,
              onBackButtonPressed: onBackButtonPressed,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: _buildStep(state.step),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStep(WithdrawFormStep step) {
    switch (step) {
      case WithdrawFormStep.fill:
        return WithdrawFormFillSection(
          suppressPreviewError: suppressPreviewError,
        );
      case WithdrawFormStep.confirm:
        return const WithdrawFormConfirmSection();
      case WithdrawFormStep.success:
        return WithdrawFormSuccessSection(onDone: onSuccess);
      case WithdrawFormStep.failed:
        return const WithdrawFormFailedSection();
    }
  }
}

class NetworkErrorDisplay extends StatelessWidget {
  final TextError error;
  final VoidCallback? onRetry;

  const NetworkErrorDisplay({required this.error, this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    return ErrorDisplay(
      message: error.message,
      icon: Icons.cloud_off,
      child: onRetry != null
          ? TextButton(
              onPressed: onRetry,
              child: Text(LocaleKeys.retryButtonText.tr()),
            )
          : null,
    );
  }
}

class TransactionErrorDisplay extends StatelessWidget {
  final TextError error;
  final VoidCallback? onDismiss;

  const TransactionErrorDisplay({
    required this.error,
    this.onDismiss,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorDisplay(
      message: error.message,
      icon: Icons.warning_amber_rounded,
      child: onDismiss != null
          ? IconButton(icon: const Icon(Icons.close), onPressed: onDismiss)
          : null,
    );
  }
}

class PreviewWithdrawButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isSending;

  const PreviewWithdrawButton({
    required this.onPressed,
    required this.isSending,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: UiPrimaryButton(
        onPressed: onPressed,
        child: isSending
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : Text(LocaleKeys.withdrawPreview.tr()),
      ),
    );
  }
}

class ZhtlcPreviewDelayNote extends StatelessWidget {
  const ZhtlcPreviewDelayNote({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = theme.colorScheme.secondaryContainer;
    final foregroundColor = theme.colorScheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: foregroundColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              LocaleKeys.withdrawPreviewZhtlcNote.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class WithdrawPreviewDetails extends StatelessWidget {
  const WithdrawPreviewDetails({required this.state, super.key});

  final WithdrawFormState state;

  @override
  Widget build(BuildContext context) {
    final preview = state.preview!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWideLayout = constraints.maxWidth >= 560;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WithdrawSectionCard(
              child: _WithdrawPreviewSummary(
                state: state,
                preview: preview,
                useWideLayout: useWideLayout,
              ),
            ),
            const SizedBox(height: 16),
            _WithdrawSectionCard(
              child: _WithdrawPreviewDestination(
                state: state,
                preview: preview,
                useWideLayout: useWideLayout,
              ),
            ),
            if (preview.fee is FeeInfoTron) ...[
              const SizedBox(height: 16),
              _WithdrawTronDetailsCard(fee: preview.fee as FeeInfoTron),
            ],
          ],
        );
      },
    );
  }
}

class _WithdrawPreviewSummary extends StatelessWidget {
  const _WithdrawPreviewSummary({
    required this.state,
    required this.preview,
    required this.useWideLayout,
  });

  final WithdrawFormState state;
  final WithdrawalPreview preview;
  final bool useWideLayout;

  Color _warningBackground(BuildContext context) {
    final theme = Theme.of(context);
    return Colors.amber.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.16,
    );
  }

  Color _warningForeground(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? Colors.amber.shade200
        : Colors.amber.shade900;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final feeAssetId = _resolveFeeAssetId(context, state.asset, preview.fee);
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );
    final amountStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.1,
    );
    final feeStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.15,
    );

    final leftContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AssetLogo.ofId(state.asset.id, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(LocaleKeys.youSend.tr(), style: labelStyle),
                  const SizedBox(height: 4),
                  Text(
                    state.asset.id.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AssetAmountWithFiat(
          assetId: state.asset.id,
          amount: preview.balanceChanges.netChange.abs(),
          style: amountStyle,
          isAutoScrollEnabled: false,
        ),
      ],
    );

    final rightContent = Container(
      width: useWideLayout ? null : double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(LocaleKeys.fee.tr(), style: labelStyle)),
              if (state.isFeePriceExpensive)
                Chip(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  label: Text(
                    LocaleKeys.withdrawHighFee.tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _warningForeground(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: _warningBackground(context),
                  side: BorderSide.none,
                ),
            ],
          ),
          const SizedBox(height: 12),
          AssetAmountWithFiat(
            assetId: feeAssetId,
            amount: preview.fee.totalFee,
            style: feeStyle,
            isAutoScrollEnabled: false,
          ),
        ],
      ),
    );

    if (!useWideLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [leftContent, const SizedBox(height: 16), rightContent],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 7, child: leftContent),
        const SizedBox(width: 16),
        Expanded(flex: 4, child: rightContent),
      ],
    );
  }
}

class _WithdrawPreviewDestination extends StatelessWidget {
  const _WithdrawPreviewDestination({
    required this.state,
    required this.preview,
    required this.useWideLayout,
  });

  final WithdrawFormState state;
  final WithdrawalPreview preview;
  final bool useWideLayout;

  Widget _buildAddressCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.primary.withValues(alpha: 0.04),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.72,
                  ),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildSourceAddress(BuildContext context) {
    final sourceAddress = state.selectedSourceAddress?.address;
    final theme = Theme.of(context);

    if (sourceAddress == null || sourceAddress.isEmpty) {
      return Text(
        state.asset.id.name,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      );
    }

    return CopiedTextV2(
      copiedValue: sourceAddress,
      fontSize: 13,
      iconSize: 14,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      textColor: theme.textTheme.bodyLarge?.color,
    );
  }

  Widget _buildRecipientAddresses(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final recipient in preview.to)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: CopiedTextV2(
              copiedValue: recipient,
              fontSize: 13,
              iconSize: 14,
              backgroundColor: theme.colorScheme.primary.withValues(
                alpha: 0.08,
              ),
              textColor: theme.textTheme.bodyLarge?.color,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destinationTitle = Text(
      LocaleKeys.withdrawDestination.tr(),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
    final routeIcon = Icon(
      useWideLayout ? Icons.arrow_forward_rounded : Icons.south_rounded,
      color: theme.colorScheme.primary,
      size: 24,
    );

    final sourceCard = _buildAddressCard(
      context,
      icon: Icons.account_balance_wallet_outlined,
      label: LocaleKeys.from.tr(),
      child: _buildSourceAddress(context),
    );
    final recipientCard = _buildAddressCard(
      context,
      icon: Icons.place_outlined,
      label: LocaleKeys.to.tr(),
      child: _buildRecipientAddresses(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        destinationTitle,
        const SizedBox(height: 16),
        if (useWideLayout)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: sourceCard),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: routeIcon,
              ),
              Expanded(child: recipientCard),
            ],
          )
        else ...[
          sourceCard,
          const SizedBox(height: 12),
          Center(child: routeIcon),
          const SizedBox(height: 12),
          recipientCard,
        ],
        if (preview.memo?.isNotEmpty ?? false) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.35,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.memo.tr(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.72,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                SelectableText(preview.memo!, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _WithdrawTronDetailsCard extends StatelessWidget {
  const _WithdrawTronDetailsCard({required this.fee});

  final FeeInfoTron fee;

  String _formatDecimal(Decimal value, {int precision = 8}) {
    return value.toStringAsFixed(precision).replaceAll(RegExp(r'\.?0+$'), '');
  }

  Widget _buildDetailRow(
    BuildContext context, {
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: valueStyle ?? theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalFee = fee.totalFee;
    final paidInCoin = LocaleKeys.withdrawTronFeePaidIn.tr(args: [fee.coin]);
    final bandwidthSource = fee.bandwidthFee > Decimal.zero
        ? paidInCoin
        : LocaleKeys.withdrawTronBandwidthCovered.tr();
    final energySource = fee.energyUsed == 0
        ? LocaleKeys.withdrawTronResourceNotUsed.tr()
        : fee.energyFee > Decimal.zero
        ? paidInCoin
        : LocaleKeys.withdrawTronEnergyCovered.tr();
    final chargeSummary = totalFee > Decimal.zero
        ? LocaleKeys.withdrawTronFeeSummaryCharged.tr(
            args: [_formatDecimal(totalFee), fee.coin],
          )
        : LocaleKeys.withdrawTronFeeSummaryCovered.tr(args: [fee.coin]);

    return Card(
      margin: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          title: Text(
            LocaleKeys.withdrawNetworkDetails.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(chargeSummary, style: theme.textTheme.bodySmall),
          ),
          children: [
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawTronBandwidthUsed.tr(),
              value: '${fee.bandwidthUsed}',
            ),
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawTronBandwidthFee.tr(),
              value: '${_formatDecimal(fee.bandwidthFee)} ${fee.coin}',
            ),
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawTronBandwidthSource.tr(),
              value: bandwidthSource,
              valueStyle: theme.textTheme.bodySmall,
            ),
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawTronEnergyUsed.tr(),
              value: '${fee.energyUsed}',
            ),
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawTronEnergyFee.tr(),
              value: '${_formatDecimal(fee.energyFee)} ${fee.coin}',
            ),
            if (fee.accountCreationFee != null)
              _buildDetailRow(
                context,
                label: LocaleKeys.withdrawTronAccountActivationFee.tr(),
                value: '${_formatDecimal(fee.accountCreationFee!)} ${fee.coin}',
              ),
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawTronEnergySource.tr(),
              value: energySource,
              valueStyle: theme.textTheme.bodySmall,
            ),
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawTronFeeSummary.tr(),
              value: chargeSummary,
              valueStyle: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _WithdrawSectionCard extends StatelessWidget {
  const _WithdrawSectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

class WithdrawFormFillSection extends StatelessWidget {
  final bool suppressPreviewError;

  const WithdrawFormFillSection({
    required this.suppressPreviewError,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        final isEditingLocked = state.isSending;
        final isSourceInputEnabled =
            // Enabled if the asset has multiple source addresses or if there is
            // no selected address and pubkeys are available.
            (state.pubkeys?.keys.length ?? 0) > 1 ||
            (state.selectedSourceAddress == null &&
                (state.pubkeys?.isNotEmpty ?? false));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IgnorePointer(
              key: const Key('withdraw-form-fill-input-lock'),
              ignoring: isEditingLocked,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SourceAddressField(
                    asset: state.asset,
                    pubkeys: state.pubkeys,
                    selectedAddress: state.selectedSourceAddress,
                    isLoading: state.pubkeys?.isEmpty ?? true,
                    onChanged: isSourceInputEnabled
                        ? (address) => address == null
                              ? null
                              : context.read<WithdrawFormBloc>().add(
                                  WithdrawFormSourceChanged(address),
                                )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  RecipientAddressWithNotification(
                    address: state.recipientAddress,
                    isMixedAddress: state.isMixedCaseAddress,
                    onChanged: (value) => context.read<WithdrawFormBloc>().add(
                      WithdrawFormRecipientChanged(value),
                    ),
                    onQrScanned: (value) => context
                        .read<WithdrawFormBloc>()
                        .add(WithdrawFormRecipientChanged(value)),
                    errorText: state.recipientAddressError == null
                        ? null
                        : () => state.recipientAddressError?.message,
                  ),
                  const SizedBox(height: 16),
                  if (state.asset.protocol is TendermintProtocol) ...[
                    const IbcTransferField(),
                    if (state.isIbcTransfer) ...[
                      const SizedBox(height: 16),
                      const IbcChannelField(),
                    ],
                    const SizedBox(height: 16),
                  ],
                  WithdrawAmountField(
                    asset: state.asset,
                    amount: state.amount,
                    isMaxAmount: state.isMaxAmount,
                    onChanged: (value) => context.read<WithdrawFormBloc>().add(
                      WithdrawFormAmountChanged(value),
                    ),
                    onMaxToggled: (value) => context
                        .read<WithdrawFormBloc>()
                        .add(WithdrawFormMaxAmountEnabled(value)),
                    amountError: state.amountError?.message,
                  ),
                  if (state.isPriorityFeeSupported) ...[
                    const SizedBox(height: 16),
                    WithdrawalPrioritySelector(
                      feeOptions: state.feeOptions,
                      selectedPriority: state.selectedFeePriority,
                      onPriorityChanged: (priority) {
                        context.read<WithdrawFormBloc>().add(
                          WithdrawFormFeePriorityChanged(priority),
                        );
                      },
                      onCustomFeeSelected: () {
                        context.read<WithdrawFormBloc>().add(
                          const WithdrawFormCustomFeeEnabled(true),
                        );
                      },
                    ),
                  ] else if (state.isCustomFeeSupported) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: state.isCustomFee,
                          onChanged: (enabled) =>
                              context.read<WithdrawFormBloc>().add(
                                WithdrawFormCustomFeeEnabled(enabled ?? false),
                              ),
                        ),
                        Text(LocaleKeys.customNetworkFee.tr()),
                      ],
                    ),
                  ],
                  if (state.isCustomFeeSupported &&
                      state.isCustomFee &&
                      state.customFee != null) ...[
                    const SizedBox(height: 8),
                    FeeInfoInput(
                      asset: state.asset,
                      selectedFee: state.customFee!,
                      isCustomFee: true, // indicates user can edit it
                      onFeeSelected: (newFee) {
                        context.read<WithdrawFormBloc>().add(
                          WithdrawFormCustomFeeChanged(newFee!),
                        );
                      },
                    ),
                    if (state.customFeeError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          state.customFeeError!.message,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  if (_isMemoSupportedProtocol(state.asset)) ...[
                    WithdrawMemoField(
                      memo: state.memo,
                      onChanged: (value) => context
                          .read<WithdrawFormBloc>()
                          .add(WithdrawFormMemoChanged(value)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            // TODO! Refactor to use Formz and replace with the appropriate
            // error state value.
            if (state.hasPreviewError && !suppressPreviewError)
              ErrorDisplay(
                message: state.previewError!.message,
                detailedMessage: state.previewError!.technicalDetails,
              ),
            const SizedBox(height: 16),
            PreviewWithdrawButton(
              onPressed: state.isSending || state.hasValidationErrors
                  ? null
                  : () {
                      final authBloc = context.read<AuthBloc>();
                      final walletType =
                          authBloc.state.currentUser?.wallet.config.type.name ??
                          '';
                      context.read<AnalyticsBloc>().logEvent(
                        SendInitiatedEventData(
                          asset: state.asset.id.id,
                          network: state.asset.protocol.subClass.name,
                          amount: double.tryParse(state.amount) ?? 0.0,
                          hdType: walletType,
                        ),
                      );
                      context.read<WithdrawFormBloc>().add(
                        const WithdrawFormPreviewSubmitted(),
                      );
                    },
              isSending: state.isSending,
            ),
            if (state.asset.id.subClass == CoinSubClass.zhtlc &&
                state.isSending) ...[
              const SizedBox(height: 12),
              const ZhtlcPreviewDelayNote(),
            ],
          ],
        );
      },
    );
  }
}

class WithdrawFormConfirmSection extends StatelessWidget {
  const WithdrawFormConfirmSection({super.key});

  Color _warningBackground(BuildContext context) {
    final theme = Theme.of(context);
    return Colors.amber.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.22 : 0.16,
    );
  }

  Color _warningForeground(BuildContext context) {
    final theme = Theme.of(context);
    return theme.brightness == Brightness.dark
        ? Colors.amber.shade200
        : Colors.amber.shade900;
  }

  Widget? _buildStatusBanner(BuildContext context, WithdrawFormState state) {
    if (!state.isTronAsset &&
        !state.isPreviewRefreshing &&
        state.confirmStepError == null) {
      return null;
    }

    final theme = Theme.of(context);
    late final Color backgroundColor;
    late final Color foregroundColor;
    late final IconData icon;
    late final String message;
    final showSpinner = state.isPreviewRefreshing;

    if (state.isPreviewRefreshing) {
      backgroundColor = theme.colorScheme.secondaryContainer;
      foregroundColor = theme.colorScheme.onSecondaryContainer;
      icon = Icons.refresh_rounded;
      message = LocaleKeys.withdrawPreviewRefreshing.tr();
    } else if (state.confirmStepError != null || state.isPreviewExpired) {
      backgroundColor = theme.colorScheme.errorContainer;
      foregroundColor = theme.colorScheme.onErrorContainer;
      icon = Icons.warning_amber_rounded;
      message =
          state.confirmStepError?.message ??
          LocaleKeys.withdrawTronPreviewExpired.tr();
    } else if (state.previewSecondsRemaining != null) {
      final isExpiringSoon = state.previewSecondsRemaining! <= 10;
      backgroundColor = isExpiringSoon
          ? _warningBackground(context)
          : theme.colorScheme.primaryContainer;
      foregroundColor = isExpiringSoon
          ? _warningForeground(context)
          : theme.colorScheme.onPrimaryContainer;
      icon = Icons.schedule_rounded;
      message = LocaleKeys.withdrawPreviewExpiresIn.tr(
        args: [state.previewSecondsRemaining.toString()],
      );
    } else {
      return null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (showSpinner)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foregroundColor,
              ),
            )
          else
            Icon(icon, color: foregroundColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context, {
    required WithdrawFormState state,
    required bool hasExpiredPreviewAction,
    required bool isSubmitDisabled,
  }) {
    final backButton = OutlinedButton(
      onPressed: state.isSending || state.isPreviewRefreshing
          ? null
          : () => context.read<WithdrawFormBloc>().add(
              const WithdrawFormStepReverted(),
            ),
      child: Text(LocaleKeys.back.tr()),
    );
    final primaryButton = FilledButton(
      onPressed: hasExpiredPreviewAction
          ? () {
              context.read<WithdrawFormBloc>().add(
                const WithdrawFormTronPreviewRefreshRequested(),
              );
            }
          : isSubmitDisabled
          ? null
          : () {
              context.read<WithdrawFormBloc>().add(
                const WithdrawFormSubmitted(),
              );
            },
      child: state.isSending || state.isPreviewRefreshing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              hasExpiredPreviewAction
                  ? LocaleKeys.withdrawTronPreviewRegenerate.tr()
                  : LocaleKeys.send.tr(),
            ),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primaryButton, const SizedBox(height: 12), backButton],
      );
    }

    return Row(
      children: [
        Expanded(child: backButton),
        const SizedBox(width: 16),
        Expanded(child: primaryButton),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        if (state.preview == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final hasExpiredPreviewAction =
            state.isTronAsset &&
            !state.isPreviewRefreshing &&
            (state.isPreviewExpired || state.hasConfirmStepError);
        final isSubmitDisabled =
            state.isSending ||
            state.isPreviewRefreshing ||
            (state.isTronAsset &&
                (state.previewSecondsRemaining == null ||
                    state.previewSecondsRemaining == 0));
        final statusBanner = _buildStatusBanner(context, state);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WithdrawPreviewDetails(state: state),
            if (statusBanner != null) ...[
              const SizedBox(height: 16),
              statusBanner,
            ],
            const SizedBox(height: 24),
            _buildActions(
              context,
              state: state,
              hasExpiredPreviewAction: hasExpiredPreviewAction,
              isSubmitDisabled: isSubmitDisabled,
            ),
          ],
        );
      },
    );
  }
}

class WithdrawFormSuccessSection extends StatelessWidget {
  final VoidCallback onDone;

  const WithdrawFormSuccessSection({required this.onDone, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        final result = state.result!;

        return WithdrawSuccessReceipt(
          asset: state.asset,
          result: result,
          sourceAddress: state.selectedSourceAddress?.address,
          memo: state.memo,
          onClose: onDone,
        );
      },
    );
  }
}

class WithdrawSuccessReceipt extends StatelessWidget {
  const WithdrawSuccessReceipt({
    required this.asset,
    required this.result,
    required this.onClose,
    this.sourceAddress,
    this.memo,
    super.key,
  });

  final Asset asset;
  final WithdrawalResult result;
  final String? sourceAddress;
  final String? memo;
  final VoidCallback onClose;

  Widget _buildActions(BuildContext context, Uri? explorerUrl) {
    final doneButton = explorerUrl == null
        ? FilledButton(onPressed: onClose, child: Text(LocaleKeys.done.tr()))
        : OutlinedButton(onPressed: onClose, child: Text(LocaleKeys.done.tr()));

    if (explorerUrl == null) {
      return SizedBox(width: double.infinity, child: doneButton);
    }

    final explorerButton = FilledButton.icon(
      onPressed: () => openUrl(explorerUrl),
      icon: const Icon(Icons.open_in_new_rounded),
      label: Text(LocaleKeys.viewOnExplorer.tr()),
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [explorerButton, const SizedBox(height: 12), doneButton],
      );
    }

    return Row(
      children: [
        Expanded(child: explorerButton),
        const SizedBox(width: 16),
        Expanded(child: doneButton),
      ],
    );
  }

  Widget _buildDetailItem(
    BuildContext context, {
    required String label,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.72),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final explorerUrl = asset.protocol.explorerTxUrl(result.txHash);
    final feeAssetId = _resolveFeeAssetId(context, asset, result.fee);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WithdrawSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.check_circle_rounded,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                LocaleKeys.successPageHeadline.tr(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              AssetLogo.ofId(asset.id, size: 52),
              const SizedBox(height: 12),
              Center(
                child: AssetAmountWithFiat(
                  assetId: asset.id,
                  amount: result.amount,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                  isAutoScrollEnabled: false,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                asset.id.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  LocaleKeys.recipientAddress.tr(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.72,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: CopiedTextV2(
                  copiedValue: result.toAddress,
                  fontSize: 13,
                  iconSize: 14,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.08,
                  ),
                  textColor: theme.textTheme.bodyLarge?.color,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  padding: EdgeInsets.zero,
                  avatar: Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                  label: Text(
                    LocaleKeys.withdrawAwaitingConfirmations.tr(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  side: BorderSide.none,
                ),
              ),
              const SizedBox(height: 24),
              _buildActions(context, explorerUrl),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              title: Text(
                LocaleKeys.technicalDetails.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              children: [
                _buildDetailItem(
                  context,
                  label: LocaleKeys.transactionHash.tr(),
                  child: CopiedText(
                    copiedValue: result.txHash,
                    isTruncated: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                if (sourceAddress?.isNotEmpty ?? false)
                  _buildDetailItem(
                    context,
                    label: LocaleKeys.from.tr(),
                    child: CopiedText(
                      copiedValue: sourceAddress!,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                _buildDetailItem(
                  context,
                  label: LocaleKeys.to.tr(),
                  child: CopiedText(
                    copiedValue: result.toAddress,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
                _buildDetailItem(
                  context,
                  label: LocaleKeys.fee.tr(),
                  child: AssetAmountWithFiat(
                    assetId: feeAssetId,
                    amount: result.fee.totalFee,
                    isAutoScrollEnabled: false,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (memo?.isNotEmpty ?? false)
                  _buildDetailItem(
                    context,
                    label: LocaleKeys.memo.tr(),
                    child: SelectableText(
                      memo!,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                _buildDetailItem(
                  context,
                  label: LocaleKeys.network.tr(),
                  child: Row(
                    children: [
                      AssetLogo.ofId(asset.id, size: 28),
                      const SizedBox(width: 10),
                      Text(
                        asset.id.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class WithdrawFormFailedSection extends StatelessWidget {
  const WithdrawFormFailedSection({super.key});

  static Future<void> _openSupportContact() async {
    try {
      await openUrl(discordInviteUrl);
    } catch (_) {
      // Avoid surfacing launch failures as another error state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        final supportLink = TextButton(
          onPressed: _openSupportContact,
          child: Text(LocaleKeys.support.tr()),
        );

        final backButton = OutlinedButton(
          onPressed: () => context.read<WithdrawFormBloc>().add(
            const WithdrawFormStepReverted(),
          ),
          child: Text(LocaleKeys.back.tr()),
        );

        final tryAgainButton = FilledButton(
          onPressed: () =>
              context.read<WithdrawFormBloc>().add(const WithdrawFormReset()),
          child: Text(LocaleKeys.tryAgainButton.tr()),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              LocaleKeys.transactionFailed.tr(),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (state.transactionError != null)
              WithdrawErrorCard(error: state.transactionError!),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                LocaleKeys.errorTryAgainSupportHint.tr(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            if (isMobile) ...[
              backButton,
              const SizedBox(height: 12),
              tryAgainButton,
              const SizedBox(height: 8),
              Center(child: supportLink),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: backButton),
                  const SizedBox(width: 16),
                  Expanded(child: tryAgainButton),
                ],
              ),
              const SizedBox(height: 12),
              Center(child: supportLink),
            ],
          ],
        );
      },
    );
  }
}

class WithdrawErrorCard extends StatelessWidget {
  final BaseError error;

  const WithdrawErrorCard({required this.error, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final rawDetails = error is TextError
        ? (error as TextError).technicalDetails
        : null;
    final hasDistinctDetails =
        rawDetails != null && rawDetails != error.message;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              LocaleKeys.errorDetails.tr(),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(error.message, style: theme.textTheme.bodyMedium),
            if (hasDistinctDetails) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              ExpansionTile(
                title: Text(LocaleKeys.technicalDetails.tr()),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(
                      rawDetails,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'Mono',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows a temporary notification when the address is converted to mixed case.
/// This is to avoid confusion for users when the auto-conversion happens.
/// The notification will be shown for a short duration and then fade out.
class RecipientAddressWithNotification extends StatefulWidget {
  final String address;
  final bool isMixedAddress;
  final Duration notificationDuration;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onQrScanned;
  final String? Function()? errorText;

  const RecipientAddressWithNotification({
    required this.address,
    required this.onChanged,
    required this.onQrScanned,
    required this.isMixedAddress,
    this.notificationDuration = const Duration(seconds: 10),
    this.errorText,
    super.key,
  });

  @override
  State<RecipientAddressWithNotification> createState() =>
      _RecipientAddressWithNotificationState();
}

class _RecipientAddressWithNotificationState
    extends State<RecipientAddressWithNotification> {
  bool _showNotification = false;
  Timer? _notificationTimer;

  @override
  void didUpdateWidget(RecipientAddressWithNotification oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMixedAddress && !oldWidget.isMixedAddress) {
      _showTemporaryNotification();
    } else if (!widget.isMixedAddress) {
      setState(() {
        _showNotification = false;
      });
    }
  }

  void _showTemporaryNotification() {
    _notificationTimer?.cancel();
    setState(() {
      _showNotification = true;
    });

    _notificationTimer = Timer(widget.notificationDuration, () {
      if (mounted) {
        setState(() {
          _showNotification = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RecipientAddressField(
          address: widget.address,
          onChanged: widget.onChanged,
          onQrScanned: widget.onQrScanned,
          errorText: widget.errorText,
        ),
        if (_showNotification)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: 1.0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  LocaleKeys.addressConvertedToMixedCase.tr(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
