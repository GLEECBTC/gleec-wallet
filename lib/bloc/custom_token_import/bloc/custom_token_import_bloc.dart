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
import 'package:web_dex/model/kdf_auth_metadata_extension.dart';
import 'package:web_dex/shared/utils/extensions/kdf_user_extensions.dart';

class _CustomTokenPreviewSession {
  const _CustomTokenPreviewSession({
    required this.platformAsset,
    required this.wasPlatformAlreadyActivated,
    required this.wasPlatformAlreadyInWalletMetadata,
    this.tokenAsset,
    this.wasTokenAlreadyActivated = false,
    this.wasTokenAlreadyInWalletMetadata = false,
    this.wasTokenAlreadyKnown = false,
  });

  final Asset platformAsset;
  final bool wasPlatformAlreadyActivated;
  final bool wasPlatformAlreadyInWalletMetadata;
  final Asset? tokenAsset;
  final bool wasTokenAlreadyActivated;
  final bool wasTokenAlreadyInWalletMetadata;
  final bool wasTokenAlreadyKnown;

  _CustomTokenPreviewSession copyWith({
    Asset? platformAsset,
    bool? wasPlatformAlreadyActivated,
    bool? wasPlatformAlreadyInWalletMetadata,
    Asset? Function()? tokenAsset,
    bool? wasTokenAlreadyActivated,
    bool? wasTokenAlreadyInWalletMetadata,
    bool? wasTokenAlreadyKnown,
  }) {
    return _CustomTokenPreviewSession(
      platformAsset: platformAsset ?? this.platformAsset,
      wasPlatformAlreadyActivated:
          wasPlatformAlreadyActivated ?? this.wasPlatformAlreadyActivated,
      wasPlatformAlreadyInWalletMetadata:
          wasPlatformAlreadyInWalletMetadata ??
          this.wasPlatformAlreadyInWalletMetadata,
      tokenAsset: tokenAsset != null ? tokenAsset() : this.tokenAsset,
      wasTokenAlreadyActivated:
          wasTokenAlreadyActivated ?? this.wasTokenAlreadyActivated,
      wasTokenAlreadyInWalletMetadata:
          wasTokenAlreadyInWalletMetadata ??
          this.wasTokenAlreadyInWalletMetadata,
      wasTokenAlreadyKnown: wasTokenAlreadyKnown ?? this.wasTokenAlreadyKnown,
    );
  }
}

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
  _CustomTokenPreviewSession? _previewSession;

  Future<void> _onResetFormStatus(
    ResetFormStatusEvent event,
    Emitter<CustomTokenImportState> emit,
  ) async {
    await _rollbackPreviewIfNeeded();

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

    try {
      final walletCoinIds = (await _sdk.getWalletCoinIds()).toSet();
      final platformAsset = _sdk.getSdkAsset(state.network.ticker);
      final wasPlatformAlreadyActivated = await _coinsRepo.isAssetActivated(
        platformAsset.id,
      );
      _previewSession = _CustomTokenPreviewSession(
        platformAsset: platformAsset,
        wasPlatformAlreadyActivated: wasPlatformAlreadyActivated,
        wasPlatformAlreadyInWalletMetadata: walletCoinIds.contains(
          platformAsset.id.id,
        ),
      );

      // Network (parent) asset must be active before attempting to fetch the
      // custom token data
      await _coinsRepo.activateAssetsSync(
        [platformAsset],
        notifyListeners: false,
        addToWalletMetadata: false,
      );

      final tokenData = await _repository.fetchCustomToken(
        network: state.network,
        platformAsset: platformAsset,
        address: state.address,
      );
      final wasTokenAlreadyKnown = _sdk.assets.available.containsKey(
        tokenData.id,
      );
      final wasTokenAlreadyActivated = await _coinsRepo.isAssetActivated(
        tokenData.id,
      );
      _previewSession = _previewSession?.copyWith(
        tokenAsset: () => tokenData,
        wasTokenAlreadyActivated: wasTokenAlreadyActivated,
        wasTokenAlreadyInWalletMetadata: walletCoinIds.contains(
          tokenData.id.id,
        ),
        wasTokenAlreadyKnown: wasTokenAlreadyKnown,
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
      final usdBalance = _coinsRepo.getUsdPriceForAmount(
        balance.toDouble(),
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
      await _rollbackPreviewIfNeeded();
      emit(
        state.copyWith(
          formStatus: FormStatus.failure,
          tokenData: () => null,
          formErrorMessage: _formatImportError(e),
        ),
      );
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
      _previewSession = null;

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

  Future<void> _rollbackPreviewIfNeeded() async {
    final previewSession = _previewSession;
    _previewSession = null;

    if (previewSession == null) {
      return;
    }

    final rollbackAssets = <Asset>[];
    final deleteCustomTokens = <AssetId>{};
    final removeWalletMetadataAssets = <AssetId>{};

    final tokenAsset = previewSession.tokenAsset;
    if (tokenAsset != null && !previewSession.wasTokenAlreadyActivated) {
      rollbackAssets.add(tokenAsset);
      if (!previewSession.wasTokenAlreadyInWalletMetadata) {
        removeWalletMetadataAssets.add(tokenAsset.id);
      }
      if (!previewSession.wasTokenAlreadyKnown &&
          !previewSession.wasTokenAlreadyInWalletMetadata) {
        deleteCustomTokens.add(tokenAsset.id);
      }
    }

    if (!previewSession.wasPlatformAlreadyActivated) {
      rollbackAssets.add(previewSession.platformAsset);
      if (!previewSession.wasPlatformAlreadyInWalletMetadata) {
        removeWalletMetadataAssets.add(previewSession.platformAsset.id);
      }
    }

    if (rollbackAssets.isEmpty &&
        deleteCustomTokens.isEmpty &&
        removeWalletMetadataAssets.isEmpty) {
      return;
    }

    try {
      await _coinsRepo.rollbackPreviewAssets(
        rollbackAssets,
        deleteCustomTokens: deleteCustomTokens,
        removeWalletMetadataAssets: removeWalletMetadataAssets,
      );
    } catch (e, s) {
      _log.warning('Failed to rollback preview activation state', e, s);
    }
  }

  @override
  Future<void> close() async {
    await _rollbackPreviewIfNeeded();
    _repository.dispose();
    await super.close();
  }
}
