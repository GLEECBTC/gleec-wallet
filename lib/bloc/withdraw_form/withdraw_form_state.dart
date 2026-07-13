import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart'
    show
        GaslessAccountAvailability,
        GaslessAccountStatusResponse,
        GaslessTraceState;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:komodo_ui/utils.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_step.dart';
import 'package:web_dex/bloc/withdraw_form/gasless_transfer_state.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/shared/utils/formatters.dart';

class WithdrawFormState extends Equatable {
  static const int tronPreviewExpirationSeconds = 60;

  /// Validity window of the signed gas-free (TIP-712) permit. KDF bakes
  /// `now + deadline_seconds` into the permit at preview/sign time and the
  /// provider re-checks it at broadcast, so it must comfortably outlive the
  /// 60s UI preview TTL ([tronPreviewExpirationSeconds]) plus relay latency.
  /// Matches KDF's `DEFAULT_GASLESS_DEADLINE_SECONDS`. Fee drift over the
  /// longer window is bounded by the permit's signed max-fee cap.
  static const int gaslessPermitDeadlineSeconds = 300;

  final Asset asset;
  final AssetPubkeys? pubkeys;
  final WithdrawFormStep step;

  /// Wallet type of the active user. Gas-free (gasless) TRC20 transfers are not
  /// wired into the hardware-wallet (Trezor) activation path, so the gas-free
  /// rail is unsupported there — see [isGaslessSupported].
  final WalletType? walletType;
  final bool isGaslessFeatureConfigured;

  /// False when encrypted pending-transfer storage could not be read. New
  /// relay submissions must fail closed because an unresolved prior transfer
  /// may exist even though it cannot currently be displayed.
  final bool gaslessPendingStoreHealthy;

  // Form fields
  final String recipientAddress;
  final String amount;
  final PubkeyInfo? selectedSourceAddress;
  final bool isSourceSelectionLocked;
  final bool isMaxAmount;
  final bool isCustomFee;
  final FeeInfo? customFee;
  // Gas-free (gasless) TRC20 withdrawal options
  final bool isGaslessEnabled;
  final Decimal? gaslessMaxFee;

  /// Latest `gasless::account_status` snapshot for [asset] (custody balance,
  /// fees, activation state, provider availability). Null until the first
  /// successful fetch; kept stale-but-present when a refresh fails so the UI
  /// degrades gracefully. Only populated when [isGaslessSupported].
  final GaslessAccountStatusResponse? gaslessAccountStatus;

  /// When [gaslessAccountStatus] was fetched — drives the bloc's TTL cache.
  final DateTime? gaslessStatusFetchedAt;

  /// True while a `gasless::account_status` fetch is in flight.
  final bool isGaslessStatusLoading;

  /// Authoritative availability taxonomy for the selected GasFree rail.
  final GaslessAvailability gaslessAvailability;

  final String? memo;
  final bool isIbcTransfer;
  final String? ibcChannel;
  final WithdrawalFeeOptions? feeOptions;
  final WithdrawalFeeLevel? selectedFeePriority;

  // Transaction state
  final WithdrawalPreview? preview;
  final Decimal? authorizedRecipientAmount;
  final bool isSending;
  final WithdrawalResult? result;

  /// Live gas-free relay status message shown while a gasless transfer is
  /// being relayed and confirmed (null for non-gasless flows).
  final String? gaslessStatusMessage;

  /// Typed relay lifecycle state matching [gaslessStatusMessage]; preferred
  /// by the UI so the status copy can be localized. Null before the relay
  /// poll starts and for non-gasless flows.
  final GaslessTraceState? gaslessTraceState;

  /// Wallet-facing transfer finality. Unlike [gaslessTraceState], this also
  /// represents pre-relay rejection and an accepted transfer whose status is
  /// temporarily unknown.
  final GaslessTransferState? gaslessTransferState;

  /// Provider trace handle. Non-null means the relay accepted the transfer and
  /// a blind retry must be prohibited until an authoritative terminal state.
  final String? gaslessTraceId;

