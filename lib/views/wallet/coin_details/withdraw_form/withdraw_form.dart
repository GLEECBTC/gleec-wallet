import 'dart:async' show Timer;
import 'dart:convert' show jsonEncode;

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
import 'package:web_dex/shared/widgets/gasless_info_dialog.dart';
import 'package:web_dex/shared/widgets/notice_banner.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fields.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/fill_form/fields/fill_form_memo.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/gasless_balance_breakdown.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/gasless_pending_transfer_panel.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/trezor_withdraw_progress_dialog.dart';
import 'package:web_dex/views/wallet/coin_details/withdraw_form/widgets/withdraw_form_header.dart';

bool _isMemoSupportedProtocol(Asset asset) {
  final protocol = asset.protocol;
  return protocol is TendermintProtocol || protocol is ZhtlcProtocol;
}

bool _shouldStackWithdrawActions(BuildContext context, double maxWidth) {
  return maxWidth < 480 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
}

AssetId _resolveFeeAssetId(BuildContext context, Asset asset, FeeInfo fee) {
  if (fee.coin.isEmpty || fee.coin == asset.id.id) {
    return asset.id;
  }

  return context.sdk.getSdkAsset(fee.coin).id;
}

/// The address a withdrawal is presented as sending FROM.
///
/// For a gas-free send this is the GasFree custody address — the address the
/// tokens actually settle from and the one a block explorer shows — matching
/// the source selector, where the custody address is the selected entry. KDF
/// itself reports `from` as the signing (standard) address, but showing that
/// here read as a mismatch against the on-chain transfer. Native sends keep
/// the signing address.
String? _effectiveWithdrawSourceAddress(WithdrawFormState state) {
  if (state.useGasless) {
    final custody =
        state.gaslessAccountStatus?.gasfreeAddress ??
        state.selectedSourceAddress?.gasfreeAddress;
    if (custody != null && custody.isNotEmpty) return custody;
  }
  return state.selectedSourceAddress?.address;
}

Future<void> _openGaslessSupportContact(
  BuildContext context,
  WithdrawFormState state,
) async {
  final hasGaslessContext =
      state.gaslessTransferState != null || state.gaslessTraceId != null;
  if (!hasGaslessContext) {
    try {
      await openUrl(discordInviteUrl);
    } catch (_) {
      // A support-launch failure must not replace the transfer result.
    }
    return;
  }

  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(LocaleKeys.withdrawGaslessSupportDiagnosticsTitle.tr()),
      content: Text(LocaleKeys.withdrawGaslessSupportDiagnosticsBody.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(LocaleKeys.cancel.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(LocaleKeys.withdrawGaslessSupportDiagnosticsAction.tr()),
        ),
      ],
    ),
  );
  if (approved != true || !context.mounted) return;

  final diagnostics = jsonEncode({
    'feature': 'tron_gasfree',
    'stage': state.gaslessTraceId == null ? 'pre_relay' : 'trace_status',
    'rail': 'gasfree',
    'state': state.gaslessTransferState?.name ?? 'unknown',
    'availability': state.gaslessAvailability.name,
    'retryable': state.canRetryGaslessTransfer,
    if (state.gaslessTraceId != null) 'trace_id': state.gaslessTraceId,
  });
  copyToClipBoard(context, diagnostics);

  try {
    await openUrl(discordInviteUrl);
  } catch (_) {
    // The approved bundle remains on the clipboard if support cannot open.
  }
}

class WithdrawForm extends StatefulWidget {
  final Asset asset;
  final VoidCallback onSuccess;
  final VoidCallback? onBackButtonPressed;

  /// Optional prefill for flows that open the form with a known recipient —
  /// e.g. the stranded-funds consolidation (recipient = the user's own GasFree
  /// custody address, native rail, max amount).
  final String? initialRecipient;
  final PubkeyInfo? initialSourceAddress;
  final bool initialGaslessEnabled;
  final bool initialIsMax;
  final bool lockSourceSelection;

