import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/withdraw_form/withdraw_form_bloc.dart';
import 'package:web_dex/generated/codegen_loader.g.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/mm2/mm2_api/mm2_api.dart';
import 'package:web_dex/model/text_error.dart';
import 'package:web_dex/model/wallet.dart';
import 'package:web_dex/services/fd_monitor_service.dart';
import 'package:web_dex/shared/constants.dart';
import 'package:web_dex/shared/gasless/tron_gasless_policy.dart';
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/kdf_error_display.dart';
import 'package:web_dex/shared/utils/platform_tuner.dart';
import 'package:collection/collection.dart';

export 'package:web_dex/bloc/withdraw_form/withdraw_form_event.dart';
export 'package:web_dex/bloc/withdraw_form/gasless_transfer_state.dart';
export 'package:web_dex/bloc/withdraw_form/withdraw_form_state.dart';
export 'package:web_dex/bloc/withdraw_form/withdraw_form_step.dart';

import 'package:decimal/decimal.dart';

typedef WithdrawalAuthorizationGuard = FutureOr<bool> Function();

class WithdrawFormBloc extends Bloc<WithdrawFormEvent, WithdrawFormState> {
  static final Logger _logger = Logger('WithdrawFormBloc');
  static const _unsupportedSiaHardwareWalletMessage =
      'SIA is not supported for hardware wallets in this release.';
  static const _gaslessStatusTtl = Duration(seconds: 60);

  final KomodoDefiSdk _sdk;
  final WalletType? _walletType;

  /// Prefill applied at construction AND on [WithdrawFormReset], so a "try
  /// again" after a failed prefilled flow (e.g. the stranded-funds
  /// consolidation) restores the same rail/recipient/max instead of a default
  /// gasless form.
  final String? _initialRecipient;
  final PubkeyInfo? _initialSourceAddress;
  final bool _initialGaslessEnabled;
  final bool _initialIsMax;

  /// Locks the complete prefilled withdrawal contract used by controlled
  /// flows: source, rail, recipient, and Max selection. Source-only locking is
  /// insufficient because changing any of the other fields would let the
  /// caller mark a different transfer as complete.
  final bool _lockSourceSelection;
  final WithdrawalAuthorizationGuard? _authorizationGuard;
  final String? _authorizationFailureMessage;
  Timer? _tronPreviewTimer;
  int _gaslessTraceCheckGeneration = 0;
  int _gaslessStatusRequestGeneration = 0;

  WithdrawFormBloc({
    required Asset asset,
    required KomodoDefiSdk sdk,
    required Mm2Api mm2Api,
    WalletType? walletType,
    String? initialRecipient,
    PubkeyInfo? initialSourceAddress,
    bool initialGaslessEnabled = true,
    bool initialIsMax = false,
    bool lockSourceSelection = false,
    bool? gaslessFeatureConfigured,
    WithdrawalAuthorizationGuard? authorizationGuard,
    String? authorizationFailureMessage,
  }) : _sdk = sdk,
       _walletType = walletType,
       _initialRecipient = initialRecipient,
       _initialSourceAddress = initialSourceAddress,
       _initialGaslessEnabled = initialGaslessEnabled,
       _initialIsMax = initialIsMax,
       _lockSourceSelection = lockSourceSelection,
       _authorizationGuard = authorizationGuard,
       _authorizationFailureMessage = authorizationFailureMessage,
       super(
         WithdrawFormState(
           asset: asset,
           step: WithdrawFormStep.fill,
           recipientAddress: '',
           amount: '0',
           walletType: walletType,
           isGaslessFeatureConfigured:
               gaslessFeatureConfigured ?? asset.isTronGaslessConfiguredAsset,
           gaslessPendingStoreReady:
               walletType == WalletType.trezor ||
               !asset.isTronGaslessRecoveryEligibleAsset,
           selectedSourceAddress: initialSourceAddress,
           isSourceSelectionLocked: lockSourceSelection,
           isGaslessEnabled: initialGaslessEnabled,
         ),
       ) {
    on<WithdrawFormRecipientChanged>(
      _onRecipientChanged,
      transformer: restartable(),
    );
    on<WithdrawFormAmountChanged>(_onAmountChanged);
    on<WithdrawFormSourceChanged>(_onSourceChanged);
    on<WithdrawFormMaxAmountEnabled>(_onMaxAmountEnabled);
    on<WithdrawFormCustomFeeEnabled>(_onCustomFeeEnabled);
    on<WithdrawFormCustomFeeChanged>(_onFeeChanged);
    on<WithdrawFormGaslessToggled>(_onGaslessToggled);
    on<WithdrawFormGaslessStatusRequested>(
      _onGaslessStatusRequested,
      transformer: restartable(),
    );
    on<WithdrawFormFeePriorityChanged>(_onFeePriorityChanged);
    on<WithdrawFormMemoChanged>(_onMemoChanged);
    on<WithdrawFormIbcTransferEnabled>(_onIbcTransferEnabled);
    on<WithdrawFormIbcChannelChanged>(_onIbcChannelChanged);
    on<WithdrawFormPreviewSubmitted>(
      _onPreviewSubmitted,
      transformer: droppable(),
    );
    on<WithdrawFormSubmitted>(_onSubmitted, transformer: droppable());
    on<WithdrawFormGaslessTraceCheckRequested>(
      _onGaslessTraceCheckRequested,
      transformer: restartable(),
    );
    on<WithdrawFormPendingGaslessLoadRequested>(
      _onPendingGaslessLoadRequested,
      transformer: restartable(),
    );
    on<WithdrawFormPendingUseStandardRequested>(_onPendingUseStandardRequested);
    on<WithdrawFormTronPreviewTicked>(_onTronPreviewTicked);
    on<WithdrawFormTronPreviewRefreshRequested>(
      _onTronPreviewRefreshRequested,
      transformer: droppable(),
    );
    on<WithdrawFormCancelled>(_onCancelled);
    on<WithdrawFormReset>(_onReset);
    on<WithdrawFormStepReverted>(_onStepReverted);
    on<WithdrawFormSourcesLoadRequested>(_onSourcesLoadRequested);
    on<WithdrawFormFeeOptionsRequested>(_onFeeOptionsRequested);
    on<WithdrawFormConvertAddressRequested>(_onConvertAddress);

    add(const WithdrawFormSourcesLoadRequested());
    add(const WithdrawFormFeeOptionsRequested());
    if (_canRecoverGaslessAsset(asset)) {
      add(const WithdrawFormPendingGaslessLoadRequested());
    }
    if (initialRecipient != null && initialRecipient.isNotEmpty) {
      add(WithdrawFormRecipientChanged(initialRecipient));
    }
    if (initialIsMax) {
      add(const WithdrawFormMaxAmountEnabled(true));
    }
  }

  Future<bool> _authorizeWithdrawal(Emitter<WithdrawFormState> emit) async {
    if (!_lockedPrefillIsIntact(state)) {
      _cancelTronPreviewTimer();
      emit(
        state.copyWith(
          step: WithdrawFormStep.fill,
          preview: () => null,
          authorizedRecipientAmount: () => null,
          isSending: false,
          isAwaitingTrezorConfirmation: false,
          previewError: () => TextError(
            error:
                _authorizationFailureMessage ?? LocaleKeys.somethingWrong.tr(),
          ),
          transactionError: () => null,
          confirmStepError: () => null,
          previewExpiresAt: () => null,
          previewSecondsRemaining: () => null,
          isPreviewExpired: false,
          isPreviewRefreshing: false,
        ),
      );
      return false;
    }

    final guard = _authorizationGuard;
    if (guard == null) return true;

    var authorized = false;
    try {
      authorized = await guard();
    } catch (_) {
      authorized = false;
    }
    if (emit.isDone) return false;
    if (authorized) return true;

    _cancelTronPreviewTimer();
    emit(
      state.copyWith(
        step: WithdrawFormStep.fill,
        preview: () => null,
        authorizedRecipientAmount: () => null,
        isSending: false,
        isAwaitingTrezorConfirmation: false,
        previewError: () => TextError(
          error:
              _authorizationFailureMessage ??
              LocaleKeys.receiveGaslessPausedNotice.tr(),
        ),
        gaslessQuoteFailure: () => state.useGasless
            ? const GaslessQuoteFailure(
                failureClass: GaslessQuoteFailureClass.capabilityNotReady,
                retryable: true,
              )
            : null,
        transactionError: () => null,
        confirmStepError: () => null,
        previewExpiresAt: () => null,
        previewSecondsRemaining: () => null,
        isPreviewExpired: false,
        isPreviewRefreshing: false,
      ),
    );
    return false;
  }

  bool _lockedPrefillIsIntact(WithdrawFormState candidate) {
    if (!_lockSourceSelection) return true;

    final initialSourceAddress = _initialSourceAddress?.address;
    final initialRecipient = _initialRecipient?.trim();
    return initialSourceAddress != null &&
        candidate.selectedSourceAddress?.address == initialSourceAddress &&
        initialRecipient != null &&
        initialRecipient.isNotEmpty &&
        candidate.recipientAddress.trim() == initialRecipient &&
        candidate.isGaslessEnabled == _initialGaslessEnabled &&
        candidate.useGasless == _initialGaslessEnabled &&
        candidate.isMaxAmount == _initialIsMax;
  }

  bool _isTronAsset(Asset asset) =>
      asset.protocol is TrxProtocol || asset.protocol is Trc20Protocol;

  ({bool usesGasless, bool isConsistent}) _previewRail(
    WithdrawalPreview preview,
  ) {
    final hasGaslessFee = preview.fee is FeeInfoTronGasless;
    final hasGaslessRelay = preview.gaslessRelayPayload != null;
    return (
      usesGasless: hasGaslessFee && hasGaslessRelay,
      isConsistent: hasGaslessFee == hasGaslessRelay,
    );
  }

  bool _previewUsesGaslessRail(WithdrawalPreview preview) =>
      _previewRail(preview).usesGasless;

  bool _canRecoverGaslessAsset(Asset asset) =>
      _walletType != WalletType.trezor &&
      asset.isTronGaslessRecoveryEligibleAsset;

  void _cancelTronPreviewTimer() {
    _tronPreviewTimer?.cancel();
    _tronPreviewTimer = null;
  }

  DateTime? _buildPreviewExpiryAt(
    WithdrawFormState state,
    WithdrawalPreview preview,
  ) {
    if (!_isTronAsset(state.asset)) {
      return null;
    }

    final isGaslessPreview = _previewUsesGaslessRail(preview);
    if (isGaslessPreview) {
      final signedAuthorization =
          preview.gaslessRelayPayload?.signedAuthorization;
      if (signedAuthorization == null) {
        return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
      // KDF represents this value as U256. A value outside Dart's DateTime
      // range cannot drive the preview countdown safely, so treat it as an
      // unusable preview instead of silently disabling expiry checks.
      return signedAuthorization.expiresAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    return DateTime.fromMillisecondsSinceEpoch(
      preview.timestamp * 1000,
      isUtc: true,
    ).add(
      const Duration(seconds: WithdrawFormState.tronPreviewExpirationSeconds),
    );
  }

  int _calculatePreviewSecondsRemaining(DateTime expiryAt) {
    final remainingMs = expiryAt
        .difference(DateTime.now().toUtc())
        .inMilliseconds;
    if (remainingMs <= 0) {
      return 0;
    }

    return (remainingMs / 1000).ceil();
  }

  void _startTronPreviewTimer(WithdrawFormState state) {
    _cancelTronPreviewTimer();

    if (!_isTronAsset(state.asset) ||
        state.step != WithdrawFormStep.confirm ||
        state.preview == null ||
        state.previewExpiresAt == null ||
        state.isPreviewExpired) {
      return;
    }

    _tronPreviewTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      add(const WithdrawFormTronPreviewTicked());
    });
  }