  /// Wallet-generated identity persisted before relay submission. This is
  /// intentionally distinct from [gaslessTraceId]: a request-only journal
  /// record has an unknown submission outcome and must never be polled as if
  /// the request ID were a provider trace handle.
  final String? gaslessRequestId;

  final DateTime? gaslessSubmittedAt;

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
  final TextError?
  confirmStepError; // Errors while refreshing an expired TRON preview
  final TextError? networkError; // Network connectivity errors

  // TRON confirm preview lifetime
  final DateTime? previewExpiresAt;
  final int? previewSecondsRemaining;
  final bool isPreviewExpired;
  final bool isPreviewRefreshing;

  bool get isCustomFeeSupported =>
      asset.protocol is UtxoProtocol ||
      asset.protocol is Erc20Protocol ||
      asset.protocol is QtumProtocol ||
      asset.protocol is TendermintProtocol;

  bool get isPriorityFeeSupported =>
      asset.protocol is Erc20Protocol ||
      asset.protocol is QtumProtocol ||
      asset.protocol is TendermintProtocol;

  bool get isTronAsset =>
      asset.protocol is TrxProtocol || asset.protocol is Trc20Protocol;

  /// Gas-free (gasless) transfers are available for TRC20 tokens, where the
  /// network fee is paid in the token rather than in TRX.
  ///
  /// Hardware wallets (Trezor) are excluded: their TRX/TRC20 activation path
  /// (`EthTaskActivationStrategy`) does not thread the `tron_gasless_provider`,
  /// so KDF has no relay configured and would silently produce a native
  /// transfer. Hiding the toggle keeps the request honest with what the backend
  /// can actually fulfil.
  bool get isGaslessSupported =>
      asset.protocol is Trc20Protocol &&
      isGaslessFeatureConfigured &&
      gaslessPendingStoreHealthy &&
      walletType != WalletType.trezor;

  /// Whether the gas-free rail should be requested for this withdrawal.
  bool get useGasless => isGaslessSupported && isGaslessEnabled;

  /// True when this asset would be gas-free but the active wallet is a
  /// hardware wallet, which cannot use the gasless rail — used to show an
  /// honest notice instead of the gasless UI.
  bool get isGaslessTrezorBlocked =>
      asset.protocol is Trc20Protocol &&
      isGaslessFeatureConfigured &&
      walletType == WalletType.trezor;

  /// True when the first gasless send will incur the one-time account
  /// activation fee (custody account not yet activated on-chain).
  bool get needsGaslessActivation =>
      useGasless &&
      gaslessAccountStatus?.availability ==
          GaslessAccountAvailability.available &&
      gaslessAccountStatus?.active == false;

  /// True when the GasFree provider reported itself unreachable: the custody
  /// balance is still known (on-chain fallback) but a gasless send cannot be
  /// built right now. Only a *successful* status fetch with an explicit
  /// non-available result blocks — a failed fetch leaves the KDF preview as
  /// the authority.
  bool get isGaslessProviderUnavailable =>
      useGasless &&
      (gaslessAvailability == GaslessAvailability.providerUnavailable ||
          (gaslessAvailability == GaslessAvailability.temporarilyUnavailable &&
              gaslessAccountStatus?.availability ==
                  GaslessAccountAvailability.providerUnreachable));

  /// Whether an authoritative capability/status result blocks a new GasFree
  /// submission. A transient fetch failure without a status snapshot remains
  /// previewable so Preview can perform the authoritative check; a returned
  /// provider rejection, unsupported token, or security mismatch fails closed.
  bool get isGaslessSendBlocked =>
      useGasless &&
      (gaslessAvailability.isBlocked ||
          (gaslessAccountStatus != null &&
              gaslessAccountStatus!.availability !=
                  GaslessAccountAvailability.available));

  /// Largest amount that can be sent gaslessly right now (fees already netted
  /// out by KDF), or null when unknown or on the native rail.
  Decimal? get gaslessMaxWithdrawable =>
      useGasless && gaslessAvailability.isVerifiedReady
      ? gaslessAccountStatus?.maxWithdrawable
      : null;

