import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart'
    show retry, ExponentialBackoff;
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:logging/logging.dart';
import 'package:web_dex/bloc/nfts/nft_main_repo.dart';
import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/model/text_error.dart';

part 'nft_main_event.dart';
part 'nft_main_state.dart';

class NftMainBloc extends Bloc<NftMainEvent, NftMainState> {
  NftMainBloc({
    required NftsRepo repo,
    required KomodoDefiSdk sdk,
  })  : _repo = repo,
        _sdk = sdk,
        super(NftMainState.initial()) {
    on<NftMainChainUpdateRequested>(_onChainNftsUpdateRequested,
        transformer: restartable());
    on<NftMainTabChanged>(_onTabChanged);
    on<NftMainResetRequested>(_onReset);
    on<NftMainChainNftsRefreshed>(_onRefreshForChain);
    on<NftMainUpdateNftsStarted>(_onStartUpdate);
    on<NftMainUpdateNftsStopped>(_onStopUpdate);

    _authorizationSubscription = _sdk.auth.watchCurrentUser().listen((event) {
      final isSignedIn = event != null;
      if (isSignedIn) {
        add(const NftMainChainUpdateRequested());
      } else {
        add(const NftMainResetRequested());
      }
    });
  }

  final NftsRepo _repo;
  final KomodoDefiSdk _sdk;
  late StreamSubscription<KdfUser?> _authorizationSubscription;
  Timer? _updateTimer;
  final _log = Logger('NftMainBloc');

  Future<void> _onTabChanged(
    NftMainTabChanged event,
    Emitter<NftMainState> emit,
  ) async {
    emit(state.copyWith(selectedChain: () => event.chain));
    if (!await _sdk.auth.isSignedIn() || !state.isInitialized) {
      _log.warning(
          'User is not signed in or state is not initialized. Cannot change NFT tab.');
      return;
    }

    try {
      _log.info('Changing NFT tab to ${event.chain}');
      final List<NftToken> nftList = await _repo.getNfts([event.chain]);

      final (newNftS, newNftCount) =
          _recalculateNftsForChain(nftList, event.chain);
      emit(
        state.copyWith(
          nfts: () => newNftS,
          nftCount: () => newNftCount,
          error: () => null,
        ),
      );
      _log.info('Found ${nftList.length} NFTs for chain ${event.chain}');
    } on BaseError catch (e) {
      _log.warning('Error changing NFT tab to ${event.chain}: ${e.message}');
      emit(state.copyWith(error: () => e));
    } catch (e, s) {
      _log.severe('Unexpected error changing NFT tab', e, s);
      emit(state.copyWith(error: () => TextError(error: e.toString())));
    }
  }

  Future<void> _onChainNftsUpdateRequested(
    NftMainChainUpdateRequested event,
    Emitter<NftMainState> emit,
  ) async {
    if (!await _sdk.auth.isSignedIn()) {
      _log.warning('User is not signed in. Cannot update NFT chains.');
      // This guard precedes the try below, so the `finally` does not cover it.
      // Without this the loading screen, which is reachable again now that it
      // no longer depends on the chain list, would spin forever.
      emit(state.copyWith(isInitialized: () => true));
      return;
    }

    try {
      _log.info('Updating all NFT chains');

      final List<NftBlockchains> activatedChains = await _repo
          .getActivatedChains(NftBlockchains.values);
      final Map<NftBlockchains, List<NftToken>> nfts = await _getAllNfts();
      final (counts, sortedChains) = _calculateNftCount(nfts, activatedChains);

      emit(
        state.copyWith(
          nftCount: () => counts,
          nfts: () => nfts,
          sortedChains: () => sortedChains,
          selectedChain: state.isInitialized || sortedChains.isEmpty
              ? null
              : () => sortedChains.first,
          isInitialized: () => true,
          error: () => null,
        ),
      );

      final totalNfts = counts.values.fold(0, (sum, count) => sum + count);
      _log.info(
          'Updated all NFT chains, found $totalNfts NFTs across ${sortedChains.length} chains');
    } on BaseError catch (e) {
      _log.warning('Error updating NFT chains: ${e.message}');
      emit(state.copyWith(error: () => e));
    } catch (e, s) {
      _log.severe('Unexpected error updating NFT chains', e, s);
      emit(state.copyWith(error: () => TextError(error: e.toString())));
    } finally {
      emit(state.copyWith(isInitialized: () => true));
    }
  }

  void _onReset(NftMainResetRequested event, Emitter<NftMainState> emit) {
    _log.info('Resetting NFT state');
    emit(NftMainState.initial());
  }