  ({TextError error, GaslessQuoteFailure? gaslessFailure})?
  _previewGuardFailure() {
    if (_isUnsupportedSiaHardwareWalletFlow) {
      return (
        error: TextError(error: _unsupportedSiaHardwareWalletMessage),
        gaslessFailure: null,
      );
    }

    if (_isSelfTransfer) {
      return (
        error: TextError(error: LocaleKeys.cannotSendToSelf.tr()),
        gaslessFailure: state.useGasless
            ? const GaslessQuoteFailure(
                failureClass: GaslessQuoteFailureClass.invalidAddress,
                retryable: false,
              )
            : null,
      );
    }

    if (state.useGasless && state.hasUnresolvedGaslessTransfer) {
      return (
        error: TextError(error: LocaleKeys.withdrawGaslessPendingTransfer.tr()),
        gaslessFailure: const GaslessQuoteFailure(
          failureClass: GaslessQuoteFailureClass.transferPending,
          retryable: false,
        ),
      );
    }

    // The GasFree provider reported itself unreachable: custody funds are
    // safe on-chain but a gasless send cannot be built right now. Block with
    // an honest message — never suggest TRX or switching to the native rail
    // (custody funds are not natively spendable).
    if (state.isGaslessProviderUnavailable) {
      return (
        error: TextError(
          error: LocaleKeys.withdrawGaslessProviderUnavailable.tr(
            args: [state.asset.id.id],
          ),
        ),
        gaslessFailure: const GaslessQuoteFailure(
          failureClass: GaslessQuoteFailureClass.serviceUnavailable,
          retryable: true,
        ),
      );
    }

    if (state.useGasless &&
        state.gaslessAvailability == GaslessAvailability.unsupported) {
      return (
        error: TextError(error: LocaleKeys.withdrawGaslessUnsupported.tr()),
        gaslessFailure: const GaslessQuoteFailure(
          failureClass: GaslessQuoteFailureClass.unsupported,
          retryable: false,
        ),
      );
    }

    if (state.useGasless &&
        state.gaslessAvailability == GaslessAvailability.securityMismatch) {
      return (
        error: TextError(
          error: LocaleKeys.withdrawGaslessSecurityMismatch.tr(),
        ),
        gaslessFailure: const GaslessQuoteFailure(
          failureClass: GaslessQuoteFailureClass.securityMismatch,
          retryable: false,
        ),
      );
    }

    if (state.useGasless &&
        state.gaslessAvailability == GaslessAvailability.pendingTransfer) {
      return (
        error: TextError(error: LocaleKeys.withdrawGaslessPendingTransfer.tr()),
        gaslessFailure: const GaslessQuoteFailure(
          failureClass: GaslessQuoteFailureClass.transferPending,
          retryable: false,
        ),
      );
    }

    if (state.useGasless && state.isGaslessSendBlocked) {
      return (
        error: TextError(
          error: LocaleKeys.withdrawGaslessUnavailableBlocked.tr(),
        ),
        gaslessFailure: GaslessQuoteFailure(
          failureClass: GaslessQuoteFailureClass.capabilityNotReady,
          retryable: state.gaslessAvailability != GaslessAvailability.disabled,
        ),
      );
    }

    return null;
  }

  Future<WithdrawalPreview> _generatePreview(
    WithdrawFormState requestState,
  ) async {
    final params = requestState.toWithdrawParameters();
    return _sdk.withdrawals.previewWithdrawal(params);
  }

  bool _matchesPreviewRequest(
    WithdrawFormState requestState,
    WithdrawFormState currentState,
  ) {
    final requestParams = requestState.toWithdrawParameters();
    final currentParams = currentState.toWithdrawParameters();
    if (requestParams == currentParams) {
      return true;
    }

    if (_isBackgroundFeePriorityDefault(requestState, currentState)) {
      final requestWithDefaultFeePriority = requestState.copyWith(
        selectedFeePriority: () => currentState.selectedFeePriority,
      );
      return requestWithDefaultFeePriority.toWithdrawParameters() ==
          currentParams;
    }

    return false;
  }

  bool _isBackgroundFeePriorityDefault(
    WithdrawFormState requestState,
    WithdrawFormState currentState,
  ) {
    return !requestState.isCustomFee &&
        !currentState.isCustomFee &&
        requestState.selectedFeePriority == null &&
        currentState.selectedFeePriority == WithdrawalFeeLevel.medium &&
        currentState.feeOptions != null;
  }

  void _emitPreviewState(
    Emitter<WithdrawFormState> emit,
    WithdrawFormState requestState,
    WithdrawalPreview preview, {
    required bool moveToConfirm,
  }) {
    final currentState = state;
    if (!_matchesPreviewRequest(requestState, currentState)) {
      emit(
        currentState.copyWith(
          isSending: false,
          isPreviewRefreshing: false,
          isAwaitingTrezorConfirmation: false,
        ),
      );
      _cancelTronPreviewTimer();
      return;
    }

    final previewRail = _previewRail(preview);
    if (!previewRail.isConsistent ||
        currentState.useGasless != previewRail.usesGasless) {
      _cancelTronPreviewTimer();
      emit(
        currentState.copyWith(
          step: WithdrawFormStep.fill,
          preview: () => null,
          authorizedRecipientAmount: () => null,
          isSending: false,
          isPreviewRefreshing: false,
          previewError: () =>
              TextError(error: LocaleKeys.withdrawGaslessSecurityMismatch.tr()),
          gaslessQuoteFailure: () => const GaslessQuoteFailure(
            failureClass: GaslessQuoteFailureClass.securityMismatch,
            retryable: false,
          ),
          isAwaitingTrezorConfirmation: false,
        ),
      );
      return;
    }

    final expiryAt = _buildPreviewExpiryAt(currentState, preview);
    final secondsRemaining = expiryAt == null
        ? null
        : _calculatePreviewSecondsRemaining(expiryAt);
    final isExpired = secondsRemaining != null && secondsRemaining <= 0;
    final authorizedRecipientAmount = _authorizedRecipientAmount(
      currentState,
      preview,
    );
    final nextState = currentState.copyWith(
      preview: () => preview,
      authorizedRecipientAmount: () => authorizedRecipientAmount,
      step: moveToConfirm ? WithdrawFormStep.confirm : currentState.step,
      previewError: () => null,
      transactionError: () => null,
      confirmStepError: () => isExpired
          ? TextError(error: LocaleKeys.withdrawTronPreviewExpired.tr())
          : null,
      isSending: false,
      isPreviewRefreshing: false,
      isPreviewExpired: isExpired,
      previewExpiresAt: () => expiryAt,
      previewSecondsRemaining: () => secondsRemaining,
      isAwaitingTrezorConfirmation: false,
    );

    emit(nextState);

    if (isExpired) {
      _cancelTronPreviewTimer();
      return;
    }

    _startTronPreviewTimer(nextState);
  }

  Decimal _authorizedRecipientAmount(
    WithdrawFormState requestState,
    WithdrawalPreview preview,
  ) {
    if (!requestState.isMaxAmount) {
      final explicitAmount = Decimal.tryParse(
        normalizeDecimalString(requestState.amount),
      );
      if (explicitAmount != null && explicitAmount > Decimal.zero) {
        return explicitAmount;
      }
    }

    if (preview.fee is FeeInfoTronGasless) {
      // `totalAmount` is the recipient amount KDF signed into the preview.
      // Never reverse-calculate it from `spentByMe - fee`: the provider may
      // settle below the signed maximum fee without changing what was sent.
      return preview.balanceChanges.totalAmount;
    }

    final net = preview.balanceChanges.netChange.abs();
    return net > Decimal.zero ? net : preview.balanceChanges.spentByMe;
  }

  String _formatErrorMessage(Object error) {
    final structured = _formatStructuredGaslessShortfall(error);
    if (structured != null) return structured;
    final resolved = formatKdfUserFacingError(error);
    if (state.useGasless) {
      // GasFree lifecycle and endpoint failures are typed by the SDK. Never
      // infer a provider state from arbitrary response text; an untyped
      // submission failure gets a privacy-safe generic message.
      final source = error is SdkError ? error.source : error;
      final isTyped =
          error is SdkError ||
          source is GaslessTransferException ||
          source is WithdrawalException;
      return isTyped ? resolved : LocaleKeys.somethingWrong.tr();
    }
    return _normalizeCommonErrors(resolved);
  }

  /// KDF's structured GasFree shortfall errors (`InsufficientGasFreeBalance`
  /// [ForActivation]) carry exact token amounts; render them directly — with
  /// the custody address the wallet already knows — instead of letting the
  /// string normalizers collapse them back into the generic gasless text.
  ///
  /// The SDK's arg orders are a stable contract (see sdk_error_mapper.dart):
  /// base `[gasfreeAddress, available, coin, required, coin, coin]`,
  /// activation `[gasfreeAddress, available, coin, required, coin,
  /// activationFee, coin, coin]`. KDF does not send the custody address in
  /// the payload, so arg 0 is usually empty and substituted here.
  String? _formatStructuredGaslessShortfall(Object error) {
    if (error is! SdkError) return null;
    final isActivation =
        error.messageKey ==
        LocaleKeys.withdrawGaslessInsufficientGasFreeBalanceForActivation;
    final isBase =
        error.messageKey ==
        LocaleKeys.withdrawGaslessInsufficientGasFreeBalance;
    if (!isBase && !isActivation) return null;

    final args = List<String>.of(error.messageArgs);
    if (args.length != (isActivation ? 8 : 6)) return null;

    // KDF reports the raw config id (e.g. USDT-TRC20) as the coin; show the
    // clean ticker. Value-matched (not positional) so amounts are untouched.
    for (var i = 1; i < args.length; i++) {
      if (args[i] == state.asset.id.id) {
        args[i] = state.asset.id.symbol.configSymbol;
      }
    }

    if (args.first.isEmpty) {
      args[0] =
          state.gaslessAccountStatus?.gasfreeAddress ??
          state.selectedSourceAddress?.gasfreeAddress ??
          '';
    }
    if (args.first.isEmpty) {
      // Custody address unknown (status fetch failed and no source selected):
      // fall back to the address-less shortfall copy rather than rendering
      // "Your gasless address  holds …". `required` already includes any
      // activation fee, so the shared message stays accurate.
      return LocaleKeys.withdrawGaslessInsufficientBalance.tr(
        args: [args[1], args[2], args[3], args[4], args[4]],
      );
    }
    args[0] = truncateMiddleSymbols(args[0]);
    return error.messageKey.tr(args: args);
  }

  TextError _buildTextError(Object error) {
    return TextError(
      error: _formatErrorMessage(error),
      technicalDetails: extractKdfTechnicalDetails(error),
    );
  }

  GaslessQuoteFailure _gaslessQuoteFailureFrom(Object error) {
    final sdkError = error is SdkError ? error : null;
    final source = sdkError?.source ?? error;

    // Endpoint-scoped GasFree balance shortfalls intentionally retain a
    // GaslessTransferException as their source, but the mapped SDK category is
    // the authoritative user/analytics classification.
    if (sdkError?.code == SdkErrorCode.insufficientFunds) {
      return GaslessQuoteFailure(
        failureClass: GaslessQuoteFailureClass.insufficientFunds,
        retryable: sdkError!.retryable,
      );
    }
    if (source is GaslessTransferException) {
      return GaslessQuoteFailure(
        failureClass: _quoteFailureClassForGaslessCode(source.code),
        retryable: source.retryable,
      );
    }
    if (source is WithdrawalException) {
      return GaslessQuoteFailure(
        failureClass: _quoteFailureClassForWithdrawalCode(source.code),
        retryable: source.code == WithdrawalErrorCode.networkError,
      );
    }
    if (sdkError != null) {
      return GaslessQuoteFailure(
        failureClass: _quoteFailureClassForSdkCode(sdkError.code),
        retryable: sdkError.retryable,
      );
    }
    if (source is TimeoutException) {
      return const GaslessQuoteFailure(
        failureClass: GaslessQuoteFailureClass.timeout,
        retryable: true,
      );
    }
    if (source is FormatException || source is ArgumentError) {
      return const GaslessQuoteFailure(
        failureClass: GaslessQuoteFailureClass.securityMismatch,
        retryable: false,
      );
    }
    return const GaslessQuoteFailure(
      failureClass: GaslessQuoteFailureClass.unknown,
      retryable: false,
    );
  }

