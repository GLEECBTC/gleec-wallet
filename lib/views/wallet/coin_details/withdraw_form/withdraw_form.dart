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
import 'package:web_dex/shared/widgets/copied_text.dart' show CopiedTextV2;
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fill_form_memo.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/trezor_withdraw_progress_dialog.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/withdraw_form_header.dart';
import 'package:web_dex/views/wallet/coin_details/transactions/transaction_details.dart';

bool _isMemoSupportedProtocol(Asset asset) {
  final protocol = asset.protocol;
  return protocol is TendermintProtocol || protocol is ZhtlcProtocol;
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
  final WithdrawalPreview preview;
  final double widthThreshold;
  final double minPadding;
  final double maxPadding;

  const WithdrawPreviewDetails({
    required this.preview,
    super.key,
    this.widthThreshold = 400,
    this.minPadding = 2,
    this.maxPadding = 16,
  });

  double _calculatePadding(double width) {
    if (width >= widthThreshold) {
      return maxPadding;
    }

    // Scale padding linearly based on width below threshold
    final ratio = width / widthThreshold;
    final scaledPadding = minPadding + (maxPadding - minPadding) * ratio;

    return scaledPadding.clamp(minPadding, maxPadding);
  }

  @override
  Widget build(BuildContext context) {
    final sdk = context.sdk;

    final assets = sdk.getSdkAsset(preview.coin);
    final feeAssets = sdk.getSdkAsset(preview.fee.coin);

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = _calculatePadding(constraints.maxWidth);
        final useRowLayout = constraints.maxWidth >= widthThreshold;

        return Card(
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (useRowLayout)
                  _buildRow(
                    LocaleKeys.amount.tr(),
                    AssetAmountWithFiat(
                      assetId: assets.id,
                      // netchange for withdrawals is expected to be negative
                      // so we display the absolute value here to avoid
                      // confusion with the negative sign
                      amount: preview.balanceChanges.netChange.abs(),
                      isAutoScrollEnabled: true,
                    ),
                  )
                else ...[
                  Text(
                    LocaleKeys.amount.tr(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  AssetAmountWithFiat(
                    assetId: assets.id,
                    amount: preview.balanceChanges.netChange,
                    isAutoScrollEnabled: true,
                  ),
                ],
                const SizedBox(height: 16),
                if (useRowLayout)
                  _buildRow(
                    LocaleKeys.fee.tr(),
                    AssetAmountWithFiat(
                      assetId: feeAssets.id,
                      amount: preview.fee.totalFee,
                      isAutoScrollEnabled: true,
                    ),
                  )
                else ...[
                  Text(
                    LocaleKeys.fee.tr(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  AssetAmountWithFiat(
                    assetId: feeAssets.id,
                    amount: preview.fee.totalFee,
                    isAutoScrollEnabled: true,
                  ),
                ],
                if (preview.fee is FeeInfoTron) ...[
                  const SizedBox(height: 16),
                  _buildTronFeeDetails(
                    context,
                    preview.fee as FeeInfoTron,
                    useRowLayout: useRowLayout,
                  ),
                ],
                const SizedBox(height: 16),
                if (useRowLayout)
                  _buildRow(
                    LocaleKeys.recipientAddress.tr(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final recipient in preview.to)
                          CopiedTextV2(copiedValue: recipient, fontSize: 14),
                      ],
                    ),
                  )
                else ...[
                  Text(
                    LocaleKeys.recipientAddress.tr(),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final recipient in preview.to)
                        CopiedTextV2(copiedValue: recipient, fontSize: 14),
                    ],
                  ),
                ],
                if (preview.memo?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 16),
                  if (useRowLayout)
                    _buildRow(
                      LocaleKeys.memo.tr(),
                      Text(
                        preview.memo!,
                        textAlign: TextAlign.right,
                        softWrap: true,
                        overflow: TextOverflow.visible,
                      ),
                    )
                  else ...[
                    Text(
                      LocaleKeys.memo.tr(),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview.memo!,
                      textAlign: TextAlign.left,
                      softWrap: true,
                      overflow: TextOverflow.visible,
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTronFeeDetails(
    BuildContext context,
    FeeInfoTron fee, {
    required bool useRowLayout,
  }) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    final secondaryValueStyle = Theme.of(context).textTheme.bodySmall;
    final totalFee = fee.totalFee;
    final hasTrxFee = totalFee > Decimal.zero;
    final bandwidthUsedLabel = LocaleKeys.withdrawTronBandwidthUsed.tr();
    final bandwidthFeeLabel = LocaleKeys.withdrawTronBandwidthFee.tr();
    final bandwidthSourceLabel = LocaleKeys.withdrawTronBandwidthSource.tr();
    final energyUsedLabel = LocaleKeys.withdrawTronEnergyUsed.tr();
    final energyFeeLabel = LocaleKeys.withdrawTronEnergyFee.tr();
    final energySourceLabel = LocaleKeys.withdrawTronEnergySource.tr();
    final feeSummaryLabel = LocaleKeys.withdrawTronFeeSummary.tr();
    final paidInCoin = LocaleKeys.withdrawTronFeePaidIn.tr(args: [fee.coin]);
    final bandwidthSource = fee.bandwidthFee > Decimal.zero
        ? paidInCoin
        : LocaleKeys.withdrawTronBandwidthCovered.tr();
    final energySource = fee.energyUsed == 0
        ? LocaleKeys.withdrawTronResourceNotUsed.tr()
        : fee.energyFee > Decimal.zero
        ? paidInCoin
        : LocaleKeys.withdrawTronEnergyCovered.tr();

    final bandwidthFeeString =
        '${_formatDecimal(fee.bandwidthFee)} ${fee.coin}';
    final energyFeeString = '${_formatDecimal(fee.energyFee)} ${fee.coin}';
    final chargeSummary = hasTrxFee
        ? LocaleKeys.withdrawTronFeeSummaryCharged.tr(
            args: [_formatDecimal(totalFee), fee.coin],
          )
        : LocaleKeys.withdrawTronFeeSummaryCovered.tr(args: [fee.coin]);

    if (useRowLayout) {
      return Column(
        children: [
          _buildRow(bandwidthUsedLabel, Text('${fee.bandwidthUsed}')),
          const SizedBox(height: 8),
          _buildRow(bandwidthFeeLabel, Text(bandwidthFeeString)),
          const SizedBox(height: 8),
          _buildRow(
            bandwidthSourceLabel,
            Text(
              bandwidthSource,
              textAlign: TextAlign.right,
              style: secondaryValueStyle,
            ),
          ),
          const SizedBox(height: 8),
          _buildRow(energyUsedLabel, Text('${fee.energyUsed}')),
          const SizedBox(height: 8),
          _buildRow(energyFeeLabel, Text(energyFeeString)),
          const SizedBox(height: 8),
          _buildRow(
            energySourceLabel,
            Text(
              energySource,
              textAlign: TextAlign.right,
              style: secondaryValueStyle,
            ),
          ),
          const SizedBox(height: 8),
          _buildRow(
            feeSummaryLabel,
            Text(
              chargeSummary,
              textAlign: TextAlign.right,
              style: secondaryValueStyle,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bandwidthUsedLabel, style: labelStyle),
        const SizedBox(height: 4),
        Text('${fee.bandwidthUsed}'),
        const SizedBox(height: 8),
        Text(bandwidthFeeLabel, style: labelStyle),
        const SizedBox(height: 4),
        Text(bandwidthFeeString),
        const SizedBox(height: 8),
        Text(bandwidthSourceLabel, style: labelStyle),
        const SizedBox(height: 4),
        Text(bandwidthSource, style: secondaryValueStyle),
        const SizedBox(height: 8),
        Text(energyUsedLabel, style: labelStyle),
        const SizedBox(height: 4),
        Text('${fee.energyUsed}'),
        const SizedBox(height: 8),
        Text(energyFeeLabel, style: labelStyle),
        const SizedBox(height: 4),
        Text(energyFeeString),
        const SizedBox(height: 8),
        Text(energySourceLabel, style: labelStyle),
        const SizedBox(height: 4),
        Text(energySource, style: secondaryValueStyle),
        const SizedBox(height: 8),
        Text(feeSummaryLabel, style: labelStyle),
        const SizedBox(height: 4),
        Text(chargeSummary, style: secondaryValueStyle),
      ],
    );
  }

  String _formatDecimal(Decimal value, {int precision = 8}) {
    return value.toStringAsFixed(precision).replaceAll(RegExp(r'\.?0+$'), '');
  }

  Widget _buildRow(String label, Widget value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(label)),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Align(alignment: Alignment.centerRight, child: value),
        ),
      ],
    );
  }
}

class WithdrawResultDetails extends StatelessWidget {
  final WithdrawalResult result;

  const WithdrawResultDetails({required this.result, super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              LocaleKeys.transactionHash.tr(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SelectableText(result.txHash),
            // Add more result details as needed
          ],
        ),
      ),
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
        final isSourceInputEnabled =
            // Enabled if the asset has multiple source addresses or if there is
            // no selected address and pubkeys are available.
            (state.pubkeys?.keys.length ?? 0) > 1 ||
            (state.selectedSourceAddress == null &&
                (state.pubkeys?.isNotEmpty ?? false));

        return Column(
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
              onQrScanned: (value) => context.read<WithdrawFormBloc>().add(
                WithdrawFormRecipientChanged(value),
              ),
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
              onMaxToggled: (value) => context.read<WithdrawFormBloc>().add(
                WithdrawFormMaxAmountEnabled(value),
              ),
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
                    onChanged: (enabled) => context
                        .read<WithdrawFormBloc>()
                        .add(WithdrawFormCustomFeeEnabled(enabled ?? false)),
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
              // If the bloc has an error for custom fees:
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
                onChanged: (value) => context.read<WithdrawFormBloc>().add(
                  WithdrawFormMemoChanged(value),
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        if (state.preview == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WithdrawPreviewDetails(preview: state.preview!),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.read<WithdrawFormBloc>().add(
                      const WithdrawFormCancelled(),
                    ),
                    child: Text(LocaleKeys.back.tr()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: state.isSending
                        ? null
                        : () {
                            context.read<WithdrawFormBloc>().add(
                              const WithdrawFormSubmitted(),
                            );
                          },
                    child: state.isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(LocaleKeys.send.tr()),
                  ),
                ),
              ],
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
        // Build a temporary Transaction model matching history view expectations
        final result = state.result!;
        final tx = Transaction(
          id: result.txHash,
          internalId: result.txHash,
          assetId: state.asset.id,
          balanceChanges: result.balanceChanges,
          // Show as unconfirmed initially
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
          confirmations: 0,
          blockHeight: 0,
          from: state.selectedSourceAddress != null
              ? [state.selectedSourceAddress!.address]
              : <String>[],
          to: [result.toAddress],
          txHash: result.txHash,
          fee: result.fee,
          memo: state.memo,
        );

        return TransactionDetails(
          transaction: tx,
          coin: state.asset.toCoin(),
          onClose: onDone,
        );
      },
    );
  }
}

class WithdrawResultCard extends StatelessWidget {
  final WithdrawalResult result;
  final Asset asset;

  const WithdrawResultCard({
    required this.result,
    required this.asset,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final maybeTxEplorer = asset.protocol.explorerTxUrl(result.txHash);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHashSection(context),
            const Divider(height: 32),
            _buildNetworkSection(context),
            if (maybeTxEplorer != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => openUrl(maybeTxEplorer),
                icon: const Icon(Icons.open_in_new),
                label: Text(LocaleKeys.viewOnExplorer.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHashSection(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.transactionHash.tr(),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SelectableText(
          result.txHash,
          style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'Mono'),
        ),
      ],
    );
  }

  Widget _buildNetworkSection(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(LocaleKeys.network.tr(), style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Row(
          children: [
            AssetLogo.ofId(asset.id),
            const SizedBox(width: 8),
            Text(asset.id.name, style: theme.textTheme.bodyLarge),
          ],
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