  /// True while the very first gas-free account-status fetch is still in
  /// flight: availability (and fees) are unknown, so the UI should show a
  /// checking state and hold Preview instead of letting it hard-fail.
  bool get isGaslessAvailabilityUnknown =>
      useGasless && gaslessAvailability.isChecking;

  bool get isGaslessAvailabilityNeutral =>
      useGasless && gaslessAvailability.isNeutralUnknown;

  bool get hasUnresolvedGaslessTransfer =>
      gaslessTransferState?.isUnresolved == true;

  bool get canRetryGaslessTransfer =>
      gaslessTransferState == null || gaslessTransferState!.canRetrySafely;

  /// One-time activation fee (token units), when known.
  Decimal? get gaslessActivationFee => gaslessAvailability.isVerifiedReady
      ? gaslessAccountStatus?.activationFee
      : null;

  /// Per-transfer gasless fee (token units), when known.
  Decimal? get gaslessTransferFee => gaslessAvailability.isVerifiedReady
      ? gaslessAccountStatus?.transferFee
      : null;

  /// True when the gas-free rail is usable (provider available, status known)
  /// but the custody balance is entirely consumed by the transfer (and, on a
  /// first send, activation) fee — so the maximum sendable amount is zero even
  /// though the account holds funds. Distinct from a genuinely empty custody
  /// (`on_chain == 0`), which is an honest "deposit funds" case KDF already
  /// reports well.
  bool get isGaslessBalanceBelowFees {
    final status = gaslessAccountStatus;
    if (!useGasless ||
        status == null ||
        status.availability != GaslessAccountAvailability.available) {
      return false;
    }
    final spendable = status.spendableBalance;
    final feeFloor =
        (status.transferFee ?? Decimal.zero) +
        (status.activationFee ?? Decimal.zero);
    return status.maxWithdrawable == Decimal.zero &&
        spendable != null &&
        spendable > Decimal.zero &&
        feeFloor >= spendable;
  }

  /// True when gas-free was requested but the generated [preview] came back as
  /// a native (TRX-funded) transfer — i.e. KDF could not build the gas-free
  /// rail and fell back. The wallet treats this as a blocking condition rather
  /// than silently broadcasting a native transfer the user did not choose.
  bool get didGaslessDowngrade =>
      useGasless && preview != null && preview!.fee is FeeInfoTron;