  GaslessQuoteFailureClass _quoteFailureClassForGaslessCode(
    GaslessTransferErrorCode code,
  ) => switch (code) {
    GaslessTransferErrorCode.capabilityNotReady =>
      GaslessQuoteFailureClass.capabilityNotReady,
    GaslessTransferErrorCode.securePersistenceUnavailable ||
    GaslessTransferErrorCode.storageMigrationRequired =>
      GaslessQuoteFailureClass.persistenceUnavailable,
    GaslessTransferErrorCode.invalidSignedPreview =>
      GaslessQuoteFailureClass.invalidPreview,
    GaslessTransferErrorCode.configurationInvalid ||
    GaslessTransferErrorCode.wrongCoinType ||
    GaslessTransferErrorCode.runtimeMissing ||
    GaslessTransferErrorCode.coinNotFound ||
    GaslessTransferErrorCode.notEthCoin ||
    GaslessTransferErrorCode.gaslessNotConfigured =>
      GaslessQuoteFailureClass.configurationInvalid,
    GaslessTransferErrorCode.invalidPayload =>
      GaslessQuoteFailureClass.invalidPayload,
    GaslessTransferErrorCode.invalidAddress =>
      GaslessQuoteFailureClass.invalidAddress,
    GaslessTransferErrorCode.maxFeeExceeded =>
      GaslessQuoteFailureClass.maxFeeExceeded,
    GaslessTransferErrorCode.serviceProviderMismatch ||
    GaslessTransferErrorCode.tokenMismatch ||
    GaslessTransferErrorCode.tokenDecimalMismatch ||
    GaslessTransferErrorCode.custodyAddressMismatch ||
    GaslessTransferErrorCode.signatureMismatch ||
    GaslessTransferErrorCode.walletOwnershipMismatch ||
    GaslessTransferErrorCode.responseMismatch ||
    GaslessTransferErrorCode.finalFeeExceeded ||
    GaslessTransferErrorCode.traceInvalid ||
    GaslessTransferErrorCode.traceNotFound ||
    GaslessTransferErrorCode.invalidTraceId =>
      GaslessQuoteFailureClass.securityMismatch,
    GaslessTransferErrorCode.authenticationRejected =>
      GaslessQuoteFailureClass.authenticationFailed,
    GaslessTransferErrorCode.unsupportedToken ||
    GaslessTransferErrorCode.coinNotSupported =>
      GaslessQuoteFailureClass.unsupported,
    GaslessTransferErrorCode.authorizationExpired =>
      GaslessQuoteFailureClass.authorizationExpired,
    GaslessTransferErrorCode.pendingTransfer =>
      GaslessQuoteFailureClass.transferPending,
    GaslessTransferErrorCode.relayRejected =>
      GaslessQuoteFailureClass.relayRejected,
    GaslessTransferErrorCode.rateLimited =>
      GaslessQuoteFailureClass.rateLimited,
    GaslessTransferErrorCode.providerUnavailable ||
    GaslessTransferErrorCode.providerError ||
    GaslessTransferErrorCode.tronRpcUnavailable ||
    GaslessTransferErrorCode.internalError ||
    GaslessTransferErrorCode.traceStreamEnableError ||
    GaslessTransferErrorCode.traceStreamInternal ||
    GaslessTransferErrorCode.traceUnavailable =>
      GaslessQuoteFailureClass.serviceUnavailable,
    GaslessTransferErrorCode.providerTimeout =>
      GaslessQuoteFailureClass.timeout,
    GaslessTransferErrorCode.submissionOutcomeUnknown ||
    GaslessTransferErrorCode.relayFailedFinal =>
      GaslessQuoteFailureClass.unknown,
  };

  GaslessQuoteFailureClass _quoteFailureClassForSdkCode(SdkErrorCode code) =>
      switch (code) {
        SdkErrorCode.networkUnavailable ||
        SdkErrorCode.transport => GaslessQuoteFailureClass.serviceUnavailable,
        SdkErrorCode.timeout => GaslessQuoteFailureClass.timeout,
        SdkErrorCode.invalidResponse =>
          GaslessQuoteFailureClass.securityMismatch,
        SdkErrorCode.insufficientFunds ||
        SdkErrorCode.insufficientGas ||
        SdkErrorCode.insufficientFeeBalance ||
        SdkErrorCode.zeroBalance ||
        SdkErrorCode.amountTooLow => GaslessQuoteFailureClass.insufficientFunds,
        SdkErrorCode.invalidAddress => GaslessQuoteFailureClass.invalidAddress,
        SdkErrorCode.invalidFee ||
        SdkErrorCode.invalidMemo => GaslessQuoteFailureClass.invalidPayload,
        SdkErrorCode.assetNotActivated ||
        SdkErrorCode.assetNotFound ||
        SdkErrorCode.activationFailed =>
          GaslessQuoteFailureClass.capabilityNotReady,
        SdkErrorCode.userCancelled => GaslessQuoteFailureClass.cancelled,
        SdkErrorCode.notSupported => GaslessQuoteFailureClass.unsupported,
        SdkErrorCode.authInvalidCredentials ||
        SdkErrorCode.authUnauthorized ||
        SdkErrorCode.authWalletNotFound =>
          GaslessQuoteFailureClass.authenticationFailed,
        SdkErrorCode.hardwareFailure ||
        SdkErrorCode.general => GaslessQuoteFailureClass.unknown,
      };

  GaslessQuoteFailureClass _quoteFailureClassForWithdrawalCode(
    WithdrawalErrorCode code,
  ) => switch (code) {
    WithdrawalErrorCode.insufficientFunds =>
      GaslessQuoteFailureClass.insufficientFunds,
    WithdrawalErrorCode.invalidAddress =>
      GaslessQuoteFailureClass.invalidAddress,
    WithdrawalErrorCode.networkError =>
      GaslessQuoteFailureClass.serviceUnavailable,
    WithdrawalErrorCode.userCancelled => GaslessQuoteFailureClass.cancelled,
    WithdrawalErrorCode.contractError =>
      GaslessQuoteFailureClass.securityMismatch,
    WithdrawalErrorCode.gasEstimateFailed ||
    WithdrawalErrorCode.transactionFailed ||
    WithdrawalErrorCode.unknownError => GaslessQuoteFailureClass.unknown,
  };

  String _normalizeCommonErrors(String message) {
    final normalized = message.toLowerCase();

    if (normalized.contains('cannot transfer') &&
        normalized.contains('to yourself')) {
      return LocaleKeys.cannotSendToSelf.tr();
    }

    if (normalized.contains('insufficient') &&
        (normalized.contains('gas') || normalized.contains('fee'))) {
      return LocaleKeys.notEnoughBalanceForGasError.tr();
    }

    if (normalized.contains('insufficient funds') ||
        normalized.contains('not sufficient balance')) {
      return LocaleKeys.kdfErrorNotSufficientBalance.tr();
    }

    if (normalized.contains('failed to fetch') ||
        normalized.contains('network error') ||
        normalized.contains('timed out') ||
        normalized.contains('timeout')) {
      return LocaleKeys.kdfErrorTransport.tr();
    }

    if (message.trim().isEmpty) {
      return LocaleKeys.somethingWrong.tr();
    }

    return message;
  }

  Future<void> _onSourcesLoadRequested(
    WithdrawFormSourcesLoadRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    try {
      // PubkeyManager captures and revalidates the authenticated wallet around
      // cache access and refresh. Do not consume the asset-only synchronous
      // cache here because it can briefly still belong to the previous wallet
      // while an asynchronous auth-change event is in flight.
      final pubkeys = await state.asset.getPubkeys(_sdk);
      final gaslessCandidates = canonicalTronGaslessSourceCandidates(
        pubkeys.keys,
        isHdWallet: state.walletType == WalletType.hdwallet,
      );
      final hasAmbiguousGaslessSources = gaslessCandidates.length > 1;
      final canonicalGaslessKey = gaslessCandidates.length == 1
          ? gaslessCandidates.single
          : null;
      final fundedStandardKeys = pubkeys.keys
          .where((key) => key.balance.total > Decimal.zero)
          .toList(growable: false);

      // Keep every canonical candidate in state so ambiguity remains visible
      // to toggle/reset/UI paths. Only funded EOAs are eligible for Standard
      // selection, while one zero-balance canonical signer may still represent
      // a funded GasFree custody account.
      final retainedKeys = pubkeys.keys
          .where(
            (key) =>
                gaslessCandidates.contains(key) ||
                key.balance.total > Decimal.zero,
          )
          .toList(growable: false);
      final filteredPubkeys = AssetPubkeys(
        assetId: pubkeys.assetId,
        keys: retainedKeys,
        availableAddressesCount: pubkeys.availableAddressesCount,
        syncStatus: pubkeys.syncStatus,
      );

      final gaslessWasRequested =
          state.isGaslessSupported &&
          state.isGaslessEnabled &&
          !state.hasUnresolvedGaslessTransfer;
      final canUseGasless =
          gaslessWasRequested &&
          canonicalGaslessKey != null &&
          !hasAmbiguousGaslessSources;
      final current = state.selectedSourceAddress;
      final lockedSourceAddress = _initialSourceAddress?.address;
      final lockedSource = _lockSourceSelection
          ? pubkeys.keys.firstWhereOrNull(
              (key) =>
                  key.address == lockedSourceAddress &&
                  (_initialGaslessEnabled || key.balance.total > Decimal.zero),
            )
          : null;
      final newSelection = _lockSourceSelection
          ? lockedSource
          : canUseGasless
          ? canonicalGaslessKey
          : current != null
          ? fundedStandardKeys.firstWhereOrNull(
                  (key) => key.address == current.address,
                ) ??
                (fundedStandardKeys.length == 1
                    ? fundedStandardKeys.single
                    : null)
          : (fundedStandardKeys.length == 1 ? fundedStandardKeys.single : null);
      final nextAvailability = hasAmbiguousGaslessSources
          ? GaslessAvailability.securityMismatch
          : gaslessWasRequested && canonicalGaslessKey == null
          ? GaslessAvailability.unsupported
          : state.gaslessAvailability;
      final sourceError = newSelection != null
          ? null
          : hasAmbiguousGaslessSources
          ? TextError(error: LocaleKeys.withdrawGaslessSecurityMismatch.tr())
          : gaslessWasRequested
          ? TextError(
              error: LocaleKeys.withdrawGaslessNoSourceAddress.tr(
                args: [state.asset.id.id],
              ),
            )
          : TextError(
              error: LocaleKeys.withdrawNoFundedAddresses.tr(
                args: [state.asset.id.name],
              ),
            );

      emit(
        state.copyWith(
          pubkeys: () => filteredPubkeys,
          networkError: () => sourceError,
          selectedSourceAddress: () => newSelection,
          isGaslessEnabled: _lockSourceSelection
              ? _initialGaslessEnabled && canUseGasless
              : canUseGasless,
          gaslessAccountStatus: hasAmbiguousGaslessSources ? () => null : null,
          gaslessStatusFetchedAt: hasAmbiguousGaslessSources
              ? () => null
              : null,
          isGaslessStatusLoading: hasAmbiguousGaslessSources
              ? false
              : state.isGaslessStatusLoading,
          gaslessAvailability: nextAvailability,
        ),
      );
      if (canUseGasless) {
        add(const WithdrawFormGaslessStatusRequested());
      }
      // A max amount chosen before sources finished loading (e.g. the
      // consolidation prefill) was computed against a null balance —
      // recompute it now that the source address is known.
      if (state.isMaxAmount) {
        add(const WithdrawFormMaxAmountEnabled(true));
      }
    } catch (e) {
      emit(
        state.copyWith(
          networkError: () => TextError(
            error: _formatErrorMessage(e),
            technicalDetails: extractKdfTechnicalDetails(e),
          ),
        ),
      );
    }
  }

  FeeInfo? _getDefaultFee() {
    final protocol = state.asset.protocol;
    if (protocol is Erc20Protocol) {
      return FeeInfo.ethGasEip1559(
        coin: state.asset.id.id,
        maxFeePerGas: Decimal.parse('0.00000002'),
        maxPriorityFeePerGas: Decimal.parse('0.000000001'),
        gas: 21000,
      );
    }
    if (protocol is QtumProtocol) {
      return FeeInfo.qrc20Gas(
        coin: state.asset.id.id,
        gasPrice: Decimal.parse('0.00000040'),
        gasLimit: 250000,
      );
    }
    if (protocol is TendermintProtocol) {
      return FeeInfo.cosmosGas(
        coin: state.asset.id.id,
        gasPrice: Decimal.parse('0.025'),
        gasLimit: 200000,
      );
    }
    if (protocol is UtxoProtocol) {
      final decimals = state.asset.id.chainId.decimals ?? 8;
      final feeAtomic = protocol.txFee ?? 10000;
      return FeeInfo.utxoFixed(
        coin: state.asset.id.id,
        amount: _atomicToDecimal(feeAtomic, decimals),
      );
    }
    return null;
  }

