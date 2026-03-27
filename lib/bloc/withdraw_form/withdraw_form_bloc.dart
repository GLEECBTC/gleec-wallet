import 'dart:async';

import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
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
import 'package:web_dex/shared/utils/formatters.dart';
import 'package:web_dex/shared/utils/kdf_error_display.dart';
import 'package:web_dex/shared/utils/platform_tuner.dart';
import 'package:collection/collection.dart';

export 'package:web_dex/bloc/withdraw_form/withdraw_form_event.dart';
export 'package:web_dex/bloc/withdraw_form/withdraw_form_state.dart';
export 'package:web_dex/bloc/withdraw_form/withdraw_form_step.dart';

import 'package:decimal/decimal.dart';

class WithdrawFormBloc extends Bloc<WithdrawFormEvent, WithdrawFormState> {
  static final Logger _logger = Logger('WithdrawFormBloc');
  static const _unsupportedSiaHardwareWalletMessage =
      'SIA is not supported for hardware wallets in this release.';

  final KomodoDefiSdk _sdk;
  final WalletType? _walletType;
  Timer? _tronPreviewTimer;

  WithdrawFormBloc({
    required Asset asset,
    required KomodoDefiSdk sdk,
    required Mm2Api mm2Api,
    WalletType? walletType,
  }) : _sdk = sdk,
       _walletType = walletType,
       super(
         WithdrawFormState(
           asset: asset,
           step: WithdrawFormStep.fill,
           recipientAddress: '',
           amount: '0',
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
    on<WithdrawFormFeePriorityChanged>(_onFeePriorityChanged);
    on<WithdrawFormMemoChanged>(_onMemoChanged);
    on<WithdrawFormIbcTransferEnabled>(_onIbcTransferEnabled);
    on<WithdrawFormIbcChannelChanged>(_onIbcChannelChanged);
    on<WithdrawFormPreviewSubmitted>(
      _onPreviewSubmitted,
      transformer: droppable(),
    );
    on<WithdrawFormSubmitted>(_onSubmitted, transformer: droppable());
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
  }

  bool _isTronAsset(Asset asset) =>
      asset.protocol is TrxProtocol || asset.protocol is Trc20Protocol;

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

    return null;
  }

  Future<WithdrawalPreview> _generatePreview(
    WithdrawFormState requestState,
    Emitter<WithdrawFormState> emit,
  ) async {
    if (_walletType == WalletType.trezor) {
      emit(requestState.copyWith(isAwaitingTrezorConfirmation: true));
    }

    final params = requestState.toWithdrawParameters();
    return _sdk.withdrawals.previewWithdrawal(params);
  }