  const WithdrawForm({
    required this.asset,
    required this.onSuccess,
    this.onBackButtonPressed,
    this.initialRecipient,
    this.initialSourceAddress,
    this.initialGaslessEnabled = true,
    this.initialIsMax = false,
    this.lockSourceSelection = false,
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
      initialRecipient: widget.initialRecipient,
      initialSourceAddress: widget.initialSourceAddress,
      initialGaslessEnabled: widget.initialGaslessEnabled,
      initialIsMax: widget.initialIsMax,
      lockSourceSelection: widget.lockSourceSelection,
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

              // Gas-free sends add the fee on top (custody cap governs max)
              // and the EOA spendable compared below is the wrong balance
              // for them — this offer only makes sense on the native rail.
              if (state.useGasless) return;

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
                    content: Text(LocaleKeys.withdrawFullAmountFeeNotice.tr()),
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
              if (state.gaslessTransferState ==
                  GaslessTransferState.confirmed) {
                context.read<AnalyticsBloc>().logEvent(
                  const GaslessTransferAnalyticsEventData(
                    stage: 'finality',
                    code: 'confirmed',
                    retryable: false,
                  ),
                );
              } else {
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
              }

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
              final reason = state.transactionError?.message ?? 'unknown';
              if (state.gaslessTransferState != null || state.useGasless) {
                context.read<AnalyticsBloc>().logEvent(
                  GaslessTransferAnalyticsEventData(
                    stage: state.gaslessTransferState?.name ?? 'submission',
                    code: reason,
                    retryable: state.canRetryGaslessTransfer,
                  ),
                );
              } else {
                final authBloc = context.read<AuthBloc>();
                final walletType = authBloc.state.currentUser?.type ?? '';
                context.read<AnalyticsBloc>().logEvent(
                  SendFailedEventData(
                    asset: state.asset.id.id,
                    network: state.asset.protocol.subClass.name,
                    failureReason: reason,
                    hdType: walletType,
                  ),
                );
              }
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
      buildWhen: (prev, curr) =>
          prev.step != curr.step ||
          prev.isSending != curr.isSending ||
          prev.gaslessTraceId != curr.gaslessTraceId,
      builder: (context, state) {
        final canLeave =
            !state.isSending ||
            !state.useGasless ||
            state.gaslessTraceId != null;
        return PopScope(
          canPop: canLeave,
          child: Column(
            children: [
              WithdrawFormHeader(
                asset: state.asset,
                onBackButtonPressed: canLeave ? onBackButtonPressed : null,
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
          ),
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
      case WithdrawFormStep.pending:
        return WithdrawFormPendingSection(onViewActivity: onSuccess);
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
            if (preview.fee is FeeInfoTronGasless) ...[
              const SizedBox(height: 16),
              _WithdrawGaslessDetailsCard(
                fee: preview.fee as FeeInfoTronGasless,
              ),
            ] else if (preview.fee is FeeInfoTron) ...[
              if (state.useGasless) ...[
                const SizedBox(height: 16),
                // Gas-free was requested but KDF returned a native preview: the
                // rail is unavailable. Surface a blocking notice; the Send
                // button is disabled (see isSubmitDisabled) so a native transfer
                // is never sent under a ticked gas-free checkbox.
                _GaslessUnavailableNotice(
                  gasCoin: (preview.fee as FeeInfoTron).coin,
                ),
              ],
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

  Color _warningBackground(BuildContext context) =>
      NoticeBanner.styleOf(context, NoticeBannerVariant.warning).background;

  Color _warningForeground(BuildContext context) =>
      NoticeBanner.styleOf(context, NoticeBannerVariant.warning).foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fee = preview.fee;
    final feeAssetId = _resolveFeeAssetId(context, state.asset, fee);
    final symbol = state.asset.id.symbol.configSymbol;
    final recipientAmount = fee is FeeInfoTronGasless
        ? state.authorizedRecipientAmount ?? preview.balanceChanges.totalAmount
        : _recipientAmount(preview.balanceChanges);
    // Gas-free fees are paid in the sent token, so amount + fee reconcile
    // into a single meaningful total; on other rails the fee is a different
    // asset and a token-sum would be nonsense.
    final gaslessFee = fee is FeeInfoTronGasless ? fee : null;
    final totalDeducted = gaslessFee == null
        ? null
        : recipientAmount + gaslessFee.totalTokenFee;
    // The GasFree tariff is flat, so small sends can be fee-dominated; the
    // SDK's isHighFee never fires for the gasless variant, so warn here when
    // the fee is >= 20% of what the recipient gets.
    final isFeeDominant =
        gaslessFee != null &&
        recipientAmount > Decimal.zero &&
        gaslessFee.totalTokenFee * Decimal.fromInt(5) >= recipientAmount;
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
                  Text(
                    gaslessFee != null
                        ? LocaleKeys.withdrawRecipientGets.tr()
                        : LocaleKeys.youSend.tr(),
                    style: labelStyle,
                  ),
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
          amount: recipientAmount,
          symbol: symbol,
          style: amountStyle,
          isAutoScrollEnabled: false,
        ),
        if (totalDeducted != null) ...[
          const SizedBox(height: 6),
          Text(
            key: const Key('withdraw-gasless-total-deducted'),
            LocaleKeys.withdrawTotalDeducted.tr(
              args: [_formatTrimmedDecimal(totalDeducted), symbol],
            ),
            style: labelStyle,
          ),
        ],
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
              if (state.isFeePriceExpensive || isFeeDominant)
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
            amount: fee.totalFee,
            symbol: feeAssetId.symbol.configSymbol,
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
    final sourceAddress = _effectiveWithdrawSourceAddress(state);
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
            args: [_formatTrimmedDecimal(totalFee), fee.coin],
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
              value: '${_formatTrimmedDecimal(fee.bandwidthFee)} ${fee.coin}',
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
              value: '${_formatTrimmedDecimal(fee.energyFee)} ${fee.coin}',
            ),
            if (fee.accountCreationFee != null)
              _buildDetailRow(
                context,
                label: LocaleKeys.withdrawTronAccountActivationFee.tr(),
                value:
                    '${_formatTrimmedDecimal(fee.accountCreationFee!)} ${fee.coin}',
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

class _WithdrawGaslessDetailsCard extends StatelessWidget {
  const _WithdrawGaslessDetailsCard({required this.fee});

  final FeeInfoTronGasless fee;

  /// Maps the backend's raw provider token (e.g. "gasfree", or an empty
  /// string) to a human-readable name so the Provider row never surfaces an
  /// internal code.
  String _humanizeProvider(String raw) {
    final name = raw.trim();
    if (name.isEmpty || name.toLowerCase() == 'gasfree') return 'GasFree';
    return name;
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
    final summary = LocaleKeys.withdrawGaslessFeeSummary.tr(
      args: [_formatTrimmedDecimal(fee.totalTokenFee), fee.coin],
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  LocaleKeys.withdrawGaslessNetworkDetails.tr(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Chip(
                  label: Text(LocaleKeys.withdrawGaslessBadge.tr()),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: NoticeBanner.styleOf(
                    context,
                    NoticeBannerVariant.success,
                  ).background,
                  labelStyle: theme.textTheme.labelSmall?.copyWith(
                    color: NoticeBanner.styleOf(
                      context,
                      NoticeBannerVariant.success,
                    ).foreground,
                    fontWeight: FontWeight.w700,
                  ),
                  side: BorderSide.none,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(summary, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            // The GasFree custody address the tokens actually settle from —
            // distinct from the withdrawal's `from` (the user's own address).
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawGaslessSourceAddress.tr(),
              value: formatCompactAddress(fee.gasfreeAddress),
            ),
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawGaslessProvider.tr(),
              value: _humanizeProvider(fee.providerName),
            ),
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawGaslessTransferFee.tr(),
              value: '${_formatTrimmedDecimal(fee.transferFee)} ${fee.coin}',
            ),
            if (fee.activationFee != null)
              _buildDetailRow(
                context,
                label: LocaleKeys.withdrawTronAccountActivationFee.tr(),
                value:
                    '${_formatTrimmedDecimal(fee.activationFee!)} ${fee.coin}',
              ),
            _buildDetailRow(
              context,
              label: LocaleKeys.withdrawGaslessTotalFee.tr(),
              value: '${_formatTrimmedDecimal(fee.totalTokenFee)} ${fee.coin}',
            ),
            if (fee.signedMaxFee != null)
              _buildDetailRow(
                context,
                label: LocaleKeys.withdrawGaslessMaxFee.tr(),
                value:
                    '${_formatTrimmedDecimal(fee.signedMaxFee!)} ${fee.coin}',
                valueStyle: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            NoticeBanner(
              variant: NoticeBannerVariant.info,
              icon: Icons.schedule_outlined,
              child: Text(
                LocaleKeys.withdrawGaslessRelayHint.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: NoticeBanner.styleOf(
                    context,
                    NoticeBannerVariant.info,
                  ).foreground,
                ),
              ),
            ),
            const SizedBox(height: 8),
            NoticeBanner(
              variant: NoticeBannerVariant.warning,
              icon: Icons.warning_amber_rounded,
              child: Text(
                LocaleKeys.withdrawGaslessIrreversibleWarning.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: NoticeBanner.styleOf(
                    context,
                    NoticeBannerVariant.warning,
                  ).foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Amber notice shown when a gas-free withdrawal silently fell back to the
/// native rail (relay unavailable), so the user learns the network fee is
/// actually paid in [gasCoin] (TRX) rather than in the token they expected.
/// Amber receipt banner shown when a gas-free request fell back to a native
/// (TRX-funded) transfer.
///
/// Intentionally unreachable under the current design (gas-free downgrades are
/// blocked before submit and `fallbackToNative` is false) — kept as a
/// defense-in-depth backstop should native fallback ever be re-enabled.
class _GaslessFallbackNotice extends StatelessWidget {
  const _GaslessFallbackNotice({required this.gasCoin});

  final String gasCoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = NoticeBanner.styleOf(context, NoticeBannerVariant.warning);

    return NoticeBanner(
      icon: Icons.info_outline_rounded,
      child: Text(
        LocaleKeys.withdrawGaslessFallbackNotice.tr(args: [gasCoin]),
        style: theme.textTheme.bodySmall?.copyWith(
          color: style.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Blocking notice shown on the confirm step when gas-free was requested but
/// the generated preview came back as a native (TRX-funded) transfer — the
/// gas-free rail could not be built (e.g. the GasFree custody address is
/// unfunded, or the token is not enrolled with the provider). The Send button
/// is disabled for this state, so the user must untick gas-free to send a
/// standard transfer paid in [gasCoin] (TRX).
class _GaslessUnavailableNotice extends StatelessWidget {
  const _GaslessUnavailableNotice({required this.gasCoin});

  final String gasCoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.errorContainer;
    final foreground = theme.colorScheme.onErrorContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block_rounded, size: 20, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              LocaleKeys.withdrawGaslessUnavailableBlocked.tr(args: [gasCoin]),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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

/// Source selector for gas-free-capable sends.
///
/// The user's single TRON key funds two spendable pots: the derived GasFree
/// custody address (token balance, fees paid in the token) and the standard
/// address (fees paid in TRX). The stock selector could only show the
/// standard address — locked — while a gas-free send actually settles from
/// the custody address, which read as "sending from an address I never
/// chose". Here both pots are selectable entries and the choice drives the
/// fee rail; the Advanced native toggle dispatches the same event, so the
/// two controls stay in sync by construction.
class _GaslessRailSourceSelector extends StatelessWidget {
  const _GaslessRailSourceSelector({required this.state});

  final WithdrawFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sources = state.pubkeys?.keys ?? const <PubkeyInfo>[];
    final canonicalSource = sources.firstWhereOrNull(
      (key) =>
          isCanonicalTronGaslessPubkey(
            key,
            isHdWallet: state.walletType == WalletType.hdwallet,
          ) &&
          (key.gasfreeAddress?.isNotEmpty ?? false),
    );
    if (canonicalSource == null) return const SizedBox.shrink();
    final custodyAddress =
        state.gaslessAccountStatus?.gasfreeAddress ??
        canonicalSource.gasfreeAddress!;
    final symbol = state.asset.id.symbol.configSymbol;
    // Never substitute the aggregate/EOA cache into custody. Unknown custody
    // balance remains explicitly zero until account_status supplies its
    // provenance-aware snapshot.
    final custodyBalance =
        state.gaslessAccountStatus?.custodyBalance ??
        BalanceInfo(
          total: Decimal.zero,
          spendable: Decimal.zero,
          unspendable: Decimal.zero,
        );

    // View-model entry only: selection dispatches the rail toggle, never a
    // source change, so this synthetic pubkey can never leak into the bloc.
    final custodyEntry = PubkeyInfo(
      address: custodyAddress,
      derivationPath: canonicalSource.derivationPath,
      chain: canonicalSource.chain,
      balance: custodyBalance,
      coinTicker: state.asset.id.id,
      gasfreeAddress: custodyAddress,
    );
    final standardSources = sources
        .where(
          (key) =>
              key.balance.total > Decimal.zero ||
              key.address == canonicalSource.address,
        )
        .toList();
    final selectedStandard = standardSources.firstWhereOrNull(
      (entry) => entry.address == state.selectedSourceAddress?.address,
    );
    final selected = state.isGaslessEnabled
        ? custodyEntry
        : selectedStandard ?? canonicalSource;

    String entryLabel(PubkeyInfo entry) => entry.address == custodyAddress
        ? LocaleKeys.withdrawSourceGasfreeEntry.tr(
            args: [_formatTrimmedDecimal(entry.balance.spendable), symbol],
          )
        : LocaleKeys.withdrawSourceStandardEntry.tr(
            args: [_formatTrimmedDecimal(entry.balance.spendable), symbol],
          );

    return Column(
      key: const Key('withdraw-gasless-source-selector'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleKeys.withdrawSendFrom.tr(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        AddressSelectInput(
          addresses: [custodyEntry, ...standardSources],
          selectedAddress: selected,
          assetName: symbol,
          balanceLabel: entryLabel,
          verified: (entry) => entry.address == custodyAddress,
          onAddressSelected: state.isSourceSelectionLocked
              ? null
              : (picked) {
                  if (picked == null) return;
                  final wantGasless = picked.address == custodyAddress;
                  if (wantGasless) {
                    if (!state.isGaslessEnabled) {
                      context.read<WithdrawFormBloc>().add(
                        const WithdrawFormGaslessToggled(true),
                      );
                    }
                    return;
                  }
                  if (state.isGaslessEnabled) {
                    context.read<WithdrawFormBloc>().add(
                      const WithdrawFormGaslessToggled(false),
                    );
                  }
                  context.read<WithdrawFormBloc>().add(
                    WithdrawFormSourceChanged(picked),
                  );
                },
        ),
      ],
    );
  }
}

String _formatTrimmedDecimal(Decimal value, {int precision = 8}) {
  return value.toStringAsFixed(precision).replaceAll(RegExp(r'\.?0+$'), '');
}

/// The amount sent on a standard rail.
///
/// GasFree call sites use the persisted authorization amount or KDF's
/// `totalAmount` directly. They must never reverse-calculate the recipient
/// amount from a fee that can settle below the signed maximum.
Decimal _recipientAmount(BalanceChanges balanceChanges) {
  final net = balanceChanges.netChange.abs();
  return net > Decimal.zero ? net : balanceChanges.spentByMe;
}

/// Fixed status chip communicating that the gas-free rail is active: the fee
/// is paid in the token and the user never needs TRX. Replaces the old opt-in
/// checkbox — gasless is the default, not an option to discover. The trailing
/// info affordance opens [GaslessInfoDialog].
class _GaslessRailStatusChip extends StatelessWidget {
  const _GaslessRailStatusChip({required this.state});

  final WithdrawFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReady = state.gaslessAvailability.isVerifiedReady;
    final isCheckingAvailability = state.isGaslessAvailabilityUnknown;
    final isNeutralAvailability = state.isGaslessAvailabilityNeutral;
    final isUnsupported =
        state.gaslessAvailability == GaslessAvailability.unsupported;
    final isSecurityMismatch =
        state.gaslessAvailability == GaslessAvailability.securityMismatch;
    final variant = isReady
        ? NoticeBannerVariant.success
        : isSecurityMismatch
        ? NoticeBannerVariant.warning
        : NoticeBannerVariant.info;
    final style = NoticeBanner.styleOf(context, variant);
    final foreground = style.foreground;
    final symbol = state.asset.id.symbol.configSymbol;
    final transferFee = state.gaslessTransferFee;
    // While the first status fetch is in flight the fee and availability are
    // unknown: say so instead of optimistically promising the rail (the
    // Preview button is held under the same condition).
    final label = isCheckingAvailability
        ? LocaleKeys.withdrawGaslessCheckingAvailability.tr()
        : state.isGaslessProviderUnavailable
        ? LocaleKeys.withdrawGaslessProviderUnavailable.tr(args: [symbol])
        : isUnsupported
        ? LocaleKeys.withdrawGaslessUnsupported.tr()
        : isSecurityMismatch
        ? LocaleKeys.withdrawGaslessSecurityMismatch.tr()
        : isNeutralAvailability
        ? LocaleKeys.withdrawGaslessAvailabilityUnknown.tr()
        : transferFee != null
        ? LocaleKeys.withdrawGaslessRailChipWithFee.tr(
            args: [_formatTrimmedDecimal(transferFee), symbol],
          )
        : LocaleKeys.withdrawGaslessRailChip.tr(args: [symbol]);

    return Container(
      key: const Key('withdraw-gasless-chip'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          if (isCheckingAvailability)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: foreground,
              ),
            )
          else
            Icon(
              isReady
                  ? Icons.bolt_rounded
                  : isSecurityMismatch
                  ? Icons.gpp_bad_outlined
                  : isUnsupported
                  ? Icons.block_rounded
                  : Icons.info_outline_rounded,
              size: 20,
              color: foreground,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            key: const Key('withdraw-gasless-info-button'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.info_outline_rounded, size: 18, color: foreground),
            tooltip: LocaleKeys.gaslessInfoTitle.tr(),
            onPressed: () => GaslessInfoDialog.show(
              context,
              assetName: state.asset.id.symbol.configSymbol,
            ),
          ),
          if (isNeutralAvailability || state.isGaslessProviderUnavailable)
            IconButton(
              tooltip: LocaleKeys.retryButtonText.tr(),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => context.read<WithdrawFormBloc>().add(
                const WithdrawFormGaslessStatusRequested(force: true),
              ),
              icon: Icon(Icons.refresh_rounded, color: foreground),
            ),
        ],
      ),
    );
  }
}

/// Pre-warning shown on the fill step when the custody account has not been
/// activated yet: the first gasless send carries a one-time activation fee on
/// top of the transfer fee, both paid in the token. The confirm step shows the
/// exact signed fees.
class _GaslessActivationBanner extends StatelessWidget {
  const _GaslessActivationBanner({required this.state});

  final WithdrawFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = state.asset.id.symbol.configSymbol;
    final activationFee = state.gaslessActivationFee;
    final transferFee = state.gaslessTransferFee;
    final message = activationFee != null && transferFee != null
        ? LocaleKeys.withdrawGaslessActivationBanner.tr(
            args: [
              _formatTrimmedDecimal(activationFee),
              symbol,
              _formatTrimmedDecimal(transferFee),
              symbol,
            ],
          )
        : LocaleKeys.withdrawGaslessActivationBannerGeneric.tr(args: [symbol]);

    return Container(
      key: const Key('withdraw-gasless-activation-banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest degradation notice when the GasFree provider reports itself
/// unavailable: funds are safe on-chain but a gasless send cannot be built
/// right now. Never suggests TRX or the native rail. Offers a retry that
/// force-refreshes the account status.
class _GaslessProviderUnavailableNotice extends StatelessWidget {
  const _GaslessProviderUnavailableNotice({required this.assetName});

  final String assetName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = NoticeBanner.styleOf(context, NoticeBannerVariant.warning);

    return NoticeBanner(
      key: const Key('gasless-provider-unavailable-notice'),
      icon: Icons.cloud_off_rounded,
      footer: Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          key: const Key('gasless-provider-unavailable-retry'),
          onPressed: () => context.read<WithdrawFormBloc>().add(
            const WithdrawFormGaslessStatusRequested(force: true),
          ),
          child: Text(
            LocaleKeys.retryButtonText.tr(),
            style: TextStyle(color: style.foreground),
          ),
        ),
      ),
      child: Text(
        LocaleKeys.withdrawGaslessProviderUnavailable.tr(args: [assetName]),
        style: theme.textTheme.bodySmall?.copyWith(
          color: style.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Collapsed "Advanced" section housing the native (TRX-paid) interop rail.
/// Kept out of the way: gasless is the default, and a standard transfer is
/// only for interoperability (or moving legacy standard-address funds).
class _AdvancedNativeSendSection extends StatelessWidget {
  const _AdvancedNativeSendSection({required this.state});

  final WithdrawFormState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNativeSelected = !state.isGaslessEnabled;

    return Card(
      margin: EdgeInsets.zero,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const Key('withdraw-advanced-section'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          initiallyExpanded: isNativeSelected,
          title: Text(
            LocaleKeys.withdrawAdvancedSection.tr(),
            style: theme.textTheme.titleSmall,
          ),
          children: [
            SwitchListTile(
              key: const Key('withdraw-native-send-switch'),
              value: isNativeSelected,
              contentPadding: EdgeInsets.zero,
              onChanged: (nativeOn) => context.read<WithdrawFormBloc>().add(
                WithdrawFormGaslessToggled(!nativeOn),
              ),
              title: Text(LocaleKeys.withdrawNativeSendToggle.tr()),
              subtitle: Text(
                LocaleKeys.withdrawNativeSendToggleSubtitle.tr(
                  args: [state.asset.id.symbol.configSymbol],
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (isNativeSelected)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: NoticeBanner(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Text(
                    LocaleKeys.withdrawNativeSendActive.tr(),
                    key: const Key('withdraw-native-send-active-note'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: NoticeBanner.styleOf(
                        context,
                        NoticeBannerVariant.warning,
                      ).foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Honest notice for hardware wallets, where the gasless rail is unavailable
/// (the Trezor activation path does not thread the GasFree provider): sends
/// use a standard TRON transfer and need a small TRX balance.
class _GaslessTrezorNotice extends StatelessWidget {
  const _GaslessTrezorNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = NoticeBanner.styleOf(context, NoticeBannerVariant.warning);

    return NoticeBanner(
      key: const Key('withdraw-gasless-trezor-notice'),
      icon: Icons.usb_rounded,
      child: Text(
        LocaleKeys.withdrawGaslessTrezorNotice.tr(),
        style: theme.textTheme.bodySmall?.copyWith(
          color: style.foreground,
          fontWeight: FontWeight.w600,
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

  /// The "Available:" figure above the amount input. Gas-free sends show the
  /// sendable cap from `gasless::account_status` (null until known); native
  /// sends show the selected source address's spendable balance.
  static String? _fillAvailableBalance(WithdrawFormState state) {
    final value = state.useGasless
        ? state.gaslessMaxWithdrawable
        : state.selectedSourceAddress?.balance.spendable;
    if (value == null) return null;
    return _formatTrimmedDecimal(value);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        final isEditingLocked = state.isSending;
        final isSourceInputEnabled =
            !state.isSourceSelectionLocked &&
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
                  // A gas-free-capable TRON key funds TWO spendable pots:
                  // the GasFree custody address (token balance, fee in the
                  // token) and the standard address (fee in TRX). Present
                  // both as selectable source entries — the choice drives the
                  // fee rail. Other assets keep the stock selector.
                  if (state.isGaslessSupported &&
                      (state
                              .selectedSourceAddress
                              ?.gasfreeAddress
                              ?.isNotEmpty ??
                          false))
                    _GaslessRailSourceSelector(state: state)
                  else
                    SourceAddressField(
                      asset: state.asset,
                      pubkeys: state.pubkeys,
                      selectedAddress: state.selectedSourceAddress,
                      isLoading: state.pubkeys?.isEmpty ?? true,
                      showBalanceIndicator: !state.useGasless,
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
                    // On the gas-free rail the sendable cap (fees already
                    // netted out by KDF) is the honest "available" figure;
                    // the per-address EOA balance would be misleading there.
                    availableBalance: _fillAvailableBalance(state),
                    symbol: state.asset.id.symbol.configSymbol,
                    maxAmountLabel: LocaleKeys.withdrawAmountMaximum.tr(),
                    // Gas-free nets fees out of the "available" figure, so the
                    // custody balance (e.g. 3 USDT chip) and the sendable amount
                    // (0 after fees) legitimately differ — label it honestly so
                    // the two numbers don't read as a contradiction.
                    availableBalanceLabel: state.useGasless
                        ? LocaleKeys.withdrawGaslessSendableLabel.tr()
                        : LocaleKeys.withdrawAvailableLabel.tr(),
                  ),
                  if (state.useGasless &&
                      state.gaslessAccountStatus != null) ...[
                    const SizedBox(height: 12),
                    GaslessBalanceBreakdown(
                      total: _formatTrimmedDecimal(
                        state.gaslessAccountStatus!.onChainBalance,
                      ),
                      spendable: _formatTrimmedDecimal(
                        state.gaslessAccountStatus!.spendableBalance ??
                            Decimal.zero,
                      ),
                      pending: _formatTrimmedDecimal(
                        state.gaslessAccountStatus!.frozenBalance ??
                            Decimal.zero,
                      ),
                      symbol: state.asset.id.symbol.configSymbol,
                      totalLabel: LocaleKeys.withdrawGaslessTotalBalance.tr(),
                      spendableLabel: LocaleKeys.withdrawGaslessSpendableBalance
                          .tr(),
                      pendingLabel: LocaleKeys
                          .withdrawGaslessPendingLockedBalance
                          .tr(),
                    ),
                  ],
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
                  if (state.isGaslessSupported) ...[
                    const SizedBox(height: 16),
                    // Gasless is the default rail, not an option to discover:
                    // a fixed status chip replaces the old checkbox, and the
                    // native (TRX-paid) rail lives in a collapsed Advanced
                    // section for interop only.
                    if (state.useGasless) ...[
                      _GaslessRailStatusChip(state: state),
                      if (state.needsGaslessActivation) ...[
                        const SizedBox(height: 8),
                        _GaslessActivationBanner(state: state),
                      ],
                      if (state.isGaslessProviderUnavailable) ...[
                        const SizedBox(height: 8),
                        _GaslessProviderUnavailableNotice(
                          assetName: state.asset.id.symbol.configSymbol,
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                    _AdvancedNativeSendSection(state: state),
                  ] else if (state.isGaslessTrezorBlocked) ...[
                    const SizedBox(height: 16),
                    const _GaslessTrezorNotice(),
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
              onPressed:
                  state.isSending ||
                      state.hasValidationErrors ||
                      state.isGaslessSendBlocked ||
                      state.isGaslessAvailabilityUnknown
                  ? null
                  : () {
                      if (state.useGasless) {
                        context.read<AnalyticsBloc>().logEvent(
                          const GaslessTransferAnalyticsEventData(
                            stage: 'preview',
                            code: 'started',
                            retryable: false,
                          ),
                        );
                      } else {
                        final authBloc = context.read<AuthBloc>();
                        final walletType =
                            authBloc
                                .state
                                .currentUser
                                ?.wallet
                                .config
                                .type
                                .name ??
                            '';
                        context.read<AnalyticsBloc>().logEvent(
                          SendInitiatedEventData(
                            asset: state.asset.id.id,
                            network: state.asset.protocol.subClass.name,
                            amount: double.tryParse(state.amount) ?? 0.0,
                            hdType: walletType,
                          ),
                        );
                      }
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

  Color _warningBackground(BuildContext context) =>
      NoticeBanner.styleOf(context, NoticeBannerVariant.warning).background;

  Color _warningForeground(BuildContext context) =>
      NoticeBanner.styleOf(context, NoticeBannerVariant.warning).foreground;

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
    // While a gas-free transfer is being relayed/confirmed, show its live state.
    final isGaslessSending =
        state.isSending && state.gaslessStatusMessage != null;
    final showSpinner = state.isPreviewRefreshing || isGaslessSending;

    if (isGaslessSending) {
      backgroundColor = theme.colorScheme.secondaryContainer;
      foregroundColor = theme.colorScheme.onSecondaryContainer;
      icon = Icons.bolt_rounded;
      message = _gaslessRelayStatusText(state);
    } else if (state.isPreviewRefreshing) {
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Announce relay-state changes to screen readers; the
                // liveRegion is scoped to the gas-free branch so the
                // per-second preview countdown never spams announcements.
                Semantics(
                  liveRegion: isGaslessSending,
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foregroundColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isGaslessSending) ...[
                  const SizedBox(height: 2),
                  Text(
                    LocaleKeys.withdrawGaslessRelayHint.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: foregroundColor.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Localized live status for the gas-free relay, keyed off the typed
  /// [WithdrawFormState.gaslessTraceState]; the raw SDK message is only a
  /// fallback for states this build does not know.
  String _gaslessRelayStatusText(WithdrawFormState state) {
    return switch (state.gaslessTraceState) {
      GaslessTraceState.pending =>
        LocaleKeys.withdrawGaslessStatusAwaitingRelay.tr(),
      GaslessTraceState.submitted =>
        LocaleKeys.withdrawGaslessStatusSubmitted.tr(),
      GaslessTraceState.onChain || GaslessTraceState.confirmed =>
        LocaleKeys.withdrawGaslessStatusConfirmingOnChain.tr(),
      GaslessTraceState.failed => state.gaslessStatusMessage ?? '',
      // The pre-relay yield ("Submitting gas-free transfer...") carries no
      // trace state yet.
      null => LocaleKeys.withdrawGaslessStatusSubmitting.tr(),
    };
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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_shouldStackWithdrawActions(context, constraints.maxWidth)) {
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
      },
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
            // Gas-free requested but the preview came back native: block the
            // send so a native (TRX-funded) transfer is never broadcast under a
            // ticked gas-free checkbox. The user must untick gas-free to send a
            // standard transfer.
            state.didGaslessDowngrade ||
            state.isGaslessSendBlocked ||
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
        // Gas-free was requested but the executed fee is native TRX -> the
        // relay was unavailable and the transfer fell back to the native rail.
        //
        // Defense-in-depth: this is currently UNREACHABLE. With
        // `fallbackToNative: false`, a gas-free request never produces a native
        // result, and a native downgrade is blocked before submit
        // (`didGaslessDowngrade` -> `isSubmitDisabled`). A successful gas-free
        // result therefore always carries a `FeeInfoTronGasless` fee, so this
        // stays false. It is retained intentionally so the user is still warned
        // if native fallback is ever re-enabled; do not remove without also
        // revisiting that block.
        final didGaslessFallBack =
            state.useGasless && result.fee is FeeInfoTron;

        return WithdrawSuccessReceipt(
          asset: state.asset,
          result: result,
          recipientAmount: state.authorizedRecipientAmount,
          sourceAddress: _effectiveWithdrawSourceAddress(state),
          memo: state.memo,
          didGaslessFallBack: didGaslessFallBack,
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
    this.recipientAmount,
    this.didGaslessFallBack = false,
    super.key,
  });

  final Asset asset;
  final WithdrawalResult result;
  final String? sourceAddress;
  final String? memo;
  final Decimal? recipientAmount;
  final bool didGaslessFallBack;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (_shouldStackWithdrawActions(context, constraints.maxWidth)) {
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
      },
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
    final txHash = result.txHash;
    final explorerUrl = txHash == null || txHash.isEmpty
        ? null
        : asset.protocol.explorerTxUrl(txHash);
    final feeAssetId = _resolveFeeAssetId(context, asset, result.fee);
    final symbol = asset.id.symbol.configSymbol;
    final gaslessFee = result.fee is FeeInfoTronGasless
        ? result.fee as FeeInfoTronGasless
        : null;
    final displayedRecipientAmount =
        recipientAmount ??
        (gaslessFee == null
            ? _recipientAmount(result.balanceChanges)
            : result.balanceChanges.totalAmount);
    final totalDeducted = gaslessFee == null
        ? null
        : displayedRecipientAmount +
              (gaslessFee.finalFee ?? gaslessFee.totalTokenFee);

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
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  LocaleKeys.successPageHeadline.tr(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              AssetLogo.ofId(asset.id, size: 52),
              const SizedBox(height: 12),
              Center(
                child: AssetAmountWithFiat(
                  assetId: asset.id,
                  amount: displayedRecipientAmount,
                  symbol: symbol,
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
              if (totalDeducted != null) ...[
                const SizedBox(height: 6),
                Text(
                  key: const Key('withdraw-receipt-total-deducted'),
                  LocaleKeys.withdrawTotalDeducted.tr(
                    args: [_formatTrimmedDecimal(totalDeducted), symbol],
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.textTheme.bodySmall?.color?.withValues(
                      alpha: 0.72,
                    ),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
                // A gas-free success only fires after the relay reports the
                // transfer confirmed on-chain, so "awaiting confirmations"
                // would understate finality on exactly the rail where the
                // user already sat through the wait.
                child: gaslessFee != null
                    ? _ConfirmedOnChainChip(theme: theme)
                    : Chip(
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
        // Retained defense-in-depth: `didGaslessFallBack` is unreachable under
        // the current strict-block design (see WithdrawFormSuccessSection).
        if (didGaslessFallBack && result.fee is FeeInfoTron) ...[
          const SizedBox(height: 16),
          _GaslessFallbackNotice(gasCoin: (result.fee as FeeInfoTron).coin),
        ],
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
                if (txHash != null && txHash.isNotEmpty)
                  _buildDetailItem(
                    context,
                    label: LocaleKeys.transactionHash.tr(),
                    child: CopiedText(
                      copiedValue: txHash,
                      isTruncated: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                if (gaslessFee?.traceId?.isNotEmpty ?? false)
                  _buildDetailItem(
                    context,
                    label: LocaleKeys.withdrawGaslessTraceId.tr(),
                    child: CopiedText(
                      copiedValue: gaslessFee!.traceId!,
                      isTruncated: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                if (gaslessFee != null)
                  _buildDetailItem(
                    context,
                    label: LocaleKeys.withdrawGaslessProvider.tr(),
                    child: SelectableText(
                      gaslessFee.providerName,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
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
                  label: gaslessFee == null
                      ? LocaleKeys.fee.tr()
                      : LocaleKeys.withdrawGaslessFinalFee.tr(),
                  child: AssetAmountWithFiat(
                    assetId: feeAssetId,
                    amount: gaslessFee?.finalFee ?? result.fee.totalFee,
                    symbol: feeAssetId.symbol.configSymbol,
                    isAutoScrollEnabled: false,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (gaslessFee != null) ...[
                  _buildDetailItem(
                    context,
                    label: LocaleKeys.withdrawGaslessTransferFee.tr(),
                    child: AssetAmountWithFiat(
                      assetId: asset.id,
                      amount: gaslessFee.transferFee,
                      symbol: symbol,
                      isAutoScrollEnabled: false,
                    ),
                  ),
                  if (gaslessFee.activationFee != null)
                    _buildDetailItem(
                      context,
                      label: LocaleKeys.withdrawGaslessActivationFee.tr(),
                      child: AssetAmountWithFiat(
                        assetId: asset.id,
                        amount: gaslessFee.activationFee!,
                        symbol: symbol,
                        isAutoScrollEnabled: false,
                      ),
                    ),
                  if (gaslessFee.signedMaxFee != null)
                    _buildDetailItem(
                      context,
                      label: LocaleKeys.withdrawGaslessMaxFee.tr(),
                      child: AssetAmountWithFiat(
                        assetId: asset.id,
                        amount: gaslessFee.signedMaxFee!,
                        symbol: symbol,
                        isAutoScrollEnabled: false,
                      ),
                    ),
                  if (result.confirmedAt != null)
                    _buildDetailItem(
                      context,
                      label: LocaleKeys.withdrawGaslessConfirmationTime.tr(),
                      child: SelectableText(
                        _formatConfirmationDateTime(
                          context,
                          result.confirmedAt!,
                        ),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (result.confirmationBlockHeight != null)
                    _buildDetailItem(
                      context,
                      label: LocaleKeys.withdrawGaslessConfirmationBlock.tr(),
                      child: SelectableText(
                        result.confirmationBlockHeight.toString(),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
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
                      Expanded(
                        child: Text(
                          asset.id.name,
                          overflow: TextOverflow.visible,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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

String _formatConfirmationDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatFullDate(local)}, '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

/// Finality chip for gas-free receipts: the relay flow completes only after
/// on-chain confirmation, so the receipt states it plainly. Uses the brand OK
/// green family (icon) with onSurface text for contrast in both themes.
class _ConfirmedOnChainChip extends StatelessWidget {
  const _ConfirmedOnChainChip({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final style = NoticeBanner.styleOf(context, NoticeBannerVariant.success);
    final background = style.background;
    final iconColor = style.accent;
    final textColor = style.foreground;

    return Chip(
      key: const Key('withdraw-gasless-confirmed-chip'),
      padding: EdgeInsets.zero,
      avatar: Icon(Icons.check_circle_rounded, size: 18, color: iconColor),
      label: Text(
        LocaleKeys.withdrawGaslessConfirmedOnChain.tr(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      backgroundColor: background,
      side: BorderSide.none,
    );
  }
}

class WithdrawFormPendingSection extends StatelessWidget {
  const WithdrawFormPendingSection({required this.onViewActivity, super.key});

  final VoidCallback onViewActivity;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        return GaslessPendingTransferPanel(
          title: LocaleKeys.withdrawGaslessPendingTitle.tr(),
          description: LocaleKeys.withdrawGaslessPendingDescription.tr(),
          continueLabel: LocaleKeys.withdrawGaslessContinueChecking.tr(),
          activityLabel: LocaleKeys.withdrawGaslessViewActivity.tr(),
          supportLabel: LocaleKeys.support.tr(),
          traceLabel: LocaleKeys.withdrawGaslessTraceId.tr(),
          traceId: state.gaslessTraceId,
          isChecking: state.isSending,
          onContinueChecking: () => context.read<WithdrawFormBloc>().add(
            const WithdrawFormGaslessTraceCheckRequested(),
          ),
          onViewActivity: onViewActivity,
          onSupport: () => _openGaslessSupportContact(context, state),
        );
      },
    );
  }
}

class WithdrawFormFailedSection extends StatelessWidget {
  const WithdrawFormFailedSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<WithdrawFormBloc, WithdrawFormState>(
      builder: (context, state) {
        final supportLink = TextButton(
          onPressed: () => _openGaslessSupportContact(context, state),
          child: Text(LocaleKeys.support.tr()),
        );

        final backButton = OutlinedButton(
          onPressed: () => context.read<WithdrawFormBloc>().add(
            const WithdrawFormStepReverted(),
          ),
          child: Text(LocaleKeys.back.tr()),
        );

        final tryAgainButton = FilledButton(
          onPressed: state.canRetryGaslessTransfer
              ? () => context.read<WithdrawFormBloc>().add(
                  const WithdrawFormReset(),
                )
              : null,
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
            LayoutBuilder(
              builder: (context, constraints) {
                final stack = _shouldStackWithdrawActions(
                  context,
                  constraints.maxWidth,
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (stack) ...[
                      backButton,
                      const SizedBox(height: 12),
                      tryAgainButton,
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: backButton),
                          const SizedBox(width: 16),
                          Expanded(child: tryAgainButton),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Center(child: supportLink),
                  ],
                );
              },
            ),
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