  Future<void> _onRecipientChanged(
    WithdrawFormRecipientChanged event,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    if (_lockSourceSelection &&
        event.address.trim() != _initialRecipient?.trim()) {
      return;
    }

    try {
      final trimmedAddress = event.address.trim();

      // Optimistically update the address and clear previous errors so the UI
      // reflects user input immediately. Validation results will update the
      // state again when available.
      emit(
        state.copyWith(
          recipientAddress: trimmedAddress,
          recipientAddressError: () => null,
        ),
      );

      // First check if it's an EVM address that needs conversion
      if (state.asset.protocol is Erc20Protocol &&
          _isValidEthAddressFormat(trimmedAddress) &&
          !_hasEthAddressMixedCase(trimmedAddress)) {
        try {
          // Try to convert to mixed case format if possible
          final result = await _sdk.addresses.convertFormat(
            asset: state.asset,
            address: trimmedAddress,
            format: const AddressFormat(format: 'mixedcase', network: ''),
          );

          // Validate the converted address
          final validationResult = await _sdk.addresses.validateAddress(
            asset: state.asset,
            address: result.convertedAddress,
          );
          if (state.isSending ||
              state.step != WithdrawFormStep.fill ||
              state.recipientAddress != trimmedAddress) {
            return;
          }
          final isMixedCaseAdddress = result.convertedAddress != trimmedAddress;

          if (validationResult.isValid) {
            emit(
              state.copyWith(
                recipientAddress: result.convertedAddress,
                recipientAddressError: () => null,
                isMixedCaseAddress: isMixedCaseAdddress,
              ),
            );
            return;
          }
        } catch (_) {
          // Conversion failed, continue with normal validation
        }
      }

      // Proceed with normal validation
      final validationResult = await _sdk.addresses.validateAddress(
        asset: state.asset,
        address: trimmedAddress,
      );
      if (state.isSending ||
          state.step != WithdrawFormStep.fill ||
          state.recipientAddress != trimmedAddress) {
        return;
      }
      if (!validationResult.isValid) {
        emit(
          state.copyWith(
            recipientAddress: trimmedAddress,
            recipientAddressError: () =>
                TextError(error: validationResult.invalidReason!),
            isMixedCaseAddress: false,
          ),
        );
        return;
      }

      // For non-EVM addresses
      emit(
        state.copyWith(
          recipientAddress: trimmedAddress,
          recipientAddressError: () => null,
          isMixedCaseAddress: false,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          recipientAddress: event.address.trim(),
          recipientAddressError: () => TextError(
            error: _formatErrorMessage(e),
            technicalDetails: extractKdfTechnicalDetails(e),
          ),
          isMixedCaseAddress: false,
        ),
      );
    }
  }

  /// Checks if the address has valid Ethereum address format
  bool _isValidEthAddressFormat(String address) {
    return address.startsWith('0x') && address.length == 42;
  }

  void _onAmountChanged(
    WithdrawFormAmountChanged event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    if (_lockSourceSelection) return;
    if (state.isMaxAmount) return;

    try {
      // Normalize the amount string to handle locale-specific formats
      final normalizedAmount = normalizeDecimalString(event.amount);
      final amount = Decimal.parse(normalizedAmount);
      // Use the selected address balance if available
      final balance = state.selectedSourceAddress?.balance.spendable;

      if (!state.useGasless && balance != null && amount > balance) {
        emit(
          state.copyWith(
            amount: event.amount,
            amountError: () => TextError(
              error: LocaleKeys.withdrawNotSufficientBalanceError.tr(
                args: [
                  state.asset.id.id,
                  balance.toString(),
                  amount.toString(),
                ],
              ),
            ),
          ),
        );
        return;
      }

      if (amount <= Decimal.zero) {
        emit(
          state.copyWith(
            amount: event.amount,
            amountError: () => TextError(
              error: LocaleKeys.withdrawAmountTooLowError.tr(
                args: [
                  amount.toString(),
                  state.asset.id.id,
                  '0',
                  state.asset.id.id,
                ],
              ),
            ),
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          amount: event.amount,
          amountError: () => null,
          previewError: () => null,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          amount: event.amount,
          amountError: () =>
              TextError(error: LocaleKeys.withdrawInvalidAmountError.tr()),
        ),
      );
    }
  }

  void _onSourceChanged(
    WithdrawFormSourceChanged event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    if (_lockSourceSelection &&
        event.address.address != _initialSourceAddress?.address) {
      return;
    }
    _gaslessStatusRequestGeneration += 1;
    final balance = event.address.balance;
    final canonicalSource = state.canonicalGaslessSource;
    final keepsGaslessSelected =
        state.isGaslessEnabled &&
        !state.hasAmbiguousGaslessSources &&
        !state.hasUnresolvedGaslessTransfer &&
        canonicalSource != null &&
        event.address.address == canonicalSource.address;
    final updatedAmount = state.isMaxAmount && !keepsGaslessSelected
        ? balance.spendable.toString()
        : state.amount;

    emit(
      state.copyWith(
        selectedSourceAddress: () => event.address,
        isGaslessEnabled: keepsGaslessSelected,
        gaslessAccountStatus: keepsGaslessSelected ? () => null : null,
        gaslessStatusFetchedAt: keepsGaslessSelected ? () => null : null,
        isGaslessStatusLoading: keepsGaslessSelected,
        gaslessAvailability: keepsGaslessSelected
            ? GaslessAvailability.checking
            : state.gaslessAvailability,
        networkError: () => null,
        amount: updatedAmount,
        amountError: () => null,
        previewError: () => null,
      ),
    );

    if (keepsGaslessSelected) {
      add(const WithdrawFormGaslessStatusRequested(force: true));
    }

    // Re-validate the amount with the new source address balance
    if (!state.isMaxAmount) {
      add(WithdrawFormAmountChanged(updatedAmount));
    }
  }

  Future<void> _onMaxAmountEnabled(
    WithdrawFormMaxAmountEnabled event,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    if (_lockSourceSelection && event.isEnabled != _initialIsMax) return;
    // Gas-free transfers pay the network fee in the token itself, so the
    // source address legitimately holds zero TRX. Only enforce the parent
    // (TRX) gas balance guard on the native rail.
    if (event.isEnabled &&
        !state.useGasless &&
        state.asset.id.parentId != null) {
      final parentId = state.asset.id.parentId!;
      final parentSpendable = state.isTronAsset
          ? await _selectedSourceParentSpendable(parentId)
          : (await _sdk.balances.getBalance(parentId)).spendable;

      if (parentSpendable == null || parentSpendable <= Decimal.zero) {
        emit(
          state.copyWith(
            isMaxAmount: false,
            // TRON gets a specific message naming TRX and the standard
            // address — this native-rail guard is the one flow (interop /
            // stranded-funds consolidation) honestly allowed to require TRX.
            amountError: () => TextError(
              error: state.isTronAsset
                  ? LocaleKeys.withdrawTronNativeNeedsTrx.tr()
                  : LocaleKeys.notEnoughBalanceForGasError.tr(),
            ),
          ),
        );
        return;
      }
    }

    final balance =
        state.selectedSourceAddress?.balance ?? state.pubkeys?.balance;
    final String maxAmount;
    if (!event.isEnabled) {
      maxAmount = '0';
    } else if (state.useGasless) {
      // When supplied, `gasless::account_status.max_withdrawable` is an
      // advisory display value with transfer/activation fees already netted.
      // The request still sends `isMax: true` with no amount, so a fresh KDF
      // preview remains authoritative for the amount that is signed.
      // Keep an unknown advisory value empty instead of manufacturing zero;
      // the field renders its localized "Maximum" placeholder while KDF is
      // resolving the authoritative max preview.
      maxAmount = state.gaslessMaxWithdrawable?.toString() ?? '';
    } else {
      maxAmount = balance?.spendable.toString() ?? '0';
    }

    emit(
      state.copyWith(
        isMaxAmount: event.isEnabled,
        amount: maxAmount,
        // Account-status maximum and fee fields are advisory only. A fresh
        // `max: true` preview decides whether the transfer is possible and
        // signs the authoritative recipient amount.
        amountError: () => null,
        previewError: () => null, // Clear preview error when toggling max
      ),
    );

    // A missing/stale custody snapshot renders as the "Maximum" placeholder;
    // fetching (TTL-cached) fills in the concrete number when it lands (and
    // re-clears/re-sets the below-fees error if the balance changed).
    if (event.isEnabled && state.useGasless) {
      add(const WithdrawFormGaslessStatusRequested());
    }
  }

  /// Returns the parent-coin balance attached to the exact EOA selected for a
  /// native TRC-20 transfer. A wallet-wide TRX total is unsafe here: TRX on a
  /// different derivation cannot pay the fee for the token-holding source.
  Future<Decimal?> _selectedSourceParentSpendable(AssetId parentId) async {
    final selected = state.selectedSourceAddress;
    if (selected == null) return null;

    final parentAsset = _sdk.assets.fromId(parentId);
    if (parentAsset == null) return null;
    final parentPubkeys = await _sdk.pubkeys.getPubkeys(parentAsset);
    final selectedPath = selected.derivationPath;
    final matching = parentPubkeys.keys.firstWhereOrNull((candidate) {
      if (selectedPath != null && selectedPath.isNotEmpty) {
        return candidate.derivationPath == selectedPath;
      }
      return candidate.address == selected.address;
    });
    return matching?.balance.spendable;
  }

  void _onCustomFeeEnabled(
    WithdrawFormCustomFeeEnabled event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    if (_lockSourceSelection) return;
    final defaultPriority =
        state.selectedFeePriority ??
        (state.feeOptions != null ? WithdrawalFeeLevel.medium : null);
    // If enabling custom fees, set a default fee or reuse from `_getDefaultFee()`
    emit(
      state.copyWith(
        isCustomFee: event.isEnabled,
        customFee: event.isEnabled ? () => _getDefaultFee() : () => null,
        customFeeError: () => null,
        selectedFeePriority: () => event.isEnabled ? null : defaultPriority,
      ),
    );
  }

  void _onGaslessToggled(
    WithdrawFormGaslessToggled event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    if (_lockSourceSelection) return;
    if (!state.isGaslessSupported) return;
    _gaslessStatusRequestGeneration += 1;
    if (event.isEnabled && state.hasAmbiguousGaslessSources) {
      emit(
        state.copyWith(
          isGaslessEnabled: false,
          gaslessAvailability: GaslessAvailability.securityMismatch,
          networkError: () =>
              TextError(error: LocaleKeys.withdrawGaslessSecurityMismatch.tr()),
        ),
      );
      return;
    }
    if (event.isEnabled && state.hasUnresolvedGaslessTransfer) {
      emit(
        state.copyWith(
          isGaslessEnabled: false,
          gaslessAvailability: GaslessAvailability.pendingTransfer,
          networkError: () =>
              TextError(error: LocaleKeys.withdrawGaslessPendingTransfer.tr()),
        ),
      );
      return;
    }
    final canonicalGaslessKey = state.canonicalGaslessSource;
    if (event.isEnabled && canonicalGaslessKey == null) {
      emit(
        state.copyWith(
          isGaslessEnabled: false,
          gaslessAvailability: GaslessAvailability.unsupported,
          networkError: () => TextError(
            error: LocaleKeys.withdrawGaslessNoSourceAddress.tr(
              args: [state.asset.id.id],
            ),
          ),
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        isGaslessEnabled: event.isEnabled,
        selectedSourceAddress: event.isEnabled
            ? () => canonicalGaslessKey
            : null,
        // The rail changed, so every error produced on the previous rail is
        // stale — including the gasless "no source address" network error and
        // any left-over transaction/confirm errors.
        amountError: () => null,
        previewError: () => null,
        networkError: () => null,
        transactionError: () => null,
        confirmStepError: () => null,
        isGaslessStatusLoading: event.isEnabled
            ? state.isGaslessStatusLoading
            : false,
        gaslessStatusMessage: state.hasUnresolvedGaslessTransfer
            ? null
            : () => null,
        gaslessTraceState: state.hasUnresolvedGaslessTransfer
            ? null
            : () => null,
      ),
    );
    add(const WithdrawFormSourcesLoadRequested());
    if (event.isEnabled) {
      add(const WithdrawFormGaslessStatusRequested());
    }
    if (state.isMaxAmount) {
      // Recompute the max on the rail just switched to (custody cap vs EOA).
      add(const WithdrawFormMaxAmountEnabled(true));
    } else {
      // Re-validate on the new rail — but leave a pristine amount ('0')
      // alone, or an untouched field would flag "must be greater than 0".
      final currentAmount = Decimal.tryParse(
        normalizeDecimalString(state.amount),
      );
      if (currentAmount != null && currentAmount > Decimal.zero) {
        add(WithdrawFormAmountChanged(state.amount));
      }
    }
  }

  Future<void> _onGaslessStatusRequested(
    WithdrawFormGaslessStatusRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    await _refreshGaslessStatus(emit, force: event.force);
  }

  Future<bool> _refreshGaslessStatus(
    Emitter<WithdrawFormState> emit, {
    required bool force,
  }) async {
    if (!state.isGaslessSupported) return false;
    if (!state.isGaslessEnabled) return false;
    if (state.hasAmbiguousGaslessSources) {
      emit(
        state.copyWith(
          isGaslessEnabled: false,
          gaslessAccountStatus: () => null,
          gaslessStatusFetchedAt: () => null,
          isGaslessStatusLoading: false,
          gaslessAvailability: GaslessAvailability.securityMismatch,
        ),
      );
      return false;
    }

    final canonicalSource = state.canonicalGaslessSource;
    final expectedGasfreeAddress = canonicalSource?.gasfreeAddress?.trim();
    if (expectedGasfreeAddress == null || expectedGasfreeAddress.isEmpty) {
      emit(
        state.copyWith(
          isGaslessEnabled: false,
          gaslessAccountStatus: () => null,
          gaslessStatusFetchedAt: () => null,
          isGaslessStatusLoading: false,
          gaslessAvailability: GaslessAvailability.unsupported,
        ),
      );
      return false;
    }
    if (state.selectedSourceAddress?.address != canonicalSource!.address) {
      emit(
        state.copyWith(
          isGaslessEnabled: false,
          gaslessAccountStatus: () => null,
          gaslessStatusFetchedAt: () => null,
          isGaslessStatusLoading: false,
          gaslessAvailability: GaslessAvailability.securityMismatch,
        ),
      );
      return false;
    }

    final observedAt = state.gaslessStatusFetchedAt;
    final isFresh =
        observedAt != null &&
        DateTime.now().toUtc().difference(observedAt.toUtc()) <
            _gaslessStatusTtl;
    if (!force &&
        isFresh &&
        state.gaslessAvailability.isVerifiedReady &&
        !state.isGaslessStatusLoading) {
      return true;
    }

    final requestGeneration = ++_gaslessStatusRequestGeneration;
    final requestedAsset = state.asset.id;
    final requestedSourceAddress = canonicalSource.address;
    emit(
      state.copyWith(
        isGaslessStatusLoading: true,
        gaslessAvailability: GaslessAvailability.checking,
        gaslessStatusMessage: () => null,
      ),
    );

    try {
      final status = await _sdk.withdrawals.gaslessAccountStatus(
        requestedAsset,
      );
      if (emit.isDone ||
          requestGeneration != _gaslessStatusRequestGeneration ||
          !state.isGaslessEnabled) {
        return false;
      }

      final currentSource = state.selectedSourceAddress;
      final currentCanonicalSource = state.canonicalGaslessSource;
      if (state.asset.id != requestedAsset ||
          state.hasAmbiguousGaslessSources ||
          currentCanonicalSource?.address != requestedSourceAddress ||
          currentSource?.address != requestedSourceAddress ||
          currentSource?.gasfreeAddress?.trim() != expectedGasfreeAddress) {
        return false;
      }

      _validateGaslessStatusIdentity(status, expectedGasfreeAddress);
      final availability = _availabilityForGaslessStatus(status.availability);
      emit(
        state.copyWith(
          gaslessAccountStatus: () => status,
          gaslessStatusFetchedAt: () => DateTime.now().toUtc(),
          isGaslessStatusLoading: false,
          gaslessAvailability: availability,
          gaslessStatusMessage: () => null,
        ),
      );

      // Re-validate against fresh custody numbers so an advisory Max display
      // or old validation message cannot linger. KDF preview remains the
      // authority for the signed amount and fee.
      if (state.useGasless && state.step == WithdrawFormStep.fill) {
        if (state.isMaxAmount) {
          add(const WithdrawFormMaxAmountEnabled(true));
        } else {
          final currentAmount = Decimal.tryParse(
            normalizeDecimalString(state.amount),
          );
          if (currentAmount != null && currentAmount > Decimal.zero) {
            add(WithdrawFormAmountChanged(state.amount));
          }
        }
      }
      return availability.isVerifiedReady;
    } catch (error, stackTrace) {
      if (emit.isDone ||
          requestGeneration != _gaslessStatusRequestGeneration ||
          !state.isGaslessEnabled) {
        return false;
      }
      _logger.warning(
        'Unable to refresh GasFree account status',
        error,
        stackTrace,
      );
      final errorAvailability = _gaslessAvailabilityForStatusError(error);
      emit(
        state.copyWith(
          isGaslessStatusLoading: false,
          gaslessAvailability:
              errorAvailability ??
              (state.gaslessAccountStatus == null
                  ? GaslessAvailability.temporarilyUnavailable
                  : GaslessAvailability.stale),
          gaslessStatusMessage: () => _formatErrorMessage(error),
        ),
      );
      return false;
    }
  }

  void _validateGaslessStatusIdentity(
    GaslessAccountStatusResponse status,
    String expectedGasfreeAddress,
  ) {
    if (status.gasfreeAddress != expectedGasfreeAddress) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.providerResponse,
        code: GaslessTransferErrorCode.custodyAddressMismatch,
        stage: GaslessTransferStage.status,
        message: 'GasFree custody address does not match the active wallet',
        retryable: false,
        terminal: true,
      );
    }

    if (status.availability == GaslessAccountAvailability.providerUnreachable) {
      return;
    }

    final expectedProvider = tronGaslessServiceProvider.trim();
    if (expectedProvider.isEmpty ||
        status.serviceProvider?.trim() != expectedProvider) {
      throw GaslessTransferException(
        kind: GaslessTransferErrorKind.providerResponse,
        code: GaslessTransferErrorCode.serviceProviderMismatch,
        stage: GaslessTransferStage.status,
        message: 'GasFree service provider does not match the production pin',
        retryable: false,
        terminal: true,
      );
    }
  }