  bool get hasPreviewError => previewError != null;
  bool get hasTransactionError => transactionError != null;
  bool get hasConfirmStepError => confirmStepError != null;
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
    this.walletType,
    required this.isGaslessFeatureConfigured,
    this.gaslessPendingStoreHealthy = true,
    this.selectedSourceAddress,
    this.isSourceSelectionLocked = false,
    this.isMaxAmount = false,
    this.isCustomFee = false,
    this.customFee,
    this.isGaslessEnabled = true,
    this.gaslessMaxFee,
    this.gaslessAccountStatus,
    this.gaslessStatusFetchedAt,
    this.isGaslessStatusLoading = false,
    this.gaslessAvailability = GaslessAvailability.initial,
    this.memo,
    this.isIbcTransfer = false,
    this.ibcChannel,
    this.feeOptions,
    this.selectedFeePriority,
    this.preview,
    this.authorizedRecipientAmount,
    this.isSending = false,
    this.result,
    this.gaslessStatusMessage,
    this.gaslessTraceState,
    this.gaslessTransferState,
    this.gaslessTraceId,
    this.gaslessRequestId,
    this.gaslessSubmittedAt,
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
    this.confirmStepError,
    this.networkError,
    this.previewExpiresAt,
    this.previewSecondsRemaining,
    this.isPreviewExpired = false,
    this.isPreviewRefreshing = false,
  });

  WithdrawFormState copyWith({
    Asset? asset,
    ValueGetter<AssetPubkeys?>? pubkeys,
    WithdrawFormStep? step,
    String? recipientAddress,
    String? amount,
    WalletType? walletType,
    bool? isGaslessFeatureConfigured,
    bool? gaslessPendingStoreHealthy,
    ValueGetter<PubkeyInfo?>? selectedSourceAddress,
    bool? isSourceSelectionLocked,
    bool? isMaxAmount,
    bool? isCustomFee,
    ValueGetter<FeeInfo?>? customFee,
    bool? isGaslessEnabled,
    ValueGetter<Decimal?>? gaslessMaxFee,
    ValueGetter<GaslessAccountStatusResponse?>? gaslessAccountStatus,
    ValueGetter<DateTime?>? gaslessStatusFetchedAt,
    bool? isGaslessStatusLoading,
    GaslessAvailability? gaslessAvailability,
    ValueGetter<String?>? memo,
    bool? isIbcTransfer,
    ValueGetter<String?>? ibcChannel,
    ValueGetter<WithdrawalFeeOptions?>? feeOptions,
    ValueGetter<WithdrawalFeeLevel?>? selectedFeePriority,
    ValueGetter<WithdrawalPreview?>? preview,
    ValueGetter<Decimal?>? authorizedRecipientAmount,
    bool? isSending,
    ValueGetter<WithdrawalResult?>? result,
    ValueGetter<String?>? gaslessStatusMessage,
    ValueGetter<GaslessTraceState?>? gaslessTraceState,
    ValueGetter<GaslessTransferState?>? gaslessTransferState,
    ValueGetter<String?>? gaslessTraceId,
    ValueGetter<String?>? gaslessRequestId,
    ValueGetter<DateTime?>? gaslessSubmittedAt,
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
    ValueGetter<TextError?>? confirmStepError,
    ValueGetter<TextError?>? networkError,
    ValueGetter<DateTime?>? previewExpiresAt,
    ValueGetter<int?>? previewSecondsRemaining,
    bool? isPreviewExpired,
    bool? isPreviewRefreshing,
  }) {
    return WithdrawFormState(
      asset: asset ?? this.asset,
      pubkeys: pubkeys != null ? pubkeys() : this.pubkeys,
      step: step ?? this.step,
      recipientAddress: recipientAddress ?? this.recipientAddress,
      amount: amount ?? this.amount,
      walletType: walletType ?? this.walletType,
      isGaslessFeatureConfigured:
          isGaslessFeatureConfigured ?? this.isGaslessFeatureConfigured,
      gaslessPendingStoreHealthy:
          gaslessPendingStoreHealthy ?? this.gaslessPendingStoreHealthy,
      selectedSourceAddress: selectedSourceAddress != null
          ? selectedSourceAddress()
          : this.selectedSourceAddress,
      isSourceSelectionLocked:
          isSourceSelectionLocked ?? this.isSourceSelectionLocked,
      isMaxAmount: isMaxAmount ?? this.isMaxAmount,
      isCustomFee: isCustomFee ?? this.isCustomFee,
      customFee: customFee != null ? customFee() : this.customFee,
      isGaslessEnabled: isGaslessEnabled ?? this.isGaslessEnabled,
      gaslessMaxFee: gaslessMaxFee != null
          ? gaslessMaxFee()
          : this.gaslessMaxFee,
      gaslessAccountStatus: gaslessAccountStatus != null
          ? gaslessAccountStatus()
          : this.gaslessAccountStatus,
      gaslessStatusFetchedAt: gaslessStatusFetchedAt != null
          ? gaslessStatusFetchedAt()
          : this.gaslessStatusFetchedAt,
      isGaslessStatusLoading:
          isGaslessStatusLoading ?? this.isGaslessStatusLoading,
      gaslessAvailability: gaslessAvailability ?? this.gaslessAvailability,
      memo: memo != null ? memo() : this.memo,
      isIbcTransfer: isIbcTransfer ?? this.isIbcTransfer,
      ibcChannel: ibcChannel != null ? ibcChannel() : this.ibcChannel,
      feeOptions: feeOptions != null ? feeOptions() : this.feeOptions,
      selectedFeePriority: selectedFeePriority != null
          ? selectedFeePriority()
          : this.selectedFeePriority,
      preview: preview != null ? preview() : this.preview,
      authorizedRecipientAmount: authorizedRecipientAmount != null
          ? authorizedRecipientAmount()
          : this.authorizedRecipientAmount,
      isSending: isSending ?? this.isSending,
      result: result != null ? result() : this.result,
      gaslessStatusMessage: gaslessStatusMessage != null
          ? gaslessStatusMessage()
          : this.gaslessStatusMessage,
      gaslessTraceState: gaslessTraceState != null
          ? gaslessTraceState()
          : this.gaslessTraceState,
      gaslessTransferState: gaslessTransferState != null
          ? gaslessTransferState()
          : this.gaslessTransferState,
      gaslessTraceId: gaslessTraceId != null
          ? gaslessTraceId()
          : this.gaslessTraceId,
      gaslessRequestId: gaslessRequestId != null
          ? gaslessRequestId()
          : this.gaslessRequestId,
      gaslessSubmittedAt: gaslessSubmittedAt != null
          ? gaslessSubmittedAt()
          : this.gaslessSubmittedAt,
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
      confirmStepError: confirmStepError != null
          ? confirmStepError()
          : this.confirmStepError,
      networkError: networkError != null ? networkError() : this.networkError,
      previewExpiresAt: previewExpiresAt != null
          ? previewExpiresAt()
          : this.previewExpiresAt,
      previewSecondsRemaining: previewSecondsRemaining != null
          ? previewSecondsRemaining()
          : this.previewSecondsRemaining,
      isPreviewExpired: isPreviewExpired ?? this.isPreviewExpired,
      isPreviewRefreshing: isPreviewRefreshing ?? this.isPreviewRefreshing,
    );
  }

  WithdrawParameters toWithdrawParameters() {
    final derivationPath = selectedSourceAddress?.derivationPath;
    final supportsHdSourceSelection =
        asset.protocol.supportsMultipleAddresses &&
        asset.protocol is! SiaProtocol;

    return WithdrawParameters(
      asset: asset.id.id,
      toAddress: recipientAddress,
      amount: isMaxAmount
          ? null
          : Decimal.parse(normalizeDecimalString(amount)),
      fee: isCustomFee ? customFee : null,
      feePriority: isCustomFee ? null : selectedFeePriority,
      from: supportsHdSourceSelection && derivationPath != null
          ? WithdrawalSource.hdDerivationPath(derivationPath)
          : null,
      memo: memo,
      ibcTransfer: isIbcTransfer ? true : null,
      ibcSourceChannel: ibcChannel?.isNotEmpty == true
          ? int.tryParse(ibcChannel!.trim())
          : null,
      expirationSeconds: isTronAsset ? tronPreviewExpirationSeconds : null,
      isMax: isMaxAmount,
      feeMethod: useGasless ? WithdrawalFeeMethod.gasless : null,
      gaslessOptions: useGasless
          ? GaslessWithdrawalOptions(
              maxFee: gaslessMaxFee,
              deadlineSeconds: gaslessPermitDeadlineSeconds,
              // A checked gas-free option must never ask KDF to build a native
              // fallback. [didGaslessDowngrade] remains as a defensive guard for
              // older KDF responses or unexpected preview shapes.
              fallbackToNative: false,
            )
          : null,
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
    walletType,
    isGaslessFeatureConfigured,
    gaslessPendingStoreHealthy,
    selectedSourceAddress,
    isSourceSelectionLocked,
    isMaxAmount,
    isCustomFee,
    customFee,
    isGaslessEnabled,
    gaslessMaxFee,
    gaslessAccountStatus,
    gaslessStatusFetchedAt,
    isGaslessStatusLoading,
    gaslessAvailability,
    memo,
    isIbcTransfer,
    ibcChannel,
    feeOptions,
    selectedFeePriority,
    preview,
    authorizedRecipientAmount,
    isSending,
    result,
    gaslessStatusMessage,
    gaslessTraceState,
    gaslessTransferState,
    gaslessTraceId,
    gaslessRequestId,
    gaslessSubmittedAt,
    isAwaitingTrezorConfirmation,
    recipientAddressError,
    isMixedCaseAddress,
    amountError,
    customFeeError,
    ibcChannelError,
    previewError,
    transactionError,
    confirmStepError,
    networkError,
    previewExpiresAt,
    previewSecondsRemaining,
    isPreviewExpired,
    isPreviewRefreshing,
  ];
}
