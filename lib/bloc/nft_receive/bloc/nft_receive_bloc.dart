import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/coins_bloc/coins_repo.dart';
import 'package:web_dex/model/nft.dart';

part 'nft_receive_event.dart';
part 'nft_receive_state.dart';

class NftReceiveBloc extends Bloc<NftReceiveEvent, NftReceiveState> {
  NftReceiveBloc({required CoinsRepo coinsRepo, required KomodoDefiSdk sdk})
    : _coinsRepo = coinsRepo,
      _sdk = sdk,
      super(NftReceiveInitial()) {
    on<NftReceiveStarted>(_onInitial);
    on<NftReceiveRefreshRequested>(_onRefresh);
    on<NftReceiveAddressChanged>(_onChangeAddress);
  }

  final CoinsRepo _coinsRepo;
  final KomodoDefiSdk _sdk;
  final _log = Logger('NftReceiveBloc');
  NftBlockchains? chain;

  Future<void> _onInitial(
    NftReceiveStarted event,
    Emitter<NftReceiveState> emit,
  ) async {
    if (state is NftReceiveLoadSuccess) {
      _log.fine('Already in NftReceiveAddress state, skipping initialization');
      return;
    }

    chain = event.chain;
    final abbr = event.chain.coinAbbr();
    final coin = _coinsRepo.getCoin(abbr);
    if (coin == null) {
      _log.warning('Failed to find coin for chain: ${event.chain}');
      return emit(const NftReceiveLoadFailure());
    }

    final asset = _sdk.assets.available[coin.id]!;
    final pubkeys =
        _sdk.pubkeys.lastKnown(asset.id) ??
        await _sdk.pubkeys.getPubkeys(asset);
    if (pubkeys.keys.isEmpty) {
      _log.warning('No pubkey found for the asset: ${coin.id.id}');
      return emit(
        const NftReceiveLoadFailure(message: 'No pubkey found for the asset'),
      );
    }

    // Select the first address by default
    final selectedAddress = pubkeys.keys.first;
    _log.info('Successfully initialized, address: ${selectedAddress.address}');
    return emit(
      NftReceiveLoadSuccess(
        asset: asset,
        pubkeys: pubkeys,
        selectedAddress: selectedAddress,
      ),
    );
  }

  Future<void> _onRefresh(
    NftReceiveRefreshRequested event,
    Emitter<NftReceiveState> emit,
  ) async {
    _log.info('Refreshing NFT receive data');
    final localChain = chain;
    if (localChain != null) {
      _log.fine('Chain is available, reinitializing with chain: $localChain');
      emit(NftReceiveInitial());
      add(NftReceiveStarted(chain: localChain));
    } else {
      _log.warning('Cannot refresh - chain is null');
      return emit(const NftReceiveLoadFailure());
    }
  }

  void _onChangeAddress(
    NftReceiveAddressChanged event,
    Emitter<NftReceiveState> emit,
  ) {
    _log.info('Changing selected address to: ${event.address}');
    final state = this.state;
    if (state is! NftReceiveLoadSuccess) {
      _log.warning('Cannot change address - not in NftReceiveAddress state');
      return;
    }
    // Find the matching pubkey info from pubkeys
    final selectedPubkey = state.pubkeys.keys.firstWhere(
      (PubkeyInfo key) => key.address == event.address?.address,
      orElse: () => state.selectedAddress!,
    );

    _log.fine('Selected pubkey: ${selectedPubkey.address}');
    return emit(state.copyWith(selectedAddress: selectedPubkey));
  }
}