  GaslessAvailability _availabilityForGaslessStatus(
    GaslessAccountAvailability availability,
  ) => switch (availability) {
    GaslessAccountAvailability.available => GaslessAvailability.ready,
    GaslessAccountAvailability.pendingTransfer =>
      GaslessAvailability.pendingTransfer,
    GaslessAccountAvailability.tokenUnsupported =>
      GaslessAvailability.unsupported,
    GaslessAccountAvailability.providerUnreachable =>
      GaslessAvailability.providerUnavailable,
  };

  GaslessAvailability? _gaslessAvailabilityForStatusError(Object error) {
    final source = error is SdkError ? error.source : error;
    if (source is! GaslessTransferException) return null;
    return switch (source.code) {
      GaslessTransferErrorCode.configurationInvalid ||
      GaslessTransferErrorCode.capabilityNotReady ||
      GaslessTransferErrorCode.gaslessNotConfigured ||
      GaslessTransferErrorCode.coinNotFound when !source.retryable =>
        GaslessAvailability.disabled,
      GaslessTransferErrorCode.unsupportedToken ||
      GaslessTransferErrorCode.coinNotSupported ||
      GaslessTransferErrorCode.notEthCoin => GaslessAvailability.unsupported,
      GaslessTransferErrorCode.serviceProviderMismatch ||
      GaslessTransferErrorCode.tokenMismatch ||
      GaslessTransferErrorCode.tokenDecimalMismatch ||
      GaslessTransferErrorCode.custodyAddressMismatch ||
      GaslessTransferErrorCode.signatureMismatch ||
      GaslessTransferErrorCode.walletOwnershipMismatch ||
      GaslessTransferErrorCode.responseMismatch ||
      GaslessTransferErrorCode.finalFeeExceeded ||
      GaslessTransferErrorCode.traceInvalid =>
        GaslessAvailability.securityMismatch,
      _ => null,
    };
  }

  void _onFeeChanged(
    WithdrawFormCustomFeeChanged event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    try {
      _validateFee(event.fee);
      emit(
        state.copyWith(customFee: () => event.fee, customFeeError: () => null),
      );
    } catch (e) {
      emit(
        state.copyWith(customFeeError: () => TextError(error: e.toString())),
      );
    }
  }

  void _onFeePriorityChanged(
    WithdrawFormFeePriorityChanged event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    emit(
      state.copyWith(
        selectedFeePriority: () => event.priority,
        isCustomFee: false,
        customFee: () => null,
        customFeeError: () => null,
      ),
    );
  }

  Future<void> _onFeeOptionsRequested(
    WithdrawFormFeeOptionsRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    try {
      final feeOptions = await _sdk.withdrawals.getFeeOptions(
        state.asset.id.id,
      );
      final shouldSelectDefault =
          !state.isCustomFee &&
          state.selectedFeePriority == null &&
          feeOptions != null;
      emit(
        state.copyWith(
          feeOptions: () => feeOptions,
          selectedFeePriority: () => shouldSelectDefault
              ? WithdrawalFeeLevel.medium
              : state.selectedFeePriority,
        ),
      );
    } catch (_) {
      emit(state.copyWith(feeOptions: () => null));
    }
  }

  void _validateFee(FeeInfo fee) {
    fee.map(
      utxoFixed: (utxo) {
        if (utxo.amount <= Decimal.zero) {
          throw Exception('Fee amount must be greater than 0');
        }
      },
      utxoPerKbyte: (utxo) {
        if (utxo.amount <= Decimal.zero) {
          throw Exception('Fee amount must be greater than 0');
        }
      },
      ethGas: (eth) {
        if (eth.gasPrice <= Decimal.zero) {
          throw Exception('Gas price must be greater than 0');
        }
        if (eth.gas <= 0) {
          throw Exception('Gas limit must be greater than 0');
        }
      },
      ethGasEip1559: (eth) {
        if (eth.maxFeePerGas <= Decimal.zero ||
            eth.maxPriorityFeePerGas <= Decimal.zero) {
          throw Exception('Gas fee values must be greater than 0');
        }
        if (eth.gas <= 0) {
          throw Exception('Gas limit must be greater than 0');
        }
      },
      qrc20Gas: (qrc) {
        if (qrc.gasPrice <= Decimal.zero) {
          throw Exception('Gas price must be greater than 0');
        }
        if (qrc.gasLimit <= 0) {
          throw Exception('Gas limit must be greater than 0');
        }
      },
      cosmosGas: (cosmos) {
        if (cosmos.gasPrice <= Decimal.zero) {
          throw Exception('Gas price must be greater than 0');
        }
        if (cosmos.gasLimit <= 0) {
          throw Exception('Gas limit must be greater than 0');
        }
      },
      tendermint: (tendermint) {
        if (tendermint.amount <= Decimal.zero) {
          throw Exception('Fee amount must be greater than 0');
        }
        if (tendermint.gasLimit <= 0) {
          throw Exception('Gas limit must be greater than 0');
        }
      },
      tron: (_) {
        throw Exception('Custom TRON fees are not supported');
      },
      tronGasless: (_) {
        throw Exception('Custom gas-free TRON fees are not supported');
      },
      sia: (sia) {
        if (sia.amount <= Decimal.zero) {
          throw Exception('Fee amount must be greater than 0');
        }
      },
    );
  }

  void _onMemoChanged(
    WithdrawFormMemoChanged event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    emit(state.copyWith(memo: () => event.memo));
  }

  void _onIbcTransferEnabled(
    WithdrawFormIbcTransferEnabled event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    emit(
      state.copyWith(
        isIbcTransfer: event.isEnabled,
        ibcChannel: event.isEnabled ? () => state.ibcChannel : () => null,
        ibcChannelError: () => null,
      ),
    );
  }

