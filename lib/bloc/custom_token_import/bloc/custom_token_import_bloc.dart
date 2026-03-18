import 'dart:async' show TimeoutException;

import 'package:decimal/decimal.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart' show poll;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/analytics/events/portfolio_events.dart';
import 'package:web_dex/bloc/analytics/analytics_bloc.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/bloc/custom_token_import/bloc/custom_token_import_event.dart';
import 'package:web_dex/bloc/custom_token_import/bloc/custom_token_import_state.dart';
import 'package:web_dex/bloc/custom_token_import/data/custom_token_import_repository.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/shared/utils/extensions/kdf_user_extensions.dart';

class CustomTokenImportBloc
    extends Bloc<CustomTokenImportEvent, CustomTokenImportState> {
  CustomTokenImportBloc(
    this._repository,
    this._coinsRepo,
    this._sdk,
    this._analyticsBloc,
  ) : super(CustomTokenImportState.defaults()) {
    on<UpdateNetworkEvent>(_onUpdateAsset);
    on<UpdateAddressEvent>(_onUpdateAddress);
    on<SubmitImportCustomTokenEvent>(_onSubmitImportCustomToken);
    on<SubmitFetchCustomTokenEvent>(_onSubmitFetchCustomToken);
    on<ResetFormStatusEvent>(_onResetFormStatus);
  }

  final ICustomTokenImportRepository _repository;
  final CoinsRepo _coinsRepo;
  final KomodoDefiSdk _sdk;
  final AnalyticsBloc _analyticsBloc;
  final _log = Logger('CustomTokenImportBloc');

  void _onResetFormStatus(
    ResetFormStatusEvent event,
    Emitter<CustomTokenImportState> emit,
  ) {
    final availableCoinTypes = CoinType.values.map(
      (CoinType type) => type.toCoinSubClass(),
    );
    final items = CoinSubClass.values.where((CoinSubClass type) {
      final isAvailable = availableCoinTypes.contains(type);
      final isSupported = _repository.getNetworkApiName(type) != null;
      return isAvailable && isSupported;
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    emit(
      state.copyWith(
        formStatus: FormStatus.initial,
        formErrorMessage: '',
        importStatus: FormStatus.initial,
        importErrorMessage: '',
        supportedNetworks: items,
      ),
    );
  }

  void _onUpdateAsset(
    UpdateNetworkEvent event,
    Emitter<CustomTokenImportState> emit,
  ) {
    if (event.network == null) {
      return;
    }
    emit(state.copyWith(network: event.network));
  }

  void _onUpdateAddress(
    UpdateAddressEvent event,
    Emitter<CustomTokenImportState> emit,
  ) {
    emit(state.copyWith(address: event.address));
  }

  Future<void> _onSubmitFetchCustomToken(
    SubmitFetchCustomTokenEvent event,
    Emitter<CustomTokenImportState> emit,
  ) async {
    emit(state.copyWith(formStatus: FormStatus.submitting));

    Asset? tokenData;
    var wasTokenAlreadyActivated = false;
    try {
      final platformAsset = _sdk.getSdkAsset(state.network.ticker);

      // Network (parent) asset must be active before attempting to fetch the
      // custom token data
      await _coinsRepo.activateAssetsSync(
        [platformAsset],
        notifyListeners: false,
        addToWalletMetadata: false,
      );

      tokenData = await _repository.fetchCustomToken(
        network: state.network,
        platformAsset: platformAsset,
        address: state.address,
      );
      wasTokenAlreadyActivated = await _coinsRepo.isAssetActivated(
        tokenData.id,
      );
      await _coinsRepo.activateAssetsSync(
        [tokenData],
        addToWalletMetadata: false,
        notifyListeners: false,
        // The default coin activation is generous, assuming background retries,
        // but we limit it here to avoid waiting too long in the dialog.
        maxRetryAttempts: 10,
      );
      await _waitForCustomTokenPropagation(tokenData);

      final balanceInfo = await _coinsRepo.tryGetBalanceInfo(tokenData.id);
      final balance = balanceInfo.spendable;
      final usdBalance = _coinsRepo.getUsdPriceByAmount(
        balance.toString(),
        tokenData.id.id,
      );

      emit(
        state.copyWith(
          formStatus: FormStatus.success,
          tokenData: () => tokenData,
          tokenBalance: balance,
          tokenBalanceUsd:
              Decimal.tryParse(usdBalance?.toString() ?? '0.0') ?? Decimal.zero,
          formErrorMessage: '',
        ),
      );
    } catch (e, s) {
      _log.severe('Error fetching custom token', e, s);
      emit(
        state.copyWith(
          formStatus: FormStatus.failure,
          tokenData: () => null,
          formErrorMessage: _formatImportError(e),
        ),
      );
    } finally {
      if (tokenData != null && !wasTokenAlreadyActivated) {
        // Activate to get balance, then deactivate to avoid confusion if the user
        // does not proceed with the import (exits the dialog).
        await _coinsRepo.deactivateCoinsSync([tokenData.toCoin()]);
      }
    }
  }

  /// wait for the asset to appear in the known asset list with a 5-second
  /// timeout using the poll function from sdk type utils package
  /// and ignore timeout exception
  Future<void> _waitForCustomTokenPropagation(
    Asset tokenData, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      await poll<bool>(
        () async {
          await Future.delayed(const Duration(seconds: 1));
          return _sdk.assets.available.containsKey(tokenData.id);
        },
        isComplete: (assetExists) => assetExists,
        maxDuration: timeout,
      );
    } on TimeoutException catch (_) {
      _log.warning(
        'Timeout waiting for asset to appear in the known asset list',
      );
    }
  }

  Future<void> _onSubmitImportCustomToken(
    SubmitImportCustomTokenEvent event,
    Emitter<CustomTokenImportState> emit,
  ) async {
    emit(state.copyWith(importStatus: FormStatus.submitting));

    try {
      await _repository.importCustomToken(state.coin!);

      final walletType = (await _sdk.auth.currentUser)?.type ?? '';
      _analyticsBloc.logEvent(
        AssetAddedEventData(
          asset: state.coin!.id.id,
          network: state.network.ticker,
          hdType: walletType,
        ),
      );

      emit(
        state.copyWith(
          importStatus: FormStatus.success,
          importErrorMessage: '',
        ),
      );
    } catch (e, s) {
      _log.severe('Error importing custom token', e, s);
      emit(
        state.copyWith(
          importStatus: FormStatus.failure,
          importErrorMessage: _formatImportError(e),
        ),
      );
    }
  }

  String _formatImportError(Object error) {
    return switch (error) {
      final CustomTokenConflictException e => e.message,
      final UnsupportedCustomTokenNetworkException e => e.message,
      _ => error.toString(),
    };
  }

  @override
  Future<void> close() async {
    _repository.dispose();
    await super.close();
  }
}