  Future<void> _onRefreshForChain(
    NftMainChainNftsRefreshed event,
    Emitter<NftMainState> emit,
  ) async {
    if (!await _sdk.auth.isSignedIn() || !state.isInitialized) {
      return;
    }

    final updatingChains = _addUpdatingChains(event.chain);
    emit(state.copyWith(updatingChains: () => updatingChains));

    try {
      _log.info('Refreshing NFTs for chain ${event.chain}');
      final List<NftToken> nftList = await _repo.getNfts([event.chain]);

      final (newNftS, newNftCount) =
          _recalculateNftsForChain(nftList, event.chain);
      emit(
        state.copyWith(
          nfts: () => newNftS,
          nftCount: () => newNftCount,
          error: () => null,
        ),
      );
      _log.info('Refreshed ${nftList.length} NFTs for chain ${event.chain}');
    } on BaseError catch (e) {
      _log.warning(
          'Error refreshing NFTs for chain ${event.chain}: ${e.message}');
      emit(state.copyWith(error: () => e));
    } catch (e, s) {
      _log.severe('Unexpected error refreshing NFTs', e, s);
      emit(state.copyWith(error: () => TextError(error: e.toString())));
    } finally {
      final updatingChains = _removeUpdatingChains(event.chain);
      emit(state.copyWith(updatingChains: () => updatingChains));
    }
  }

  void _onStopUpdate(
      NftMainUpdateNftsStopped event, Emitter<NftMainState> emit) {
    _log.info('Stopping NFT update timer');
    _stopUpdate();
  }

  void _onStartUpdate(
      NftMainUpdateNftsStarted event, Emitter<NftMainState> emit) {
    _log.info('Starting NFT update timer (1 minute interval)');
    _stopUpdate();
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      add(const NftMainChainUpdateRequested());
    });
  }

  Future<Map<NftBlockchains, List<NftToken>>> _getAllNfts({
    List<NftBlockchains> chains = NftBlockchains.values,
  }) async {
    try {
      await retry<void>(
        () async => await _repo.updateNft(chains),
        maxAttempts: 3,
        backoffStrategy:
            ExponentialBackoff(initialDelay: const Duration(seconds: 1)),
      );
    } catch (e, s) {
      _log.severe('Error updating NFTs for chains $chains', e, s);
    }
    final List<NftToken> list = await _repo.getNfts(chains);

    final Map<NftBlockchains, List<NftToken>> nfts =
        list.fold<Map<NftBlockchains, List<NftToken>>>(
      <NftBlockchains, List<NftToken>>{},
      (prev, element) {
        final List<NftToken> chainList = prev[element.chain] ?? []
          ..add(element);
        prev[element.chain] = chainList;

        return prev;
      },
    );

    return nfts;
  }

  (Map<NftBlockchains, int>, List<NftBlockchains>) _calculateNftCount(
    Map<NftBlockchains, List<NftToken>> nfts,
    List<NftBlockchains> activatedChains,
  ) {
    final Map<NftBlockchains, int> countMap = {};

    // Tabs follow the chains the user has *activated*, not the chains that
    // happen to hold an NFT. An activated chain with zero NFTs still earns a
    // tab and the "no collectibles" empty state; keying this off the returned
    // tokens instead told owners of nothing to enable chains they already had.
    // Iterate the enum rather than activatedChains so insertion order stays
    // tied to the declaration order NftBlockchains documents as significant.
    for (final NftBlockchains chain in NftBlockchains.values) {
      if (activatedChains.contains(chain)) {
        countMap[chain] = nfts[chain]?.length ?? 0;
      }
    }

    // Ties are the common case now that zero counts appear, and List.sort is
    // not documented as stable, so fall back to the enum order.
    final sorted = countMap.entries.toList()
      ..sort((a, b) {
        final byCount = b.value - a.value;
        return byCount != 0 ? byCount : a.key.index - b.key.index;
      });
    final List<NftBlockchains> sortedTabs = sorted.map((e) => e.key).toList();

    return (countMap, sortedTabs);
  }

  void _stopUpdate() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  (
    Map<NftBlockchains, List<NftToken>?>,
    Map<NftBlockchains, int?>
  ) _recalculateNftsForChain(List<NftToken> newNftList, NftBlockchains chain) {
    final Map<NftBlockchains, int?> nftCount = {...state.nftCount};
    final Map<NftBlockchains, List<NftToken>?> nfts = {...state.nfts};
    nfts[chain] = newNftList;
    nftCount[chain] = newNftList.length;

    return (nfts, nftCount);
  }

  Map<NftBlockchains, bool> _addUpdatingChains(NftBlockchains chain) {
    final Map<NftBlockchains, bool> updatingChains = {...state.updatingChains};
    updatingChains[chain] = true;
    return updatingChains;
  }

  Map<NftBlockchains, bool> _removeUpdatingChains(NftBlockchains chain) {
    final Map<NftBlockchains, bool> updatingChains = {...state.updatingChains};
    updatingChains[chain] = false;
    return updatingChains;
  }

  @override
  Future<void> close() {
    _authorizationSubscription.cancel();
    _stopUpdate();
    return super.close();
  }
}