  void _onIbcChannelChanged(
    WithdrawFormIbcChannelChanged event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    if (event.channel.isEmpty) {
      emit(
        state.copyWith(
          ibcChannel: () => event.channel,
          ibcChannelError: () =>
              TextError(error: LocaleKeys.enterIbcChannel.tr()),
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        ibcChannel: () => event.channel,
        ibcChannelError: () => null,
      ),
    );
  }

  Future<void> _onPreviewSubmitted(
    WithdrawFormPreviewSubmitted event,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (!await _authorizeWithdrawal(emit)) return;
    if (state.isGaslessPendingStoreChecking) return;
    if (state.useGasless) {
      await _refreshGaslessStatus(emit, force: true);
      if (emit.isDone) return;
    }
    final requestState = state;
    if (requestState.hasValidationErrors) return;
    final guardFailure = _previewGuardFailure();
    if (guardFailure != null) {
      emit(
        requestState.copyWith(
          previewError: () => guardFailure.error,
          gaslessQuoteFailure: () => guardFailure.gaslessFailure,
          isSending: false,
          isAwaitingTrezorConfirmation: false,
        ),
      );
      // Self-heal: when the block was the provider gate, re-check
      // availability so a recovered provider unblocks the form.
      if (requestState.isGaslessProviderUnavailable) {
        add(const WithdrawFormGaslessStatusRequested(force: true));
      }
      return;
    }

    try {
      _cancelTronPreviewTimer();

      emit(
        requestState.copyWith(
          isSending: true,
          previewError: () => null,
          gaslessQuoteFailure: () => null,
          confirmStepError: () => null,
          isPreviewRefreshing: false,
          isPreviewExpired: false,
          previewExpiresAt: () => null,
          previewSecondsRemaining: () => null,
          isAwaitingTrezorConfirmation: _walletType == WalletType.trezor,
        ),
      );

      final preview = await _generatePreview(requestState);
      _emitPreviewState(emit, requestState, preview, moveToConfirm: true);
    } catch (e) {
      _cancelTronPreviewTimer();

      // Capture FD snapshot when KDF withdrawal preview fails
      if (PlatformTuner.isIOS) {
        try {
          await FdMonitorService().logDetailedStatus();
          final stats = await FdMonitorService().getCurrentCount();
          _logger.info(
            'FD stats at withdrawal preview failure for ${state.asset.id.id}: $stats',
          );
        } catch (fdError, fdStackTrace) {
          _logger.warning('Failed to capture FD stats', fdError, fdStackTrace);
        }
      }

      if (!_matchesPreviewRequest(requestState, state)) {
        emit(
          state.copyWith(
            isSending: false,
            isPreviewRefreshing: false,
            isAwaitingTrezorConfirmation: false,
          ),
        );
        return;
      }

      // Structured KDF balance failures are rendered in the token denomination.
      // There is no TRX-paid top-up: the custody address is the GasFree account.
      emit(
        state.copyWith(
          previewError: () => _buildTextError(e),
          gaslessQuoteFailure: () =>
              requestState.useGasless ? _gaslessQuoteFailureFrom(e) : null,
          isSending: false,
          isPreviewRefreshing: false,
          isAwaitingTrezorConfirmation: false,
        ),
      );
    }
  }

  void _onTronPreviewTicked(
    WithdrawFormTronPreviewTicked event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (!_isTronAsset(state.asset) ||
        state.step != WithdrawFormStep.confirm ||
        state.preview == null) {
      _cancelTronPreviewTimer();
      return;
    }

    final expiryAt = state.previewExpiresAt;
    if (expiryAt == null) {
      _cancelTronPreviewTimer();
      return;
    }

    final secondsRemaining = _calculatePreviewSecondsRemaining(expiryAt);
    if (secondsRemaining > 0) {
      if (secondsRemaining != state.previewSecondsRemaining) {
        emit(
          state.copyWith(
            previewSecondsRemaining: () => secondsRemaining,
            isPreviewExpired: false,
          ),
        );
      }
      return;
    }

    _cancelTronPreviewTimer();
    if (state.isPreviewRefreshing) {
      return;
    }

    emit(
      state.copyWith(previewSecondsRemaining: () => 0, isPreviewExpired: true),
    );
    add(const WithdrawFormTronPreviewRefreshRequested(isAutomatic: true));
  }

  Future<void> _onTronPreviewRefreshRequested(
    WithdrawFormTronPreviewRefreshRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (!await _authorizeWithdrawal(emit)) return;
    final requestState = state;
    if (!_isTronAsset(requestState.asset) ||
        requestState.step != WithdrawFormStep.confirm ||
        requestState.preview == null ||
        requestState.isSending ||
        requestState.isPreviewRefreshing) {
      return;
    }

    final guardFailure = _previewGuardFailure();
    if (guardFailure != null) {
      emit(
        requestState.copyWith(
          isPreviewRefreshing: false,
          isPreviewExpired: true,
          previewSecondsRemaining: () => 0,
          confirmStepError: () => guardFailure.error,
          gaslessQuoteFailure: () => guardFailure.gaslessFailure,
          isAwaitingTrezorConfirmation: false,
        ),
      );
      return;
    }

    try {
      _cancelTronPreviewTimer();

      emit(
        requestState.copyWith(
          isPreviewRefreshing: true,
          isPreviewExpired: true,
          previewSecondsRemaining: () => 0,
          confirmStepError: () => null,
          gaslessQuoteFailure: () => null,
          transactionError: () => null,
          isAwaitingTrezorConfirmation: _walletType == WalletType.trezor,
        ),
      );

      final preview = await _generatePreview(requestState);
      _emitPreviewState(emit, requestState, preview, moveToConfirm: false);
    } catch (e) {
      if (!_matchesPreviewRequest(requestState, state)) {
        emit(
          state.copyWith(
            isSending: false,
            isPreviewRefreshing: false,
            isAwaitingTrezorConfirmation: false,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          isPreviewRefreshing: false,
          isPreviewExpired: true,
          previewSecondsRemaining: () => 0,
          confirmStepError: () => _buildTextError(e),
          gaslessQuoteFailure: () =>
              requestState.useGasless ? _gaslessQuoteFailureFrom(e) : null,
          isAwaitingTrezorConfirmation: false,
        ),
      );
    }
  }

  Future<void> _onPendingGaslessLoadRequested(
    WithdrawFormPendingGaslessLoadRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (!_canRecoverGaslessAsset(state.asset)) return;

    emit(state.copyWith(gaslessPendingStoreReady: false));
    try {
      final transfers = await _sdk.withdrawals.listPendingGaslessTransfers();
      if (emit.isDone) return;
      final matching = transfers
          .where(
            (transfer) =>
                transfer.assetId == state.asset.id.id &&
                !transfer.state.isTerminal,
          )
          .sortedBy((transfer) => transfer.updatedAt);
      final pending = matching.lastOrNull;
      if (pending == null) {
        final recoveredFromFailure = !state.gaslessPendingStoreHealthy;
        final readyState = state.copyWith(
          gaslessPendingStoreHealthy: true,
          gaslessPendingStoreReady: true,
          gaslessAvailability:
              recoveredFromFailure &&
                  state.gaslessAvailability ==
                      GaslessAvailability.securityMismatch
              ? GaslessAvailability.initial
              : state.gaslessAvailability,
        );
        emit(readyState);
        if (readyState.useGasless) {
          add(const WithdrawFormGaslessStatusRequested());
        }
        return;
      }

      final canRestoreForm =
          state.step == WithdrawFormStep.fill &&
          !state.isSending &&
          state.preview == null &&
          state.result == null;
      final recoveredState = state.copyWith(
        gaslessPendingStoreHealthy: true,
        gaslessPendingStoreReady: true,
        gaslessAvailability: GaslessAvailability.pendingTransfer,
        gaslessStatusMessage: () => pending.traceId?.trim().isNotEmpty == true
            ? LocaleKeys.withdrawGaslessStatusUnknown.tr()
            : LocaleKeys.withdrawGaslessStatusAcceptanceUnknown.tr(),
        gaslessTraceState: () => null,
        gaslessTransferState: () => pending.state,
        gaslessTraceId: () => pending.traceId,
        gaslessJournalId: () => pending.journalId,
        gaslessSubmittedAt: () => pending.acceptedAt,
      );
      if (!canRestoreForm) {
        // Standard preview/submission is intentionally allowed while the
        // journal loads. Preserve that operation, but retain the discovered
        // unresolved relay so GasFree remains blocked on the next reset.
        emit(recoveredState);
        return;
      }

      _cancelTronPreviewTimer();
      emit(
        recoveredState.copyWith(
          step: WithdrawFormStep.pending,
          recipientAddress: pending.destinationAddress,
          amount: pending.requestedAmount.toString(),
          isMaxAmount: false,
          isGaslessEnabled: true,
          preview: () => null,
          authorizedRecipientAmount: () => pending.requestedAmount,
          result: () => null,
          isSending: false,
          previewError: () => null,
          transactionError: () => null,
          confirmStepError: () => null,
          previewExpiresAt: () => null,
          previewSecondsRemaining: () => null,
          isPreviewExpired: false,
          isPreviewRefreshing: false,
          isAwaitingTrezorConfirmation: false,
        ),
      );

      // Only an accepted provider trace can be reconciled. A migrated journal
      // without a trace stays outcome-unknown and non-resubmittable.
      if (pending.traceId?.trim().isNotEmpty == true) {
        add(const WithdrawFormGaslessTraceCheckRequested());
      }
    } catch (error, stackTrace) {
      if (emit.isDone) return;
      final failure = _pendingGaslessLoadFailure(error);
      final storageUnavailable = failure.isStorageUnavailable;
      final walletChanged = failure.source is WalletChangedDisconnectException;
      final standardSource = walletChanged ? null : _fundedStandardSource();

      // Only a typed journal read/format/legacy-resolution failure means the
      // encrypted store itself is unavailable. Authentication readiness and
      // wallet-switch races still fail closed, but must not be presented as
      // corruption.
      final logMessage =
          'Unable to restore pending GasFree transfers '
          '(${failure.source.runtimeType})';
      if (storageUnavailable) {
        _logger.warning(logMessage, null, stackTrace);
      } else {
        _logger.info(logMessage);
      }
      if (state.useGasless) {
        _cancelTronPreviewTimer();
      }
      emit(
        state.copyWith(
          pubkeys: walletChanged ? () => null : null,
          selectedSourceAddress: () => standardSource,
          gaslessPendingStoreHealthy: storageUnavailable
              ? false
              : state.gaslessPendingStoreHealthy,
          gaslessPendingStoreReady: storageUnavailable,
          isGaslessEnabled: false,
          gaslessAvailability: storageUnavailable
              ? GaslessAvailability.securityMismatch
              : GaslessAvailability.initial,
        ),
      );
    }
  }

  ({Object source, bool isStorageUnavailable}) _pendingGaslessLoadFailure(
    Object error,
  ) {
    final source = error is SdkError ? error.source ?? error : error;
    final isTypedPersistenceFailure =
        source is GaslessTransferException &&
        (source.kind == GaslessTransferErrorKind.persistenceUnavailable ||
            source.code ==
                GaslessTransferErrorCode.securePersistenceUnavailable ||
            source.code == GaslessTransferErrorCode.storageMigrationRequired);
    return (
      source: source,
      isStorageUnavailable:
          source is GaslessTransferStorageReadException ||
          source is GaslessTransferStorageFormatException ||
          source is GaslessTransferLegacyResolutionException ||
          source is FormatException ||
          isTypedPersistenceFailure,
    );
  }

  PubkeyInfo? _fundedStandardSource() {
    final fundedStandardSources =
        state.pubkeys?.keys
            .where((source) => source.balance.total > Decimal.zero)
            .toList(growable: false) ??
        const <PubkeyInfo>[];
    final currentAddress = state.selectedSourceAddress?.address;
    final initialAddress = _initialSourceAddress?.address;
    return fundedStandardSources.firstWhereOrNull(
          (source) => source.address == currentAddress,
        ) ??
        fundedStandardSources.firstWhereOrNull(
          (source) => source.address == initialAddress,
        ) ??
        (fundedStandardSources.length == 1
            ? fundedStandardSources.single
            : null);
  }

  Future<void> _onGaslessTraceCheckRequested(
    WithdrawFormGaslessTraceCheckRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    final traceId = state.gaslessTraceId;
    if (traceId?.isNotEmpty != true || state.isSending) return;
    final checkGeneration = ++_gaslessTraceCheckGeneration;

    emit(
      state.copyWith(
        step: WithdrawFormStep.pending,
        isSending: true,
        transactionError: () => null,
        gaslessStatusMessage: () =>
            LocaleKeys.withdrawGaslessContinueChecking.tr(),
      ),
    );

    try {
      await for (final progress
          in _sdk.withdrawals.resumePendingGaslessTransfer(traceId!)) {
        if (checkGeneration != _gaslessTraceCheckGeneration) return;
        // Only the typed relay submission may supply a provider trace. The
        // wallet-local journal ID is not a provider trace and must never
        // be promoted into a recoverable trace identity.
        final progressTraceId =
            progress.submission?.traceId ?? state.gaslessTraceId;
        final progressJournalId =
            progress.submission?.journalId ?? state.gaslessJournalId;
        final transferState =
            progress.gaslessTransferState ??
            _gaslessTransferStateForProgress(
              progress,
              hasAcceptedTrace:
                  progressTraceId?.isNotEmpty == true ||
                  state.gaslessTransferState?.hasRelayAccepted == true,
            );

        if (progress.status == WithdrawalStatus.complete &&
            progress.withdrawalResult != null) {
          emit(
            state.copyWith(
              step: WithdrawFormStep.success,
              result: () => progress.withdrawalResult,
              preview: () => null,
              isSending: false,
              transactionError: () => null,
              gaslessStatusMessage: () => null,
              gaslessTraceState: () => progress.gaslessState,
              gaslessTransferState: () => GaslessTransferState.confirmed,
              gaslessTraceId: () => progressTraceId,
              gaslessJournalId: () => progressJournalId,
              gaslessSubmittedAt: () =>
                  state.gaslessSubmittedAt ?? DateTime.now().toUtc(),
              previewExpiresAt: () => null,
              previewSecondsRemaining: () => null,
              isPreviewExpired: false,
              isPreviewRefreshing: false,
              isAwaitingTrezorConfirmation: false,
            ),
          );
          return;
        }

        if (transferState == GaslessTransferState.failedFinal) {
          _emitGaslessFinalFailure(emit, TextError(error: progress.message));
          return;
        }

        if (progress.status == WithdrawalStatus.error) {
          // Only an explicit typed progress state may move recovery into the
          // financially ambiguous submitted-unknown lifecycle. Transport
          // errors after submitted/on-chain progress must retain that higher
          // rank instead of manufacturing a downgrade.
          if (progress.gaslessTransferState ==
              GaslessTransferState.submittedUnknown) {
            emit(
              state.copyWith(
                step: WithdrawFormStep.pending,
                isSending: false,
                gaslessStatusMessage: () => progress.message,
                gaslessTraceState: () => progress.gaslessState,
                gaslessTransferState: () => transferState,
                gaslessTraceId: () => progressTraceId,
                gaslessJournalId: () => progressJournalId,
              ),
            );
            return;
          }
          throw progress.sdkError ??
              Exception(progress.errorMessage ?? 'GasFree trace check failed');
        }

        emit(
          state.copyWith(
            step: WithdrawFormStep.pending,
            isSending: true,
            gaslessStatusMessage: () => progress.message,
            gaslessTraceState: () => progress.gaslessState,
            gaslessTransferState: () => transferState,
            gaslessTraceId: () => progressTraceId,
            gaslessJournalId: () => progressJournalId,
          ),
        );
      }

      if (checkGeneration != _gaslessTraceCheckGeneration) return;
      // A finite one-shot recovery may end without a terminal result after
      // reporting submitted/on-chain progress. Preserve that last typed
      // lifecycle and merely release the UI's active-checking state.
      emit(state.copyWith(isSending: false));
    } catch (error) {
      if (checkGeneration != _gaslessTraceCheckGeneration) return;
      if (_isAuthoritativeGaslessFinalFailure(error)) {
        _emitGaslessFinalFailure(emit, _buildTextError(error));
      } else {
        // A transport failure is not lifecycle evidence. Keep any established
        // submitted/confirming rank, trace state, IDs, and status copy.
        emit(state.copyWith(isSending: false));
      }
    }
  }

  void _onPendingUseStandardRequested(
    WithdrawFormPendingUseStandardRequested event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.step != WithdrawFormStep.pending ||
        !state.hasUnresolvedGaslessTransfer) {
      return;
    }

    // Stop this screen's reconciliation from reclaiming the pending step.
    // The encrypted SDK journal remains authoritative and will resume through
    // one-shot trace recovery when the unresolved record is opened again.
    _gaslessTraceCheckGeneration += 1;
    _cancelTronPreviewTimer();

    final standardSource = _fundedStandardSource();

    emit(
      state.copyWith(
        step: WithdrawFormStep.fill,
        recipientAddress: '',
        amount: '0',
        selectedSourceAddress: () => standardSource,
        isMaxAmount: false,
        isCustomFee: false,
        customFee: () => null,
        isGaslessEnabled: false,
        gaslessAvailability: state.hasAmbiguousGaslessSources
            ? GaslessAvailability.securityMismatch
            : GaslessAvailability.pendingTransfer,
        preview: () => null,
        authorizedRecipientAmount: () => null,
        result: () => null,
        isSending: false,
        recipientAddressError: () => null,
        amountError: () => null,
        customFeeError: () => null,
        previewError: () => null,
        gaslessQuoteFailure: () => null,
        transactionError: () => null,
        confirmStepError: () => null,
        networkError: () => null,
        previewExpiresAt: () => null,
        previewSecondsRemaining: () => null,
        isPreviewExpired: false,
        isPreviewRefreshing: false,
        isAwaitingTrezorConfirmation: false,
      ),
    );
    add(const WithdrawFormSourcesLoadRequested());
  }

  Future<void> _onSubmitted(
    WithdrawFormSubmitted event,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (!await _authorizeWithdrawal(emit)) return;
    if (state.isGaslessPendingStoreChecking) return;
    if (state.hasValidationErrors) return;
    final isGaslessSubmission = state.useGasless;
    if (_isUnsupportedSiaHardwareWalletFlow) {
      emit(
        state.copyWith(
          transactionError: () =>
              TextError(error: _unsupportedSiaHardwareWalletMessage),
          isSending: false,
          isAwaitingTrezorConfirmation: false,
        ),
      );
      return;
    }

    if (_isTronAsset(state.asset) &&
        (state.isPreviewRefreshing ||
            state.isPreviewExpired ||
            state.previewSecondsRemaining == null ||
            state.previewSecondsRemaining == 0 ||
            state.hasConfirmStepError)) {
      emit(
        state.copyWith(
          confirmStepError: () =>
              TextError(error: LocaleKeys.withdrawTronPreviewExpired.tr()),
          isSending: false,
        ),
      );
      return;
    }

    // Backstop: the Gleec app requires the confirmed rail to match the rail
    // explicitly selected on the fill step in both directions.
    if (state.preview != null &&
        isGaslessSubmission != _previewUsesGaslessRail(state.preview!)) {
      emit(
        state.copyWith(
          confirmStepError: () =>
              TextError(error: LocaleKeys.withdrawGaslessSecurityMismatch.tr()),
          isSending: false,
        ),
      );
      return;
    }

    try {
      _cancelTronPreviewTimer();

      emit(
        state.copyWith(
          isSending: true,
          transactionError: () => null,
          confirmStepError: () => null,
          // No second device interaction is needed on confirm
          isAwaitingTrezorConfirmation: false,
          gaslessTransferState: () => isGaslessSubmission
              ? GaslessTransferState.preparing
              : state.gaslessTransferState,
          gaslessTraceId: () =>
              isGaslessSubmission ? null : state.gaslessTraceId,
          gaslessJournalId: () =>
              isGaslessSubmission ? null : state.gaslessJournalId,
          gaslessSubmittedAt: () =>
              isGaslessSubmission ? null : state.gaslessSubmittedAt,
        ),
      );
      final preview = state.preview;
      if (preview == null) {
        throw Exception('Missing withdrawal preview');
      }

      // Execute the previewed withdrawal: the transaction was already signed during preview,
      // so executeWithdrawal() will NOT sign again. It simply broadcasts the pre-signed transaction,
      // preserving the key behavior from the previous implementation.
      WithdrawalResult? result;
      await for (final progress in _sdk.withdrawals.executeWithdrawal(
        preview,
        state.asset.id.id,
      )) {
        // Preserve the SDK's typed relay lifecycle before handling a generic
        // error status. In particular, a response can be financially ambiguous
        // with only a wallet journal ID and no provider trace; the catch path
        // must still see that post-submission state and block resubmission.
        if (isGaslessSubmission &&
            progress.status != WithdrawalStatus.complete) {
          final submission = progress.submission;
          final traceId = submission?.traceId ?? state.gaslessTraceId;
          final journalId = submission?.journalId ?? state.gaslessJournalId;
          emit(
            state.copyWith(
              gaslessStatusMessage: () => progress.message,
              gaslessTraceState: () => progress.gaslessState,
              gaslessTransferState: () => _gaslessTransferStateForProgress(
                progress,
                hasAcceptedTrace: traceId != null,
              ),
              gaslessTraceId: () => traceId,
              gaslessJournalId: () => journalId,
              gaslessSubmittedAt: () => traceId == null && journalId == null
                  ? state.gaslessSubmittedAt
                  : state.gaslessSubmittedAt ?? DateTime.now().toUtc(),
            ),
          );
        }

        if (progress.status == WithdrawalStatus.complete) {
          result = progress.withdrawalResult;
          if (isGaslessSubmission) {
            final submission = progress.submission;
            emit(
              state.copyWith(
                gaslessTransferState: () => GaslessTransferState.confirmed,
                gaslessTraceId: () =>
                    submission?.traceId ?? state.gaslessTraceId,
                gaslessJournalId: () =>
                    submission?.journalId ?? state.gaslessJournalId,
                gaslessSubmittedAt: () =>
                    state.gaslessSubmittedAt ?? DateTime.now().toUtc(),
              ),
            );
          }
          break;
        } else if (progress.status == WithdrawalStatus.error) {
          if (progress.sdkError != null) {
            throw progress.sdkError!;
          }
          throw Exception(progress.errorMessage ?? 'Broadcast failed');
        }
        // Continue for in-progress states
      }

      if (result == null) {
        if (isGaslessSubmission && _hasPossiblySubmittedGaslessTransfer) {
          _emitGaslessSubmittedUnknown(emit, _gaslessUnknownStatusMessage());
          return;
        }
        emit(
          state.copyWith(
            isSending: false,
            transactionError: () =>
                TextError(error: LocaleKeys.withdrawNoResultError.tr()),
            isAwaitingTrezorConfirmation: false,
            gaslessTransferState: () => isGaslessSubmission
                ? GaslessTransferState.rejectedBeforeRelay
                : state.gaslessTransferState,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          step: WithdrawFormStep.success,
          result: () => result,
          // Clear cached preview after successful broadcast
          preview: () => null,
          isSending: false,
          previewExpiresAt: () => null,
          previewSecondsRemaining: () => null,
          isPreviewExpired: false,
          isPreviewRefreshing: false,
          isAwaitingTrezorConfirmation: false,
          gaslessStatusMessage: () =>
              isGaslessSubmission ? null : state.gaslessStatusMessage,
          gaslessTraceState: () => isGaslessSubmission
              ? GaslessTraceState.confirmed
              : state.gaslessTraceState,
          gaslessTransferState: () => isGaslessSubmission
              ? GaslessTransferState.confirmed
              : state.gaslessTransferState,
        ),
      );
      return;
    } catch (e) {
      _cancelTronPreviewTimer();

      // Capture FD snapshot when KDF withdrawal submission fails
      if (PlatformTuner.isIOS) {
        try {
          await FdMonitorService().logDetailedStatus();
          final stats = await FdMonitorService().getCurrentCount();
          _logger.info(
            'FD stats at withdrawal submission failure for ${state.asset.id.id}: $stats',
          );
        } catch (fdError, fdStackTrace) {
          _logger.warning('Failed to capture FD stats', fdError, fdStackTrace);
        }
      }

      if (isGaslessSubmission && _hasPossiblySubmittedGaslessTransfer) {
        if (_isAuthoritativeGaslessFinalFailure(e)) {
          _emitGaslessFinalFailure(emit, _buildTextError(e));
        } else {
          _emitGaslessSubmittedUnknown(emit, _gaslessUnknownStatusMessage());
        }
      } else {
        emit(
          state.copyWith(
            transactionError: () => _buildTextError(e),
            step: WithdrawFormStep.failed,
            isSending: false,
            isPreviewRefreshing: false,
            isAwaitingTrezorConfirmation: false,
            gaslessStatusMessage: () =>
                isGaslessSubmission ? null : state.gaslessStatusMessage,
            gaslessTraceState: () =>
                isGaslessSubmission ? null : state.gaslessTraceState,
            gaslessTransferState: () => isGaslessSubmission
                ? GaslessTransferState.rejectedBeforeRelay
                : state.gaslessTransferState,
          ),
        );
      }
    }
  }

  GaslessTransferState _gaslessTransferStateForProgress(
    WithdrawalProgress progress, {
    required bool hasAcceptedTrace,
  }) {
    final explicit = progress.gaslessTransferState;
    if (explicit != null) return explicit;

    return switch (progress.gaslessState) {
      GaslessTraceState.pending ||
      GaslessTraceState.submitted => GaslessTransferState.submittedPending,
      GaslessTraceState.onChain => GaslessTransferState.confirming,
      GaslessTraceState.confirmed => GaslessTransferState.confirmed,
      GaslessTraceState.failed => GaslessTransferState.failedFinal,
      null =>
        hasAcceptedTrace
            ? GaslessTransferState.submittedPending
            : GaslessTransferState.preparing,
    };
  }

  bool _isAuthoritativeGaslessFinalFailure(Object error) {
    final source = error is SdkError ? error.source : error;
    return source is GaslessTransferException && source.terminal;
  }

  /// A relay request can be financially accepted even when its response never
  /// returns a trace. The SDK persists that ambiguity with a local journal ID
  /// and a typed post-submission state. Neither case may be downgraded to a safe
  /// pre-relay rejection, because doing so would enable a duplicate send.
  bool get _hasPossiblySubmittedGaslessTransfer =>
      state.gaslessTraceId?.isNotEmpty == true ||
      state.gaslessJournalId?.isNotEmpty == true ||
      state.gaslessTransferState?.mayHaveRelayAccepted == true;

  void _emitGaslessFinalFailure(
    Emitter<WithdrawFormState> emit,
    TextError error,
  ) {
    _cancelTronPreviewTimer();
    emit(
      state.copyWith(
        step: WithdrawFormStep.failed,
        preview: () => null,
        transactionError: () => error,
        isSending: false,
        isPreviewRefreshing: false,
        isAwaitingTrezorConfirmation: false,
        gaslessStatusMessage: () => null,
        gaslessTraceState: () => GaslessTraceState.failed,
        gaslessTransferState: () => GaslessTransferState.failedFinal,
        previewExpiresAt: () => null,
        previewSecondsRemaining: () => null,
        isPreviewExpired: false,
      ),
    );
  }

  void _emitGaslessSubmittedUnknown(
    Emitter<WithdrawFormState> emit,
    String message,
  ) {
    _cancelTronPreviewTimer();
    emit(
      state.copyWith(
        step: WithdrawFormStep.pending,
        preview: () => null,
        transactionError: () => null,
        isSending: false,
        isPreviewRefreshing: false,
        isAwaitingTrezorConfirmation: false,
        gaslessStatusMessage: () => message,
        gaslessTraceState: () => null,
        gaslessTransferState: () => GaslessTransferState.submittedUnknown,
        previewExpiresAt: () => null,
        previewSecondsRemaining: () => null,
        isPreviewExpired: false,
      ),
    );
  }

  String _gaslessUnknownStatusMessage() {
    final hasAcceptedTrace = state.gaslessTraceId?.trim().isNotEmpty == true;
    return hasAcceptedTrace
        ? LocaleKeys.withdrawGaslessStatusUnknown.tr()
        : LocaleKeys.withdrawGaslessStatusAcceptanceUnknown.tr();
  }

  bool get _isUnsupportedSiaHardwareWalletFlow =>
      _walletType == WalletType.trezor && state.asset.protocol is SiaProtocol;

  bool get _isSelfTransfer {
    if (kAllowSameAddressWithdrawals) return false;

    final source = state.selectedSourceAddress;
    final recipient = state.recipientAddress.trim();
    if (source == null || recipient.isEmpty) return false;
    return source.address == recipient ||
        (state.useGasless && source.gasfreeAddress == recipient);
  }

  void _onCancelled(
    WithdrawFormCancelled event,
    Emitter<WithdrawFormState> emit,
  ) {
    // TODO: Cancel withdrawal if in progress

    add(const WithdrawFormReset());
  }

  void _onReset(WithdrawFormReset event, Emitter<WithdrawFormState> emit) {
    _cancelTronPreviewTimer();
    final hasUnresolvedGaslessTransfer = state.hasUnresolvedGaslessTransfer;
    final resetToGasless =
        _initialGaslessEnabled &&
        state.isGaslessSupported &&
        state.canonicalGaslessSource != null &&
        !state.hasAmbiguousGaslessSources &&
        !hasUnresolvedGaslessTransfer;
    final fundedStandardSources =
        state.pubkeys?.keys
            .where((source) => source.balance.total > Decimal.zero)
            .toList(growable: false) ??
        const <PubkeyInfo>[];
    final currentStandardAddress = state.selectedSourceAddress?.address;
    final initialStandardAddress = _initialSourceAddress?.address;
    final resetSource = _lockSourceSelection
        ? fundedStandardSources.firstWhereOrNull(
            (source) => source.address == initialStandardAddress,
          )
        : resetToGasless
        ? state.canonicalGaslessSource
        : fundedStandardSources.firstWhereOrNull(
                (source) => source.address == initialStandardAddress,
              ) ??
              fundedStandardSources.firstWhereOrNull(
                (source) => source.address == currentStandardAddress,
              ) ??
              fundedStandardSources.firstOrNull;
    final resetAvailability = !state.gaslessPendingStoreHealthy
        ? GaslessAvailability.securityMismatch
        : state.hasAmbiguousGaslessSources
        ? GaslessAvailability.securityMismatch
        : hasUnresolvedGaslessTransfer
        ? GaslessAvailability.pendingTransfer
        : GaslessAvailability.initial;
    emit(
      WithdrawFormState(
        asset: state.asset,
        step: WithdrawFormStep.fill,
        recipientAddress: '',
        amount: '0',
        walletType: state.walletType,
        isGaslessFeatureConfigured: state.isGaslessFeatureConfigured,
        gaslessPendingStoreHealthy: state.gaslessPendingStoreHealthy,
        gaslessPendingStoreReady: state.gaslessPendingStoreReady,
        pubkeys: state.pubkeys,
        selectedSourceAddress: resetSource,
        isSourceSelectionLocked: _lockSourceSelection,
        isGaslessEnabled: resetToGasless,
        gaslessAvailability: resetAvailability,
        gaslessStatusMessage: hasUnresolvedGaslessTransfer
            ? state.gaslessStatusMessage
            : null,
        gaslessTraceState: hasUnresolvedGaslessTransfer
            ? state.gaslessTraceState
            : null,
        gaslessTransferState: hasUnresolvedGaslessTransfer
            ? state.gaslessTransferState
            : null,
        gaslessTraceId: hasUnresolvedGaslessTransfer
            ? state.gaslessTraceId
            : null,
        gaslessJournalId: hasUnresolvedGaslessTransfer
            ? state.gaslessJournalId
            : null,
        gaslessSubmittedAt: hasUnresolvedGaslessTransfer
            ? state.gaslessSubmittedAt
            : null,
      ),
    );
    // The fresh state dropped the cached custody snapshot; re-request it.
    if (state.useGasless) {
      add(const WithdrawFormGaslessStatusRequested());
    }
    // Restore the construction-time prefill so a retry after a failed
    // prefilled flow (consolidation) does not degrade to an empty form.
    final initialRecipient = _initialRecipient;
    if (initialRecipient != null && initialRecipient.isNotEmpty) {
      add(WithdrawFormRecipientChanged(initialRecipient));
    }
    if (_initialIsMax) {
      add(const WithdrawFormMaxAmountEnabled(true));
    }
  }

  void _onStepReverted(
    WithdrawFormStepReverted event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.isPreviewRefreshing) {
      return;
    }

    if (state.step == WithdrawFormStep.confirm) {
      _cancelTronPreviewTimer();
      emit(
        state.copyWith(
          step: WithdrawFormStep.fill,
          preview: () => null,
          previewError: () => null,
          transactionError: () => null,
          confirmStepError: () => null,
          isSending: false,
          previewExpiresAt: () => null,
          previewSecondsRemaining: () => null,
          isPreviewExpired: false,
          isPreviewRefreshing: false,
          isAwaitingTrezorConfirmation: false,
        ),
      );
      return;
    }

    if (state.step != WithdrawFormStep.failed) return;

    final nextStep = state.preview != null
        ? WithdrawFormStep.confirm
        : WithdrawFormStep.fill;

    if (nextStep == WithdrawFormStep.confirm &&
        _isTronAsset(state.asset) &&
        state.preview != null) {
      final expiryAt = _buildPreviewExpiryAt(state, state.preview!);
      final secondsRemaining = expiryAt == null
          ? null
          : _calculatePreviewSecondsRemaining(expiryAt);
      final isExpired = secondsRemaining != null && secondsRemaining <= 0;

      final nextState = state.copyWith(
        step: nextStep,
        transactionError: () => null,
        confirmStepError: () => isExpired
            ? TextError(error: LocaleKeys.withdrawTronPreviewExpired.tr())
            : null,
        isSending: false,
        previewExpiresAt: () => expiryAt,
        previewSecondsRemaining: () => secondsRemaining,
        isPreviewExpired: isExpired,
        isPreviewRefreshing: false,
        isAwaitingTrezorConfirmation: false,
      );
      emit(nextState);

      if (!isExpired) {
        _startTronPreviewTimer(nextState);
      }
      return;
    }

    _cancelTronPreviewTimer();
    emit(
      state.copyWith(
        step: nextStep,
        transactionError: () => null,
        confirmStepError: () => null,
        isSending: false,
        previewExpiresAt: () => null,
        previewSecondsRemaining: () => null,
        isPreviewExpired: false,
        isPreviewRefreshing: false,
        isAwaitingTrezorConfirmation: false,
      ),
    );
  }

  bool _hasEthAddressMixedCase(String address) {
    if (!address.startsWith('0x')) return false;
    final chars = address.substring(2).split('');
    return chars.any((c) => c.toLowerCase() != c) &&
        chars.any((c) => c.toUpperCase() != c);
  }

  Future<void> _onConvertAddress(
    WithdrawFormConvertAddressRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    if (state.isMixedCaseAddress) return;

    try {
      emit(state.copyWith(isSending: true));

      // For EVM addresses, we want to convert to checksum format
      final result = await _sdk.addresses.convertFormat(
        asset: state.asset,
        address: state.recipientAddress,
        format: const AddressFormat(format: 'mixedcase', network: ''),
      );

      emit(
        state.copyWith(
          recipientAddress: result.convertedAddress,
          isMixedCaseAddress: false,
          recipientAddressError: () => null,
          isSending: false,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          recipientAddressError: () => TextError(
            error: _formatErrorMessage(e),
            technicalDetails: extractKdfTechnicalDetails(e),
          ),
          isSending: false,
        ),
      );
    }
  }

  Decimal _atomicToDecimal(int amount, int decimals) {
    if (decimals <= 0) return Decimal.fromInt(amount);
    final scale = Decimal.parse('1${'0' * decimals}');
    return (Decimal.fromInt(amount) / scale).toDecimal();
  }

  @override
  Future<void> close() {
    _cancelTronPreviewTimer();
    return super.close();
  }
}

class MixedCaseAddressError extends BaseError {
  @override
  String get message => LocaleKeys.mixedCaseError.tr();
}

class EvmAddressResult {
  final bool isValid;
  final bool isMixedCase;
  final String? errorMessage;

  EvmAddressResult({
    required this.isValid,
    this.isMixedCase = false,
    this.errorMessage,
  });

  bool get hasError => !isValid;
}
