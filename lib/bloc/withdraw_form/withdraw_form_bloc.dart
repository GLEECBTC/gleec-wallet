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
import 'package:web_dex/shared/utils/extensions/legacy_coin_migration_extensions.dart';
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
  final bool _lockSourceSelection;
  final WithdrawalAuthorizationGuard? _authorizationGuard;
  final String? _authorizationFailureMessage;
  Timer? _tronPreviewTimer;

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
    on<WithdrawFormGaslessMaxFeeChanged>(_onGaslessMaxFeeChanged);
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
    if (state.isGaslessSupported) {
      add(const WithdrawFormGaslessStatusRequested());
    }
    if (initialRecipient != null && initialRecipient.isNotEmpty) {
      add(WithdrawFormRecipientChanged(initialRecipient));
    }
    if (initialIsMax) {
      add(const WithdrawFormMaxAmountEnabled(true));
    }
  }

  Future<bool> _authorizeWithdrawal(Emitter<WithdrawFormState> emit) async {
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

  bool _isTronAsset(Asset asset) =>
      asset.protocol is TrxProtocol || asset.protocol is Trc20Protocol;

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

    final isGaslessPreview =
        preview.fee is FeeInfoTronGasless ||
        preview.txJson?['relay_type'] == 'tron_gasfree';
    if (isGaslessPreview) {
      final authorization = preview.txJson?['signed_authorization'];
      final rawDeadline = authorization is Map
          ? authorization['deadline']
          : null;
      final deadline = switch (rawDeadline) {
        final int value when value >= 0 => value,
        final String value when RegExp(r'^\d+$').hasMatch(value) =>
          int.tryParse(value),
        _ => null,
      };
      final feeDeadline = switch (preview.fee) {
        FeeInfoTronGasless(:final authorizationDeadline) =>
          authorizationDeadline,
        _ => null,
      };

      // The relay signature, not the preview creation time, defines how long
      // the authorization may be submitted. Legacy KDF responses can omit the
      // duplicated fee field, so read the signed payload and only use the fee
      // value as a consistency check when it is present.
      if (deadline == null ||
          (feeDeadline != null && feeDeadline != deadline)) {
        return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }

      try {
        return DateTime.fromMillisecondsSinceEpoch(
          deadline * Duration.millisecondsPerSecond,
          isUtc: true,
        );
      } on ArgumentError {
        // A malformed/out-of-range signed deadline must never leave the send
        // button enabled indefinitely.
        return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      }
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

  TextError? _previewGuardError() {
    if (_isUnsupportedSiaHardwareWalletFlow) {
      return TextError(error: _unsupportedSiaHardwareWalletMessage);
    }

    if (_isSelfTransfer) {
      return TextError(error: LocaleKeys.cannotSendToSelf.tr());
    }

    // The GasFree provider reported itself unreachable: custody funds are
    // safe on-chain but a gasless send cannot be built right now. Block with
    // an honest message — never suggest TRX or switching to the native rail
    // (custody funds are not natively spendable).
    if (state.isGaslessProviderUnavailable) {
      return TextError(
        error: LocaleKeys.withdrawGaslessProviderUnavailable.tr(
          args: [state.asset.id.id],
        ),
      );
    }

    if (state.useGasless &&
        state.gaslessAvailability == GaslessAvailability.unsupported) {
      return TextError(error: LocaleKeys.withdrawGaslessUnsupported.tr());
    }

    if (state.useGasless &&
        state.gaslessAvailability == GaslessAvailability.securityMismatch) {
      return TextError(error: LocaleKeys.withdrawGaslessSecurityMismatch.tr());
    }

    if (state.useGasless && state.gaslessAvailability.isBlocked) {
      return TextError(
        error: LocaleKeys.withdrawGaslessUnavailableBlocked.tr(),
      );
    }

    // A max gas-free send whose custody balance is fully consumed by fees would
    // hard-fail at KDF with a misleading "balance is zero". Block it here with
    // the honest fee-floor reason. The amount-field error normally disables
    // Preview first; this backstops a stale-cap race that reaches preview.
    if (state.isGaslessBalanceBelowFees) {
      return TextError(error: _gaslessBelowFeesMessage());
    }

    return null;
  }

  /// Honest "your custody balance is below the gas-free fee floor" message,
  /// built from the cached account-status snapshot the wallet already holds, so
  /// the user sees why nothing is sendable instead of a false "balance is zero".
  String _gaslessBelowFeesMessage() {
    final status = state.gaslessAccountStatus;
    final coin = state.asset.id.symbol.configSymbol;
    final holds = status?.spendableBalance ?? Decimal.zero;
    final totalFee =
        (status?.transferFee ?? Decimal.zero) +
        (status?.activationFee ?? Decimal.zero);
    return LocaleKeys.withdrawGaslessBalanceBelowFees.tr(
      args: [formatDexAmt(holds), coin, formatDexAmt(totalFee), coin, coin],
    );
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

  String _normalizeCommonErrors(String message) {
    final gaslessMessage = _normalizeGaslessError(message);
    if (gaslessMessage != null) {
      return gaslessMessage;
    }

    final normalized = message.toLowerCase();

    if (normalized.contains('cannot transfer') &&
        normalized.contains('to yourself')) {
      return LocaleKeys.cannotSendToSelf.tr();
    }

    // "Not enough balance to pay gas" is a native-rail concept; a gas-free
    // send must never surface it (fees are paid in the token). Gasless
    // fee-shaped shortfalls are handled by [_normalizeGaslessError] above.
    if (!state.useGasless &&
        normalized.contains('insufficient') &&
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

  /// For a gas-free withdrawal that is short on custody balance, produce a
  /// custody-aware message denominated in the token (never "insufficient TRX").
  /// Handles both the active-account shortfall (`available X, required at least
  /// Y`) and the inactive-account variant (`… activation fee Z`). GasFree
  /// provider/transport failures (401, rate limit, timeout, …) are mapped to
  /// the honest "service unavailable" message instead — never to a
  /// balance-shortfall diagnosis that would tell the user to deposit more.
  String? _normalizeGaslessError(String message) {
    if (!state.useGasless) return null;
    final normalized = message.toLowerCase();

    // The provider allows one in-flight transfer at a time
    // (maxPendingTransfer: 1) — KDF surfaces this as "already pending".
    if (normalized.contains('already pending')) {
      return LocaleKeys.withdrawGaslessPendingTransfer.tr();
    }

    final mentionsGasfreeRail =
        normalized.contains('gasfree') || normalized.contains('gas-free');
    final looksLikeProviderOutage =
        mentionsGasfreeRail &&
        (normalized.contains('unauthorized') ||
            normalized.contains('authentication') ||
            normalized.contains('forbidden') ||
            normalized.contains('rate limit') ||
            normalized.contains('upstream') ||
            normalized.contains('unavailable') ||
            normalized.contains('timed out') ||
            normalized.contains('timeout') ||
            normalized.contains('transport') ||
            normalized.contains('network'));
    if (looksLikeProviderOutage) {
      return LocaleKeys.withdrawGaslessProviderUnavailable.tr(
        args: [state.asset.id.symbol.configSymbol],
      );
    }

    // Only genuine shortfall wording qualifies — a bare mention of the
    // gas-free rail (e.g. "GasFree authentication failed") must not be
    // rewritten into an "add more USDT" message.
    final looksLikeBalanceShortfall =
        normalized.contains('required at least') ||
        ((normalized.contains('not enough') ||
                normalized.contains('insufficient') ||
                normalized.contains('not sufficient')) &&
            (normalized.contains('balance') ||
                normalized.contains('fee') ||
                normalized.contains('gas')));

    if (!looksLikeBalanceShortfall) {
      return null;
    }

    // Older KDF phrases the shortfall as "required at least {r}"; the
    // structured GasFree errors phrase it as "required {r}" (and are normally
    // caught upstream by [_formatStructuredGaslessShortfall] — this regex is
    // the string-level fallback).
    // `\d+(?:\.\d+)?` (not `[\d.]+`) so a sentence-ending period after the
    // amount ("required 8. Deposit …") isn't captured into the number.
    final details = RegExp(
      r'available\s+(\d+(?:\.\d+)?)\s*,\s*'
      r'required(?:\s+at\s+least)?\s+(\d+(?:\.\d+)?)',
      caseSensitive: false,
    ).firstMatch(message);
    final assetName = state.asset.id.symbol.configSymbol;
    if (details == null) {
      return LocaleKeys.withdrawGaslessInsufficientBalanceGeneric.tr(
        args: [assetName, assetName],
      );
    }

    final available = details.group(1)?.trim() ?? '0';
    final required = details.group(2)?.trim() ?? '';
    return LocaleKeys.withdrawGaslessInsufficientBalance.tr(
      args: [available, assetName, required, assetName, assetName],
    );
  }

  Future<void> _onSourcesLoadRequested(
    WithdrawFormSourcesLoadRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    try {
      final cached = _sdk.pubkeys.lastKnown(state.asset.id);
      final pubkeys = cached ?? await state.asset.getPubkeys(_sdk);
      // GasFree v1 has exactly one canonical custody signer. Retain that key
      // plus every funded standard EOA; secondary keys must never be rendered
      // as additional custody accounts, but their standard balances remain
      // spendable/recoverable.
      final canonicalGaslessKey = pubkeys.keys.firstWhereOrNull(
        (key) =>
            isCanonicalTronGaslessPubkey(
              key,
              isHdWallet: state.walletType == WalletType.hdwallet,
            ) &&
            (key.gasfreeAddress?.isNotEmpty ?? false),
      );
      final fundedKeys = pubkeys.keys
          .where(
            (key) =>
                identical(key, canonicalGaslessKey) ||
                key.balance.total > Decimal.zero,
          )
          .toList();

      if (fundedKeys.isNotEmpty) {
        final filteredPubkeys = AssetPubkeys(
          assetId: pubkeys.assetId,
          keys: fundedKeys,
          availableAddressesCount: pubkeys.availableAddressesCount,
          syncStatus: pubkeys.syncStatus,
        );

        final current = state.selectedSourceAddress;
        final canUseGasless = state.useGasless && canonicalGaslessKey != null;
        final newSelection = canUseGasless
            ? canonicalGaslessKey
            : current != null
            ? fundedKeys.firstWhereOrNull(
                    (key) => key.address == current.address,
                  ) ??
                  (fundedKeys.length == 1 ? fundedKeys.first : null)
            : (fundedKeys.length == 1 ? fundedKeys.first : null);
        emit(
          state.copyWith(
            pubkeys: () => filteredPubkeys,
            networkError: () => null,
            selectedSourceAddress: () => newSelection,
            isGaslessEnabled: canUseGasless,
            gaslessAvailability: state.useGasless && canonicalGaslessKey == null
                ? GaslessAvailability.unsupported
                : state.gaslessAvailability,
          ),
        );
        // A max amount chosen before sources finished loading (e.g. the
        // consolidation prefill) was computed against a null balance —
        // recompute it now that the source address is known.
        if (state.isMaxAmount) {
          add(const WithdrawFormMaxAmountEnabled(true));
        }
      } else {
        emit(
          state.copyWith(
            pubkeys: () => AssetPubkeys(
              assetId: pubkeys.assetId,
              keys: const [],
              availableAddressesCount: pubkeys.availableAddressesCount,
              syncStatus: pubkeys.syncStatus,
            ),
            selectedSourceAddress: () => null,
            networkError: () => TextError(
              error: state.useGasless
                  ? LocaleKeys.withdrawGaslessNoSourceAddress.tr(
                      args: [state.asset.id.id],
                    )
                  : LocaleKeys.withdrawNoFundedAddresses.tr(
                      args: [state.asset.id.name],
                    ),
            ),
          ),
        );
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

      // Advisory custody-cap pre-validation for the gas-free rail. Only when
      // a status snapshot is cached — otherwise behavior is unchanged and the
      // KDF preview (via _normalizeGaslessError) remains the backstop.
      final gaslessCap = state.gaslessMaxWithdrawable;
      if (gaslessCap != null && amount > gaslessCap) {
        emit(
          state.copyWith(
            amount: event.amount,
            amountError: () => TextError(
              error: gaslessCap > Decimal.zero
                  ? LocaleKeys.withdrawGaslessAmountExceedsMax.tr(
                      args: [
                        gaslessCap.toString(),
                        state.asset.id.id,
                        state.asset.id.id,
                      ],
                    )
                  // "You can send up to 0" reads absurd — an empty custody
                  // account gets the plain add-funds message instead.
                  : LocaleKeys.withdrawGaslessInsufficientBalanceGeneric.tr(
                      args: [state.asset.id.id, state.asset.id.id],
                    ),
            ),
          ),
        );
        // The snapshot may be stale (e.g. the user deposited to custody after
        // it was cached). A TTL-gated refresh re-validates and clears the
        // error once fresh numbers land; when the cap is genuinely exceeded
        // the follow-up request is a no-op (fresh snapshot → early return).
        add(const WithdrawFormGaslessStatusRequested());
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
    final balance = event.address.balance;
    final updatedAmount = state.isMaxAmount && !state.useGasless
        ? balance.spendable.toString()
        : state.amount;

    emit(
      state.copyWith(
        selectedSourceAddress: () => event.address,
        networkError: () => null,
        amount: updatedAmount,
        amountError: () => null,
        previewError: () => null,
      ),
    );

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
    // Gas-free transfers pay the network fee in the token itself, so the
    // source address legitimately holds zero TRX. Only enforce the parent
    // (TRX) gas balance guard on the native rail.
    if (event.isEnabled &&
        !state.useGasless &&
        state.asset.id.parentId != null) {
      final parentId = state.asset.id.parentId!;
      final parentSpendable = state.isTronAsset
          ? await _selectedSourceParentSpendable(parentId)
          : (_sdk.balances.lastKnown(parentId) ??
                    await _sdk.balances.getBalance(parentId))
                .spendable;

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
      // Custody-aware max: `gasless::account_status.max_withdrawable` already
      // nets out the transfer (and, if inactive, activation) fee. Display
      // only — the withdraw request still sends `isMax: true` with no amount,
      // so KDF remains the authority on the signed amount.
      maxAmount = state.gaslessMaxWithdrawable?.toString() ?? '0';
    } else {
      maxAmount = balance?.spendable.toString() ?? '0';
    }

    // Gas-free: a zero cap with funds in custody means the balance is entirely
    // consumed by the transfer (+ first-send activation) fee. Surface the honest
    // fee-floor reason — it disables Preview via hasValidationErrors — instead
    // of firing a doomed request KDF answers with a misleading "balance is zero".
    final belowFees = event.isEnabled && state.isGaslessBalanceBelowFees;

    emit(
      state.copyWith(
        isMaxAmount: event.isEnabled,
        amount: maxAmount,
        amountError: () =>
            belowFees ? TextError(error: _gaslessBelowFeesMessage()) : null,
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
    final parentPubkeys =
        _sdk.pubkeys.lastKnown(parentId) ??
        await _sdk.pubkeys.getPubkeys(parentAsset);
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
    if (!state.isGaslessSupported) return;
    final canonicalGaslessKey = state.pubkeys?.keys.firstWhereOrNull(
      (key) =>
          isCanonicalTronGaslessPubkey(
            key,
            isHdWallet: state.walletType == WalletType.hdwallet,
          ) &&
          (key.gasfreeAddress?.isNotEmpty ?? false),
    );
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
        // Clear any stale max-fee cap when turning gasless off.
        gaslessMaxFee: event.isEnabled ? null : () => null,
        // The rail changed, so every error produced on the previous rail is
        // stale — including the gasless "no source address" network error and
        // any left-over transaction/confirm errors.
        amountError: () => null,
        previewError: () => null,
        networkError: () => null,
        transactionError: () => null,
        confirmStepError: () => null,
        gaslessStatusMessage: () => null,
        gaslessTraceState: () => null,
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

  void _onGaslessMaxFeeChanged(
    WithdrawFormGaslessMaxFeeChanged event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    emit(state.copyWith(gaslessMaxFee: () => event.maxFee));
  }

  /// How long a fetched `gasless::account_status` snapshot stays fresh before
  /// a non-forced [WithdrawFormGaslessStatusRequested] re-fetches it.
  static const Duration _gaslessStatusTtl = Duration(seconds: 30);

  Future<void> _onGaslessStatusRequested(
    WithdrawFormGaslessStatusRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (!state.isGaslessSupported) return;

    final fetchedAt = state.gaslessStatusFetchedAt;
    final isFresh =
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _gaslessStatusTtl;
    // `restartable()` cancels any in-flight fetch when this event arrives, so
    // when one WAS in flight (isGaslessStatusLoading) this handler must run
    // the fetch itself — early-returning would strand the cancelled request
    // (e.g. a forced retry superseded by a non-forced one within the TTL).
    if (!event.force &&
        isFresh &&
        state.gaslessAccountStatus != null &&
        !state.isGaslessStatusLoading) {
      return;
    }

    emit(
      state.copyWith(
        isGaslessStatusLoading: true,
        gaslessAvailability: GaslessAvailability.checking,
      ),
    );
    try {
      final status = await _sdk.withdrawals.gaslessAccountStatus(
        state.asset.id,
      );
      emit(
        state.copyWith(
          gaslessAccountStatus: () => status,
          gaslessStatusFetchedAt: () => DateTime.now(),
          isGaslessStatusLoading: false,
          gaslessAvailability: _availabilityForGaslessStatus(status),
        ),
      );
      // Re-validate against the fresh custody numbers so a max amount or an
      // over-cap error entered before the fetch landed doesn't go stale. A
      // pristine form (amount still '0') is left alone — re-validating it
      // would surface a spurious "amount must be greater than 0" error.
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
    } catch (e) {
      // Keep any previous snapshot but label it stale. With no snapshot, use
      // an explicit neutral/unavailable state rather than rendering the green
      // ready chip. Do not timestamp failures as fresh: the user must be able
      // to retry immediately, while preview can remain the authoritative
      // operation for an already-funded custody account.
      _logger.fine('gasless::account_status fetch failed', e);
      emit(
        state.copyWith(
          isGaslessStatusLoading: false,
          gaslessAvailability: state.gaslessAccountStatus == null
              ? GaslessAvailability.temporarilyUnavailable
              : GaslessAvailability.stale,
        ),
      );
    }
  }

  GaslessAvailability _availabilityForGaslessStatus(
    GaslessAccountStatusResponse status,
  ) {
    if (status.providerAvailable) return GaslessAvailability.ready;

    return switch (status.reasonCode) {
      'provider_temporarily_unavailable' =>
        GaslessAvailability.temporarilyUnavailable,
      'token_unsupported' ||
      'token_decimals_mismatch' => GaslessAvailability.unsupported,
      'custody_address_mismatch' ||
      'provider_identity_mismatch' ||
      'provider_invalid_response' => GaslessAvailability.securityMismatch,
      'provider_authentication_failed' => GaslessAvailability.disabled,
      _ => GaslessAvailability.providerUnavailable,
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
    final requestState = state;
    if (requestState.hasValidationErrors) return;
    final guardError = _previewGuardError();
    if (guardError != null) {
      emit(
        requestState.copyWith(
          previewError: () => guardError,
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

      // A gas-free withdrawal that is short on custody balance surfaces a plain,
      // USDT-denominated error telling the user to add USDT to their gasless
      // address (see `_normalizeGaslessError`). There is no TRX-paid top-up: the
      // custody address is the account, funded by receiving USDT into it.
      emit(
        state.copyWith(
          previewError: () => _buildTextError(e),
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

    final guardError = _previewGuardError();
    if (guardError != null) {
      emit(
        requestState.copyWith(
          isPreviewRefreshing: false,
          isPreviewExpired: true,
          previewSecondsRemaining: () => 0,
          confirmStepError: () => guardError,
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

    try {
      final transfers = await _sdk.withdrawals.listPendingGaslessTransfers();
      final matching = transfers
          .where(
            (transfer) =>
                transfer.assetId == state.asset.id.id &&
                !transfer.state.isTerminal,
          )
          .sortedBy((transfer) => transfer.updatedAt);
      final pending = matching.lastOrNull;
      if (pending == null) return;

      _cancelTronPreviewTimer();
      emit(
        state.copyWith(
          step: WithdrawFormStep.pending,
          recipientAddress: pending.destinationAddress,
          amount: pending.requestedAmount.toString(),
          isMaxAmount: false,
          isGaslessEnabled: true,
          preview: () => null,
          authorizedRecipientAmount: () => pending.requestedAmount,
          result: () => null,
          isSending: false,
          gaslessStatusMessage: () =>
              LocaleKeys.withdrawGaslessStatusUnknown.tr(),
          gaslessTraceState: () => null,
          gaslessTransferState: () => pending.state,
          gaslessTraceId: () => pending.traceId,
          gaslessRequestId: () => pending.requestId,
          gaslessSubmittedAt: () => pending.acceptedAt,
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

      // Reconciliation is safe to start immediately: it only queries the
      // already-accepted trace and can never submit the signed payload again.
      add(const WithdrawFormGaslessTraceCheckRequested());
    } catch (error, stackTrace) {
      // A local-store read failure may be hiding an accepted transfer. Keep
      // the Standard rail available, but fail closed for every new GasFree
      // preview/submission until the encrypted journal is readable again.
      _logger.warning(
        'Unable to restore pending GasFree transfers',
        error,
        stackTrace,
      );
      _cancelTronPreviewTimer();
      emit(
        state.copyWith(
          step: WithdrawFormStep.fill,
          gaslessPendingStoreHealthy: false,
          isGaslessEnabled: false,
          gaslessAvailability: GaslessAvailability.securityMismatch,
          preview: () => null,
          authorizedRecipientAmount: () => null,
          previewError: () => TextError(
            error: LocaleKeys.withdrawGaslessStorageUnavailable.tr(),
          ),
          previewExpiresAt: () => null,
          previewSecondsRemaining: () => null,
          isPreviewExpired: false,
        ),
      );
    }
  }

  Future<void> _onGaslessTraceCheckRequested(
    WithdrawFormGaslessTraceCheckRequested event,
    Emitter<WithdrawFormState> emit,
  ) async {
    final traceId = state.gaslessTraceId;
    final requestId = state.gaslessRequestId;
    final reconciliationId = traceId?.isNotEmpty == true
        ? traceId
        : requestId?.isNotEmpty == true
        ? requestId
        : null;
    if (reconciliationId == null || state.isSending) return;

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
          in _sdk.withdrawals.resumePendingGaslessTransfer(reconciliationId)) {
        // Only the typed relay submission may supply a provider trace. The
        // generic task ID is also used for request-only records and therefore
        // must never be promoted into a pollable trace identity.
        final progressTraceId =
            progress.submission?.traceId ?? state.gaslessTraceId;
        final progressRequestId =
            progress.submission?.requestId ?? state.gaslessRequestId;
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
              gaslessRequestId: () => progressRequestId,
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

        if (progress.status == WithdrawalStatus.error) {
          throw progress.sdkError ??
              Exception(progress.errorMessage ?? 'GasFree trace check failed');
        }

        if (transferState == GaslessTransferState.failedFinal) {
          _emitGaslessFinalFailure(emit, TextError(error: progress.message));
          return;
        }

        emit(
          state.copyWith(
            step: WithdrawFormStep.pending,
            isSending: true,
            gaslessStatusMessage: () => progress.message,
            gaslessTraceState: () => progress.gaslessState,
            gaslessTransferState: () => transferState,
            gaslessTraceId: () => progressTraceId,
            gaslessRequestId: () => progressRequestId,
          ),
        );
      }

      // A reconciliation stream may finish after its bounded polling window
      // without a terminal answer. That is still an accepted transfer, not a
      // failed send, and must remain locked against resubmission.
      _emitGaslessSubmittedUnknown(
        emit,
        LocaleKeys.withdrawGaslessStatusUnknown.tr(),
      );
    } catch (error) {
      if (_isAuthoritativeGaslessFinalFailure(error)) {
        _emitGaslessFinalFailure(emit, _buildTextError(error));
      } else {
        _emitGaslessSubmittedUnknown(
          emit,
          LocaleKeys.withdrawGaslessStatusUnknown.tr(),
        );
      }
    }
  }

  Future<void> _onSubmitted(
    WithdrawFormSubmitted event,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (!await _authorizeWithdrawal(emit)) return;
    if (state.hasValidationErrors) return;
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

    // Backstop: never broadcast a native (TRX-funded) transfer when the user
    // asked for gas-free. KDF fell back to native (e.g. the GasFree custody
    // address is unfunded); block the send and direct the user to send a
    // standard transfer explicitly by unticking gas-free. The confirm UI also
    // disables the Send button for this case, so this guard rarely fires.
    if (state.didGaslessDowngrade) {
      emit(
        state.copyWith(
          confirmStepError: () => TextError(
            // The standard (native) TRC20 transfer fee is paid in the platform
            // coin (TRX), not the token being sent — use the native fee coin so
            // this matches the confirm-step `_GaslessUnavailableNotice`.
            error: LocaleKeys.withdrawGaslessUnavailableBlocked.tr(
              args: [(state.preview!.fee as FeeInfoTron).coin],
            ),
          ),
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
          gaslessTransferState: () =>
              state.useGasless ? GaslessTransferState.preparing : null,
          gaslessTraceId: () => null,
          gaslessRequestId: () => null,
          gaslessSubmittedAt: () => null,
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
        // with only a wallet request ID and no provider trace; the catch path
        // must still see that post-submission state and block resubmission.
        if (state.useGasless && progress.status != WithdrawalStatus.complete) {
          final submission = progress.submission;
          final traceId = submission?.traceId ?? state.gaslessTraceId;
          final requestId = submission?.requestId ?? state.gaslessRequestId;
          emit(
            state.copyWith(
              gaslessStatusMessage: () => progress.message,
              gaslessTraceState: () => progress.gaslessState,
              gaslessTransferState: () => _gaslessTransferStateForProgress(
                progress,
                hasAcceptedTrace: traceId != null,
              ),
              gaslessTraceId: () => traceId,
              gaslessRequestId: () => requestId,
              gaslessSubmittedAt: () => traceId == null && requestId == null
                  ? state.gaslessSubmittedAt
                  : state.gaslessSubmittedAt ?? DateTime.now().toUtc(),
            ),
          );
        }

        if (progress.status == WithdrawalStatus.complete) {
          result = progress.withdrawalResult;
          if (state.useGasless) {
            final submission = progress.submission;
            emit(
              state.copyWith(
                gaslessTransferState: () => GaslessTransferState.confirmed,
                gaslessTraceId: () =>
                    submission?.traceId ?? state.gaslessTraceId,
                gaslessRequestId: () =>
                    submission?.requestId ?? state.gaslessRequestId,
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
        if (state.useGasless && _hasPossiblySubmittedGaslessTransfer) {
          _emitGaslessSubmittedUnknown(
            emit,
            LocaleKeys.withdrawGaslessStatusUnknown.tr(),
          );
          return;
        }
        emit(
          state.copyWith(
            isSending: false,
            transactionError: () =>
                TextError(error: LocaleKeys.withdrawNoResultError.tr()),
            isAwaitingTrezorConfirmation: false,
            gaslessTransferState: () => state.useGasless
                ? GaslessTransferState.rejectedBeforeRelay
                : null,
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
          gaslessStatusMessage: () => null,
          gaslessTraceState: () => null,
          gaslessTransferState: () =>
              state.useGasless ? GaslessTransferState.confirmed : null,
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

      if (state.useGasless && _hasPossiblySubmittedGaslessTransfer) {
        if (_isAuthoritativeGaslessFinalFailure(e)) {
          _emitGaslessFinalFailure(emit, _buildTextError(e));
        } else {
          _emitGaslessSubmittedUnknown(
            emit,
            LocaleKeys.withdrawGaslessStatusUnknown.tr(),
          );
        }
      } else {
        emit(
          state.copyWith(
            transactionError: () => _buildTextError(e),
            step: WithdrawFormStep.failed,
            isSending: false,
            isPreviewRefreshing: false,
            isAwaitingTrezorConfirmation: false,
            gaslessStatusMessage: () => null,
            gaslessTraceState: () => null,
            gaslessTransferState: () => state.useGasless
                ? GaslessTransferState.rejectedBeforeRelay
                : null,
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
  /// returns a trace. The SDK persists that ambiguity with a request ID and a
  /// typed post-submission state. Neither case may be downgraded to a safe
  /// pre-relay rejection, because doing so would enable a duplicate send.
  bool get _hasPossiblySubmittedGaslessTransfer =>
      state.gaslessTraceId?.isNotEmpty == true ||
      state.gaslessRequestId?.isNotEmpty == true ||
      state.gaslessTransferState?.hasRelayAccepted == true;

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
    emit(
      WithdrawFormState(
        asset: state.asset,
        step: WithdrawFormStep.fill,
        recipientAddress: '',
        amount: '0',
        walletType: state.walletType,
        isGaslessFeatureConfigured: state.isGaslessFeatureConfigured,
        gaslessPendingStoreHealthy: state.gaslessPendingStoreHealthy,
        pubkeys: state.pubkeys,
        selectedSourceAddress:
            _initialSourceAddress ?? state.pubkeys?.keys.firstOrNull,
        isSourceSelectionLocked: _lockSourceSelection,
        isGaslessEnabled: _initialGaslessEnabled,
        gaslessAvailability: state.gaslessPendingStoreHealthy
            ? GaslessAvailability.initial
            : GaslessAvailability.securityMismatch,
      ),
    );
    // The fresh state dropped the cached custody snapshot; re-request it.
    if (state.isGaslessSupported) {
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
