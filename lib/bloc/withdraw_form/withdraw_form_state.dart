import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/utils.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_step.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class WithdrawFormState extends Equatable {
  final Asset asset;
  final AssetPubkeys? pubkeys;
  final WithdrawFormStep step;

  // Form fields
  final String recipientAddress;
  final String amount;
  final PubkeyInfo? selectedSourceAddress;
  final bool isMaxAmount;
  final bool isCustomFee;
  final FeeInfo? customFee;
  final String? memo;
  final bool isIbcTransfer;
  final String? ibcChannel;
  final WithdrawalFeeOptions? feeOptions;
  final WithdrawalFeeLevel? selectedFeePriority;

  // Transaction state
  final WithdrawalPreview? preview;
  final bool isSending;
  final WithdrawalResult? result;

  // Hardware wallet progress state
  final bool isAwaitingTrezorConfirmation;

  // Validation errors
  final TextError? recipientAddressError; // Basic address validation
  final bool isMixedCaseAddress; // EVM mixed case specific error
  final TextError? amountError; // Amount validation (insufficient funds etc)
  final TextError? customFeeError; // Fee validation for custom fees
  final TextError? ibcChannelError; // IBC channel validation

  // Network/Transaction errors
  final TextError? previewError; // Errors during preview generation
  final TextError? transactionError; // Errors during transaction submission
  final TextError? networkError; // Network connectivity errors

  bool get isCustomFeeSupported =>
      asset.protocol is UtxoProtocol ||
      asset.protocol is Erc20Protocol ||
      asset.protocol is QtumProtocol ||
      asset.protocol is TendermintProtocol;

  bool get isPriorityFeeSupported =>
      asset.protocol is Erc20Protocol ||
      asset.protocol is QtumProtocol ||
      asset.protocol is TendermintProtocol;

  bool get hasPreviewError => previewError != null;
  bool get hasTransactionError => transactionError != null;
  bool get hasAddressError => recipientAddressError != null;
  bool get hasValidationErrors =>
      hasAddressError ||
      amountError != null ||
      customFeeError != null ||
      ibcChannelError != null ||
      !_hasValidFormData();

  // TODO: change to use formz for field validation & to create reusable input
  // field validators
  /// Checks if the form has valid data to submit, not just absence of errors
  bool _hasValidFormData() {
    // A source address must be selected
    if (selectedSourceAddress == null) {
      return false;
    }
    // Recipient address is required and must not be empty
    if (recipientAddress.trim().isEmpty) {
      return false;
    }

    // Amount must be greater than zero unless max amount is selected
    if (!isMaxAmount) {
      try {
        final normalizedAmount = normalizeDecimalString(amount);
        final parsedAmount = Decimal.parse(normalizedAmount);
        if (parsedAmount <= Decimal.zero) {
          return false;
        }
      } catch (_) {
        return false; // Invalid number format
      }
    }

    // If IBC transfer is enabled, channel is required
    if (isIbcTransfer && (ibcChannel == null || ibcChannel!.trim().isEmpty)) {
      return false;
    }

    // If custom fee is enabled, it must be valid
    if (isCustomFee && customFee == null) {
      return false;
    }

    return true;
  }

  const WithdrawFormState({
    required this.asset,
    this.pubkeys,
    required this.step,
    required this.recipientAddress,
    required this.amount,
    this.selectedSourceAddress,
    this.isMaxAmount = false,
    this.isCustomFee = false,
    this.customFee,
    this.memo,
    this.isIbcTransfer = false,
    this.ibcChannel,
    this.feeOptions,
    this.selectedFeePriority,
    this.preview,
    this.isSending = false,
    this.result,
    // Hardware wallet state
    this.isAwaitingTrezorConfirmation = false,
    // Error states
    this.recipientAddressError,
    this.isMixedCaseAddress = false,
    this.amountError,
    this.customFeeError,
    this.ibcChannelError,
    this.previewError,
    this.transactionError,
    this.networkError,
  });

  WithdrawFormState copyWith({
    Asset? asset,
    ValueGetter<AssetPubkeys?>? pubkeys,
    WithdrawFormStep? step,
    String? recipientAddress,
    String? amount,
    ValueGetter<PubkeyInfo?>? selectedSourceAddress,
    bool? isMaxAmount,
    bool? isCustomFee,
    ValueGetter<FeeInfo?>? customFee,
    ValueGetter<String?>? memo,
    bool? isIbcTransfer,
    ValueGetter<String?>? ibcChannel,
    ValueGetter<WithdrawalFeeOptions?>? feeOptions,
    ValueGetter<WithdrawalFeeLevel?>? selectedFeePriority,
    ValueGetter<WithdrawalPreview?>? preview,
    bool? isSending,
    ValueGetter<WithdrawalResult?>? result,
    // Hardware wallet state
    bool? isAwaitingTrezorConfirmation,
    // Error states
    ValueGetter<TextError?>? recipientAddressError,
    bool? isMixedCaseAddress,
    ValueGetter<TextError?>? amountError,
    ValueGetter<TextError?>? customFeeError,
    ValueGetter<TextError?>? ibcChannelError,
    ValueGetter<TextError?>? previewError,
    ValueGetter<TextError?>? transactionError,
    ValueGetter<TextError?>? networkError,
  }) {
    return WithdrawFormState(
      asset: asset ?? this.asset,
      pubkeys: pubkeys != null ? pubkeys() : this.pubkeys,
      step: step ?? this.step,
      recipientAddress: recipientAddress ?? this.recipientAddress,
      amount: amount ?? this.amount,
      selectedSourceAddress: selectedSourceAddress != null
          ? selectedSourceAddress()
          : this.selectedSourceAddress,
      isMaxAmount: isMaxAmount ?? this.isMaxAmount,
      isCustomFee: isCustomFee ?? this.isCustomFee,
      customFee: customFee != null ? customFee() : this.customFee,
      memo: memo != null ? memo() : this.memo,
      isIbcTransfer: isIbcTransfer ?? this.isIbcTransfer,
      ibcChannel: ibcChannel != null ? ibcChannel() : this.ibcChannel,
      feeOptions: feeOptions != null ? feeOptions() : this.feeOptions,
      selectedFeePriority: selectedFeePriority != null
          ? selectedFeePriority()
          : this.selectedFeePriority,
      preview: preview != null ? preview() : this.preview,
      isSending: isSending ?? this.isSending,
      result: result != null ? result() : this.result,
      // Hardware wallet state
      isAwaitingTrezorConfirmation:
          isAwaitingTrezorConfirmation ?? this.isAwaitingTrezorConfirmation,
      // Error states
      recipientAddressError: recipientAddressError != null
          ? recipientAddressError()
          : this.recipientAddressError,
      isMixedCaseAddress: isMixedCaseAddress ?? this.isMixedCaseAddress,
      amountError: amountError != null ? amountError() : this.amountError,
      customFeeError: customFeeError != null
          ? customFeeError()
          : this.customFeeError,
      ibcChannelError: ibcChannelError != null
          ? ibcChannelError()
          : this.ibcChannelError,
      previewError: previewError != null ? previewError() : this.previewError,
      transactionError: transactionError != null
          ? transactionError()
          : this.transactionError,
      networkError: networkError != null ? networkError() : this.networkError,
    );
  }

  WithdrawParameters toWithdrawParameters() {
    return WithdrawParameters(
      asset: asset.id.id,
      toAddress: recipientAddress,
      amount: isMaxAmount
          ? null
          : Decimal.parse(normalizeDecimalString(amount)),
      fee: isCustomFee ? customFee : null,
      feePriority: isCustomFee ? null : selectedFeePriority,
      from: selectedSourceAddress?.derivationPath != null
          ? WithdrawalSource.hdDerivationPath(
              selectedSourceAddress!.derivationPath!,
            )
          : null,
      memo: memo,
      ibcTransfer: isIbcTransfer ? true : null,
      ibcSourceChannel: ibcChannel?.isNotEmpty == true
          ? int.tryParse(ibcChannel!.trim())
          : null,
      isMax: isMaxAmount,
    );
  }

  //TODO!
  double? get usdFeePrice => null;

  //TODO!
  double? get usdAmountPrice => null;

  bool get isFeePriceExpensive => preview?.fee.isHighFee ?? false;

  @override
  List<Object?> get props => [
    asset,
    pubkeys,
    step,
    recipientAddress,
    amount,
    selectedSourceAddress,
    isMaxAmount,
    isCustomFee,
    customFee,
    memo,
    isIbcTransfer,
    ibcChannel,
    feeOptions,
    selectedFeePriority,
    preview,
    isSending,
    result,
    isAwaitingTrezorConfirmation,
    recipientAddressError,
    isMixedCaseAddress,
    amountError,
    customFeeError,
    ibcChannelError,
    previewError,
    transactionError,
    networkError,
  ];
}