  void _emitPreviewState(
    Emitter<WithdrawFormState> emit,
    WithdrawFormState requestState,
    WithdrawalPreview preview, {
    required bool moveToConfirm,
  }) {
    final expiryAt = _buildPreviewExpiryAt(requestState, preview);
    final secondsRemaining = expiryAt == null
        ? null
        : _calculatePreviewSecondsRemaining(expiryAt);
    final isExpired = secondsRemaining != null && secondsRemaining <= 0;
    final nextState = requestState.copyWith(
      preview: () => preview,
      step: moveToConfirm ? WithdrawFormStep.confirm : requestState.step,
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

  TextError _buildPreviewRefreshError(Object error) {
    return TextError(
      error:
          '${LocaleKeys.withdrawTronPreviewRefreshFailed.tr()} ${_formatErrorMessage(error)}',
      technicalDetails: _extractTechnicalDetails(error),
    );
  }

  String _formatErrorMessage(Object error, {String? fallbackPrefix}) {
    String resolvedMessage;

    if (error is MmRpcException) {
      resolvedMessage = error.localizedMessage;
    } else if (error is GeneralErrorResponse) {
      resolvedMessage = error.localizedMessage;
    } else if (error is SdkError) {
      final localized = error.messageKey.tr(args: error.messageArgs);
      resolvedMessage = localized == error.messageKey
          ? error.fallbackMessage
          : localized;
    } else {
      resolvedMessage = error.toString();
    }

    final message = _normalizeCommonErrors(resolvedMessage);
    return fallbackPrefix == null ? message : '$fallbackPrefix: $message';
  }

  String _extractTechnicalDetails(Object error) {
    if (error is SdkError) {
      return error.fallbackMessage;
    }
    if (error is MmRpcException) {
      return error.message ?? error.toString();
    }
    if (error is GeneralErrorResponse) {
      return error.error ?? error.toString();
    }
    if (error is WithdrawalException) {
      return error.message;
    }
    return error.toString();
  }

  TextError _buildTextError(Object error, {String? fallbackPrefix}) {
    return TextError(
      error: _formatErrorMessage(error, fallbackPrefix: fallbackPrefix),
      technicalDetails: _extractTechnicalDetails(error),
    );
  }

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
      return 'kdfErrorNotSufficientBalance'.tr();
    }

    if (normalized.contains('failed to fetch') ||
        normalized.contains('network error') ||
        normalized.contains('timed out') ||
        normalized.contains('timeout')) {
      return 'kdfErrorTransport'.tr();
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
      final cached = _sdk.pubkeys.lastKnown(state.asset.id);
      final pubkeys = cached ?? await state.asset.getPubkeys(_sdk);
      final fundedKeys = pubkeys.keys
          .where((key) => key.balance.spendable > Decimal.zero)
          .toList();

      if (fundedKeys.isNotEmpty) {
        final filteredPubkeys = AssetPubkeys(
          assetId: pubkeys.assetId,
          keys: fundedKeys,
          availableAddressesCount: pubkeys.availableAddressesCount,
          syncStatus: pubkeys.syncStatus,
        );

        final current = state.selectedSourceAddress;
        final newSelection = current != null
            ? fundedKeys.firstWhereOrNull(
                    (key) => key.address == current.address,
                  ) ??
                  fundedKeys.first
            : (fundedKeys.length == 1 ? fundedKeys.first : null);
        emit(
          state.copyWith(
            pubkeys: () => filteredPubkeys,
            networkError: () => null,
            selectedSourceAddress: () => newSelection,
          ),
        );
      } else {
        emit(
          state.copyWith(
            networkError: () => TextError(
              error: 'No funded addresses found for ${state.asset.id.name}',
            ),
          ),
        );
      }
    } catch (e) {
      emit(
        state.copyWith(
          networkError: () => TextError(error: 'Failed to load addresses: $e'),
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
          recipientAddressError: () =>
              TextError(error: 'Address validation failed: $e'),
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

      if (balance != null && amount > balance) {
        emit(
          state.copyWith(
            amount: event.amount,
            amountError: () => TextError(error: 'Insufficient funds'),
          ),
        );
        return;
      }

      if (amount <= Decimal.zero) {
        emit(
          state.copyWith(
            amount: event.amount,
            amountError: () =>
                TextError(error: 'Amount must be greater than 0'),
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
          amountError: () => TextError(error: 'Invalid amount'),
        ),
      );
    }
  }

  void _onSourceChanged(
    WithdrawFormSourceChanged event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
    final balance = event.address.balance;
    final updatedAmount = state.isMaxAmount
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
    if (event.isEnabled && state.asset.id.parentId != null) {
      final parentId = state.asset.id.parentId!;
      final parentBalance =
          _sdk.balances.lastKnown(parentId) ??
          await _sdk.balances.getBalance(parentId);

      if (parentBalance.spendable == Decimal.zero) {
        emit(
          state.copyWith(
            isMaxAmount: false,
            amountError: () =>
                TextError(error: LocaleKeys.notEnoughBalanceForGasError.tr()),
          ),
        );
        return;
      }
    }

    final balance =
        state.selectedSourceAddress?.balance ?? state.pubkeys?.balance;
    final maxAmount = event.isEnabled
        ? (balance?.spendable.toString() ?? '0')
        : '0';

    emit(
      state.copyWith(
        isMaxAmount: event.isEnabled,
        amount: maxAmount,
        amountError: () => null,
        previewError: () => null, // Clear preview error when toggling max
      ),
    );
  }

  void _onCustomFeeEnabled(
    WithdrawFormCustomFeeEnabled event,
    Emitter<WithdrawFormState> emit,
  ) {
    if (state.isSending || state.step != WithdrawFormStep.fill) return;
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
          isAwaitingTrezorConfirmation: false,
        ),
      );

      final preview = await _generatePreview(requestState, emit);
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

      emit(
        requestState.copyWith(
          previewError: () =>
              _buildTextError(e, fallbackPrefix: 'Failed to generate preview'),
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
          isAwaitingTrezorConfirmation: false,
        ),
      );

      final preview = await _generatePreview(requestState, emit);
      _emitPreviewState(emit, requestState, preview, moveToConfirm: false);
    } catch (e) {
      emit(
        requestState.copyWith(
          isPreviewRefreshing: false,
          isPreviewExpired: true,
          previewSecondsRemaining: () => 0,
          confirmStepError: () => _buildPreviewRefreshError(e),
          isAwaitingTrezorConfirmation: false,
        ),
      );
    }
  }

  Future<void> _onSubmitted(
    WithdrawFormSubmitted event,
    Emitter<WithdrawFormState> emit,
  ) async {
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

    try {
      _cancelTronPreviewTimer();

      emit(
        state.copyWith(
          isSending: true,
          transactionError: () => null,
          confirmStepError: () => null,
          // No second device interaction is needed on confirm
          isAwaitingTrezorConfirmation: false,
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
        if (progress.status == WithdrawalStatus.complete) {
          result = progress.withdrawalResult;
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
        emit(
          state.copyWith(
            isSending: false,
            transactionError: () => TextError(
              error: 'Withdrawal did not complete: no result received.',
            ),
            isAwaitingTrezorConfirmation: false,
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

      emit(
        state.copyWith(
          transactionError: () =>
              _buildTextError(e, fallbackPrefix: 'Transaction failed'),
          step: WithdrawFormStep.failed,
          isSending: false,
          isPreviewRefreshing: false,
          isAwaitingTrezorConfirmation: false,
        ),
      );
    }
  }

  bool get _isUnsupportedSiaHardwareWalletFlow =>
      _walletType == WalletType.trezor && state.asset.protocol is SiaProtocol;

  bool get _isSelfTransfer {
    final source = state.selectedSourceAddress?.address;
    final recipient = state.recipientAddress.trim();
    if (source == null || recipient.isEmpty) return false;
    return source == recipient;
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
        pubkeys: state.pubkeys,
        selectedSourceAddress: state.pubkeys?.keys.first,
      ),
    );
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
          recipientAddressError: () =>
              TextError(error: 'Failed to convert address: $e'),
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
