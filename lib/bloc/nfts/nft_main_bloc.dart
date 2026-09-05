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
  NftMainBloc({required NftsRepo repo, required KomodoDefiSdk sdk})
    : _repo = repo,
      _sdk = sdk,
      super(NftMainState.initial()) {
    on<NftMainChainUpdateRequested>(
      _onChainNftsUpdateRequested,
      transformer: restartable(),
    );
    on<NftMainTabChanged>(_onTabChanged);
    // concurrent(), not restartable(): a cancelled bloc Emitter silently drops
    // emits, so a restarted activation would never write its terminal status
    // and the tab would spin forever. Two chains must also come up at once.
    on<NftMainChainActivationRequested>(
      _onChainActivationRequested,
      transformer: concurrent(),
    );
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

    // Without this the chain list only recomputed on login, on page entry, and
    // on the 60s timer, so enabling ETH from the wallet page left the NFT page
    // insisting no chain was enabled.
    _activationSubscription = _sdk
        .watchActivationStates()
        .map(_parentActivationKey)
        .distinct()
        .skip(1)
        .listen((_) => add(const NftMainChainUpdateRequested()));
  }

  static final Set<String> _nftParentTickers = NftBlockchains.values
      .map((chain) => chain.coinAbbr())
      .toSet();

  /// Collapses a whole-map snapshot to just the NFT parent chains and their
  /// status. `watchActivationStates` emits the ENTIRE map on every state change
  /// of every asset, so without this projection the login fan-out would fire
  /// hundreds of full NFT refetches. Status is part of the key so
  /// activating->failed also wakes us: that is what releases the loading hold.
  static String _parentActivationKey(
    Map<AssetId, AssetActivationState> states,
  ) {
    final rows =
        states.entries
            .where((e) => _nftParentTickers.contains(e.key.id))
            .map((e) => '${e.key.id}:${e.value.status.name}')
            .toList()
          ..sort();
    return rows.join(',');
  }

  final NftsRepo _repo;
  final KomodoDefiSdk _sdk;
  late StreamSubscription<KdfUser?> _authorizationSubscription;
  late final StreamSubscription<String> _activationSubscription;
  Timer? _updateTimer;
  final _log = Logger('NftMainBloc');

  /// The session bringing each chain up. An old request must not release a
  /// claim made by a new wallet after reset.
  final Map<NftBlockchains, int> _activationsInFlight = {};

  /// Bumped on reset, and re-checked by every post-await emit, so an activation
  /// landing after logout cannot write `active` onto a freshly reset state.
  /// `emit.isDone` will not do: a concurrent() emitter is not done just because
  /// the state was reset underneath it.
  int _session = 0;

  Future<void> _onTabChanged(
    NftMainTabChanged event,
    Emitter<NftMainState> emit,
  ) async {
    emit(state.copyWith(selectedChain: () => event.chain));
    if (!await _sdk.auth.isSignedIn() || !state.isInitialized) {
      _log.warning(
        'User is not signed in or state is not initialized. Cannot change NFT tab.',
      );
      return;
    }

    // A chain the user has never enabled has nothing to fetch: `getNfts`
    // filters it out and returns []. The tap IS the request to enable it.
    switch (state.statusOf(event.chain)) {
      case NftChainStatus.inactive:
        add(NftMainChainActivationRequested(event.chain));
        return;
      case NftChainStatus.activating:
        return;
      case NftChainStatus.failed:
        // Selecting a tab is navigation; retrying is a separate, labelled
        // decision, which the pane offers.
        return;
      case NftChainStatus.active:
        break;
    }

    try {
      _log.info('Changing NFT tab to ${event.chain}');
      final List<NftToken> nftList = await _repo.getNfts([event.chain]);

      final (newNftS, newNftCount) = _recalculateNftsForChain(
        nftList,
        event.chain,
      );
      emit(
        state.copyWith(
          nfts: () => newNftS,
          nftCount: () => newNftCount,
          chainErrors: () => _withoutChainError(event.chain),
        ),
      );
      _log.info('Found ${nftList.length} NFTs for chain ${event.chain}');
    } on BaseError catch (e) {
      _log.warning('Error changing NFT tab to ${event.chain}: ${e.message}');
      emit(state.copyWith(chainErrors: () => _withChainError(event.chain, e)));
    } catch (e, s) {
      _log.severe('Unexpected error changing NFT tab', e, s);
      emit(
        state.copyWith(
          chainErrors: () =>
              _withChainError(event.chain, TextError(error: e.toString())),
        ),
      );
    }
  }

  Future<void> _onChainActivationRequested(
    NftMainChainActivationRequested event,
    Emitter<NftMainState> emit,
  ) async {
    final chain = event.chain;
    if (!state.availableChains.contains(chain)) {
      _log.warning('Ignoring activation of unsupported NFT chain $chain');
      return;
    }
    if (state.statusOf(chain) == NftChainStatus.active) return;
    // Claimed before the first await, so a double tap cannot start two
    // activations even though the second event is handled concurrently.
    if (_activationsInFlight.containsKey(chain)) return;
    final session = _session;
    _activationsInFlight[chain] = session;
    try {
      if (!await _sdk.auth.isSignedIn()) return;
      if (_session != session || emit.isDone) return;

      emit(
        state.copyWith(
          chainStatus: () => _withStatus(chain, NftChainStatus.activating),
          chainErrors: () => _withoutChainError(chain),
        ),
      );

      _log.info('Activating ${chain.coinAbbr()} for the NFT page');
      await _repo.activateChain(chain);
      if (_session != session || emit.isDone) return;

      // "No exception" is not proof: activateAssetsSync returns silently when
      // no wallet is signed in. Ask KDF whether the chain actually came up.
      final activated = (await _repo.resolveChains([
        chain,
      ])).activated.contains(chain);
      if (_session != session || emit.isDone) return;

      if (activated) {
        emit(
          state.copyWith(
            chainStatus: () => _withStatus(chain, NftChainStatus.active),
          ),
        );
        add(const NftMainChainUpdateRequested());
      } else {
        _log.warning('KDF did not report ${chain.coinAbbr()} as enabled');
        emit(
          _failChain(
            chain,
            TextError(
              error: 'KDF did not report ${chain.coinAbbr()} as enabled',
            ),
          ),
        );
      }
    } on BaseError catch (e) {
      _log.warning('Failed to enable NFT chain $chain: ${e.message}');
      if (_session != session || emit.isDone) return;
      emit(_failChain(chain, e));
    } catch (e, s) {
      _log.severe('Unexpected error enabling NFT chain $chain', e, s);
      if (_session != session || emit.isDone) return;
      emit(_failChain(chain, TextError(error: e.toString())));
    } finally {
      if (_activationsInFlight[chain] == session) {
        _activationsInFlight.remove(chain);
      }
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

    // Sampled WITH the chain list rather than after the fetch: an activation
    // that resolves while the fetch runs is re-dispatched by the activation
    // subscription anyway, and sampling late would flash the placeholder.
    var hold = false;
    try {
      _log.info('Updating all NFT chains');

      final activation = await _repo.resolveChains(NftBlockchains.values);
      final List<NftBlockchains> activatedChains = activation.activated;
      hold = activatedChains.isEmpty && activation.unresolved.isNotEmpty;

      final results = await _fetchPerChain(activatedChains);
      final nfts = _groupByChain(results);
      // A chain whose fetch failed must not claim "0 items".
      final countable = [
        for (final entry in results.entries)
          if (entry.value.$2 == null) entry.key,
      ];
      final (counts, sortedChains) = _calculateNftCount(nfts, countable);

      emit(
        state.copyWith(
          nftCount: () => counts,
          nfts: () => nfts,
          sortedChains: () => sortedChains,
          availableChains: () => activation.supported,
          chainStatus: () => _mergeChainStatuses(activation),
          chainErrors: () => _mergeChainErrors(activation, results),
          selectedChain: _nextSelection(activation.supported, sortedChains),
          isInitialized: () => state.isInitialized || !hold,
          error: () => null,
        ),
      );

      final totalNfts = counts.values.fold(0, (sum, count) => sum + count);
      _log.info(
        'Updated all NFT chains, found $totalNfts NFTs across ${sortedChains.length} chains',
      );
    } on BaseError catch (e) {
      hold = false;
      _log.warning('Error updating NFT chains: ${e.message}');
      emit(state.copyWith(error: () => e));
    } catch (e, s) {
      hold = false;
      _log.severe('Unexpected error updating NFT chains', e, s);
      emit(state.copyWith(error: () => TextError(error: e.toString())));
    } finally {
      emit(state.copyWith(isInitialized: () => state.isInitialized || !hold));
    }
  }

  void _onReset(NftMainResetRequested event, Emitter<NftMainState> emit) {
    _log.info('Resetting NFT state');
    _session++;
    _activationsInFlight.clear();
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

      final (newNftS, newNftCount) = _recalculateNftsForChain(
        nftList,
        event.chain,
      );
      emit(
        state.copyWith(
          nfts: () => newNftS,
          nftCount: () => newNftCount,
          chainErrors: () => _withoutChainError(event.chain),
        ),
      );
      _log.info('Refreshed ${nftList.length} NFTs for chain ${event.chain}');
    } on BaseError catch (e) {
      _log.warning(
        'Error refreshing NFTs for chain ${event.chain}: ${e.message}',
      );
      emit(state.copyWith(chainErrors: () => _withChainError(event.chain, e)));
    } catch (e, s) {
      _log.severe('Unexpected error refreshing NFTs', e, s);
      emit(
        state.copyWith(
          chainErrors: () =>
              _withChainError(event.chain, TextError(error: e.toString())),
        ),
      );
    } finally {
      final updatingChains = _removeUpdatingChains(event.chain);
      emit(state.copyWith(updatingChains: () => updatingChains));
    }
  }

  void _onStopUpdate(
    NftMainUpdateNftsStopped event,
    Emitter<NftMainState> emit,
  ) {
    _log.info('Stopping NFT update timer');
    _stopUpdate();
  }

  void _onStartUpdate(
    NftMainUpdateNftsStarted event,
    Emitter<NftMainState> emit,
  ) {
    _log.info('Starting NFT update timer (1 minute interval)');
    _stopUpdate();
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      add(const NftMainChainUpdateRequested());
    });
  }

  /// Fetches each activated chain independently.
  ///
  /// One batched `getNfts` was a single point of failure - `_enableNftAssets`
  /// throws for the whole `NFT_*` batch - so one flaky chain blanked the page.
  Future<Map<NftBlockchains, (List<NftToken>, BaseError?)>> _fetchPerChain(
    List<NftBlockchains> chains,
  ) async {
    final entries = await Future.wait(
      chains.map<
        Future<MapEntry<NftBlockchains, (List<NftToken>, BaseError?)>>
      >((chain) async {
        try {
          await retry<void>(
            () async => _repo.updateNft([chain]),
            maxAttempts: 3,
            backoffStrategy: ExponentialBackoff(
              initialDelay: const Duration(seconds: 1),
            ),
          );
        } catch (e, s) {
          // Non-fatal, as before: `getNfts` still returns what KDF has cached.
          _log.severe('Error updating NFTs for chain $chain', e, s);
        }

        try {
          final tokens = await _repo.getNfts([chain]);
          return MapEntry(chain, (tokens, null));
        } on BaseError catch (e) {
          _log.warning('Error fetching NFTs for chain $chain: ${e.message}');
          return MapEntry(chain, (const <NftToken>[], e));
        } catch (e, s) {
          _log.severe('Unexpected error fetching NFTs for chain $chain', e, s);
          return MapEntry(chain, (
            const <NftToken>[],
            TextError(error: e.toString()),
          ));
        }
      }),
    );
    return Map.fromEntries(entries);
  }

  /// Groups tokens under the chain they report, as the batched fetch did.
  Map<NftBlockchains, List<NftToken>> _groupByChain(
    Map<NftBlockchains, (List<NftToken>, BaseError?)> results,
  ) {
    final nfts = <NftBlockchains, List<NftToken>>{};
    for (final entry in results.entries) {
      if (entry.value.$2 != null) continue;
      for (final token in entry.value.$1) {
        (nfts[token.chain] ??= <NftToken>[]).add(token);
      }
    }
    return nfts;
  }

  Map<NftBlockchains, NftChainStatus> _mergeChainStatuses(
    NftChainActivation activation,
  ) {
    final statuses = <NftBlockchains, NftChainStatus>{};
    for (final chain in activation.supported) {
      if (activation.activated.contains(chain)) {
        statuses[chain] = NftChainStatus.active;
      } else if (_activationsInFlight.containsKey(chain) ||
          activation.unresolved.contains(chain)) {
        // Ours in flight, or someone else's (the login fan-out). Either way
        // the 60s tick must not flip a live spinner back to "not enabled".
        statuses[chain] = NftChainStatus.activating;
      } else if (state.statusOf(chain) == NftChainStatus.failed) {
        // Sticky, so the retry affordance survives a refresh tick. The first
        // branch clears it if the chain comes up some other way.
        statuses[chain] = NftChainStatus.failed;
      } else {
        statuses[chain] = NftChainStatus.inactive;
      }
    }
    return statuses;
  }

  Map<NftBlockchains, BaseError> _mergeChainErrors(
    NftChainActivation activation,
    Map<NftBlockchains, (List<NftToken>, BaseError?)> results,
  ) {
    final errors = <NftBlockchains, BaseError>{};
    for (final chain in activation.supported) {
      final fetchError = results[chain]?.$2;
      if (fetchError != null) {
        errors[chain] = fetchError;
      } else if (!activation.activated.contains(chain)) {
        final previous = state.chainErrors[chain];
        if (previous != null) errors[chain] = previous;
      }
    }
    return errors;
  }

  /// Null leaves the selection alone.
  NftBlockchains Function()? _nextSelection(
    List<NftBlockchains> available,
    List<NftBlockchains> sorted,
  ) {
    if (available.isEmpty) return null;
    if (!state.isInitialized) {
      // First paint prefers a chain that actually holds NFTs.
      return () => sorted.isNotEmpty ? sorted.first : available.first;
    }
    // Afterwards the user's choice stands unless it left the catalogue.
    return available.contains(state.selectedChain)
        ? null
        : () => available.first;
  }

  (Map<NftBlockchains, int>, List<NftBlockchains>) _calculateNftCount(
    Map<NftBlockchains, List<NftToken>> nfts,
    List<NftBlockchains> countableChains,
  ) {
    final Map<NftBlockchains, int> countMap = {};

    // Only a chain that answered a `get_nft_list` earns a count - zero NFTs
    // included. A chain nobody enabled is absent entirely, which is what makes
    // its tab say "not enabled" rather than "0 items".
    // Iterate the enum rather than countableChains so insertion order stays
    // tied to the declaration order NftBlockchains documents as significant.
    for (final NftBlockchains chain in NftBlockchains.values) {
      if (countableChains.contains(chain)) {
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

  (Map<NftBlockchains, List<NftToken>?>, Map<NftBlockchains, int?>)
  _recalculateNftsForChain(List<NftToken> newNftList, NftBlockchains chain) {
    final Map<NftBlockchains, int?> nftCount = {...state.nftCount};
    final Map<NftBlockchains, List<NftToken>?> nfts = {...state.nfts};
    nfts[chain] = newNftList;
    nftCount[chain] = newNftList.length;

    return (nfts, nftCount);
  }

  Map<NftBlockchains, NftChainStatus> _withStatus(
    NftBlockchains chain,
    NftChainStatus status,
  ) => {...state.chainStatus, chain: status};

  Map<NftBlockchains, BaseError> _withChainError(
    NftBlockchains chain,
    BaseError error,
  ) => {...state.chainErrors, chain: error};

  Map<NftBlockchains, BaseError> _withoutChainError(NftBlockchains chain) =>
      {...state.chainErrors}..remove(chain);

  /// A per-chain activation failure never touches the page-level error: that
  /// would swap the whole page for NftMainFailure and hide the tabs that work.
  NftMainState _failChain(NftBlockchains chain, BaseError error) =>
      state.copyWith(
        chainStatus: () => _withStatus(chain, NftChainStatus.failed),
        chainErrors: () => _withChainError(chain, error),
      );

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
    _activationSubscription.cancel();
    _stopUpdate();
    return super.close();
  }
}
