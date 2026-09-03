import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// `KomodoDefiSdk.auth` is typed as the concrete `KomodoDefiLocalAuth`, which
// the SDK barrel does not re-export, so faking it means importing the package
// directly.
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/nfts/nft_main_bloc.dart';
import 'package:web_dex/bloc/nfts/nft_main_repo.dart';
import 'package:web_dex/mm2/mm2_api/rpc/errors.dart';
import 'package:web_dex/model/nft.dart';

/// Regression tests for the "Please enable NFT protocol assets" empty state
/// showing while the chain was already enabled.
///
/// Before the fix, [NftMainBloc] derived `sortedChains` from the NFTs that came
/// back rather than from the chains the wallet has activated, so a wallet with
/// ETH activated and no NFTs was told to enable ETH.
void testNftMainBloc() {
  group('NftMainBloc chain derivation', () {
    late _FakeNftsRepo repo;
    late NftMainBloc bloc;

    setUp(() {
      repo = _FakeNftsRepo();
      bloc = NftMainBloc(repo: repo, sdk: _FakeSdk(_FakeAuth()));
      addTearDown(bloc.close);
    });

    Future<NftMainState> runUpdate() {
      bloc.add(const NftMainChainUpdateRequested());
      return bloc.stream.firstWhere((state) => state.isInitialized);
    }

    test('an activated chain with no NFTs still gets a tab', () async {
      repo.activatedChains = [NftBlockchains.eth];
      repo.nftsToReturn = [];

      final state = await runUpdate();

      expect(state.sortedChains, [NftBlockchains.eth]);
      expect(state.nftCount, {NftBlockchains.eth: 0});
      expect(state.selectedChain, NftBlockchains.eth);
      expect(state.error, isNull);
    });

    test(
      'no activated chain leaves a clean empty state, not a StateError',
      () async {
        repo.activatedChains = [];
        repo.nftsToReturn = [];

        final state = await runUpdate();

        expect(state.sortedChains, isEmpty);
        expect(state.nftCount, isEmpty);
        // `sortedChains.first` used to throw inside copyWith, discarding the
        // whole emit and leaving a bogus TextError behind.
        expect(state.error, isNull);
      },
    );

    test('tabs sort by count, ties fall back to chain order', () async {
      repo.activatedChains = [
        NftBlockchains.eth,
        NftBlockchains.polygon,
        NftBlockchains.bsc,
      ];
      repo.nftsToReturn = [
        _token(NftBlockchains.bsc),
        _token(NftBlockchains.bsc),
      ];

      final state = await runUpdate();

      expect(state.sortedChains, [
        NftBlockchains.bsc,
        NftBlockchains.eth,
        NftBlockchains.polygon,
      ]);
      expect(state.nftCount, {
        NftBlockchains.eth: 0,
        NftBlockchains.polygon: 0,
        NftBlockchains.bsc: 2,
      });
    });

    test('an all-zero wallet keeps a deterministic enum tab order', () async {
      repo.activatedChains = [
        NftBlockchains.bsc,
        NftBlockchains.eth,
        NftBlockchains.polygon,
      ];
      repo.nftsToReturn = [];

      final state = await runUpdate();

      expect(state.sortedChains, [
        NftBlockchains.eth,
        NftBlockchains.polygon,
        NftBlockchains.bsc,
      ]);
    });

    test('a wallet that owns NFTs is unaffected', () async {
      repo.activatedChains = [NftBlockchains.eth];
      repo.nftsToReturn = [_token(NftBlockchains.eth)];

      final state = await runUpdate();

      expect(state.sortedChains, [NftBlockchains.eth]);
      expect(state.nftCount, {NftBlockchains.eth: 1});
      expect(state.nfts[NftBlockchains.eth], hasLength(1));
      expect(state.error, isNull);
    });

    test('activation still pending holds the loading state instead of accusing '
        'the user of having enabled nothing', () async {
      // The wallet asked for ETH but KDF has not reported it active yet.
      repo.activatedChains = [];
      repo.unresolvedChains = [NftBlockchains.eth];

      bloc.add(const NftMainChainUpdateRequested());
      await bloc.stream.firstWhere((s) => s.nfts.isEmpty && s.error == null);

      // isInitialized must stay false so NftMain paints NftMainLoading
      // rather than NftNoChainsEnabled.
      expect(bloc.state.isInitialized, isFalse);
      expect(bloc.state.sortedChains, isEmpty);
    });

    test('an unresolved chain gets a spinner, never a count', () async {
      repo.activatedChains = [NftBlockchains.eth];
      repo.unresolvedChains = [NftBlockchains.bsc];

      final state = await runUpdate();

      // Intent earns a tab now, but only live activation earns a count.
      expect(state.sortedChains, [NftBlockchains.eth]);
      expect(state.nftCount[NftBlockchains.bsc], isNull);
      expect(state.statusOf(NftBlockchains.bsc), NftChainStatus.activating);
      expect(state.isInitialized, isTrue);
    });

    test(
      'nothing pending releases the hold rather than spinning forever',
      () async {
        repo.activatedChains = [];
        repo.unresolvedChains = [];

        final state = await runUpdate();

        expect(state.isInitialized, isTrue);
        expect(state.sortedChains, isEmpty);
        expect(state.error, isNull);
      },
    );

    test('a fetch failure is scoped to its chain, not the page', () async {
      repo.activatedChains = [NftBlockchains.eth];
      repo.errorToThrow = ApiError(message: 'boom');

      final state = await runUpdate();

      expect(state.chainErrors[NftBlockchains.eth], isNotNull);
      // A page-level error swaps the whole gallery for NftMainFailure, hiding
      // the tabs that work.
      expect(state.error, isNull);
      // A chain that failed to answer must not claim "0 items".
      expect(state.nftCount[NftBlockchains.eth], isNull);
    });

    test('every supported chain earns a tab, enabled or not', () async {
      repo.activatedChains = [NftBlockchains.eth];

      final state = await runUpdate();

      // A fresh wallet has only ETH enabled, but all four chains must be
      // reachable.
      expect(state.availableChains, [
        NftBlockchains.eth,
        NftBlockchains.polygon,
        NftBlockchains.bsc,
        NftBlockchains.avalanche,
      ]);
      expect(state.statusOf(NftBlockchains.eth), NftChainStatus.active);
      expect(state.statusOf(NftBlockchains.polygon), NftChainStatus.inactive);
    });

    test('an unsupported chain never earns a tab', () async {
      repo.activatedChains = [NftBlockchains.eth];

      final state = await runUpdate();

      // FTM is absent from the coins config, so Fantom can never resolve.
      expect(state.availableChains, isNot(contains(NftBlockchains.fantom)));
    });

    test('a chain that was never queried carries no count', () async {
      repo.activatedChains = [NftBlockchains.eth];
      repo.nftsToReturn = [];

      final state = await runUpdate();

      // `null` is what makes the tab render "Not enabled". A 0 would claim the
      // user owns nothing on a chain that was never queried.
      expect(state.nftCount[NftBlockchains.polygon], isNull);
      expect(state.nftCount[NftBlockchains.eth], 0);
    });
  });

  group('NftMainBloc chain activation', () {
    late _FakeNftsRepo repo;
    late NftMainBloc bloc;

    setUp(() {
      repo = _FakeNftsRepo()..activatedChains = [NftBlockchains.eth];
      bloc = NftMainBloc(repo: repo, sdk: _FakeSdk(_FakeAuth()));
      addTearDown(bloc.close);
    });

    Future<void> initialise() async {
      bloc.add(const NftMainChainUpdateRequested());
      await bloc.stream.firstWhere((s) => s.isInitialized);
    }

    test('selecting an inactive tab enables that chain', () async {
      await initialise();

      bloc.add(const NftMainTabChanged(NftBlockchains.polygon));
      await bloc.stream.firstWhere(
        (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.active,
      );

      expect(repo.activateCalls, [NftBlockchains.polygon]);
      expect(bloc.state.selectedChain, NftBlockchains.polygon);
    });

    test('the tab spins while the chain comes up', () async {
      await initialise();
      repo.activationGate = Completer<void>();

      bloc.add(const NftMainTabChanged(NftBlockchains.polygon));
      await bloc.stream.firstWhere(
        (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.activating,
      );

      expect(
        bloc.state.statusOf(NftBlockchains.polygon),
        NftChainStatus.activating,
      );
      repo.activationGate!.complete();
    });

    test('a second tap while activating does not activate twice', () async {
      await initialise();
      repo.activationGate = Completer<void>();

      bloc.add(const NftMainTabChanged(NftBlockchains.polygon));
      await bloc.stream.firstWhere(
        (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.activating,
      );
      bloc.add(const NftMainTabChanged(NftBlockchains.polygon));
      bloc.add(const NftMainChainActivationRequested(NftBlockchains.polygon));
      await Future<void>.delayed(Duration.zero);

      expect(repo.activateCalls, [NftBlockchains.polygon]);
      repo.activationGate!.complete();
    });

    test('a refresh tick mid-activation does not reset the tab', () async {
      await initialise();
      repo.activationGate = Completer<void>();

      bloc.add(const NftMainChainActivationRequested(NftBlockchains.polygon));
      await bloc.stream.firstWhere(
        (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.activating,
      );

      // The 60s timer lands while the spinner is up. Recomputing from
      // resolveChains alone would flip it back to "Not enabled". Give the tick
      // something to change, since an identical state is never emitted.
      repo.nftsToReturn = [_token(NftBlockchains.eth)];
      bloc.add(const NftMainChainUpdateRequested());
      await bloc.stream.firstWhere((s) => s.nfts.isNotEmpty);

      expect(
        bloc.state.statusOf(NftBlockchains.polygon),
        NftChainStatus.activating,
      );
      repo.activationGate!.complete();
    });

    test('an activation failure is scoped to its own tab', () async {
      await initialise();
      repo.activationErrorToThrow = ApiError(message: 'network down');

      bloc.add(const NftMainChainActivationRequested(NftBlockchains.polygon));
      await bloc.stream.firstWhere(
        (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.failed,
      );

      expect(bloc.state.chainErrors[NftBlockchains.polygon], isNotNull);
      expect(bloc.state.statusOf(NftBlockchains.eth), NftChainStatus.active);
      // Never the page-level error: that would hide the working ETH tab.
      expect(bloc.state.error, isNull);
      expect(bloc.state.nftCount[NftBlockchains.polygon], isNull);
    });

    test('re-selecting a failed tab does not silently retry', () async {
      await initialise();
      repo.activationErrorToThrow = ApiError(message: 'network down');

      bloc.add(const NftMainChainActivationRequested(NftBlockchains.polygon));
      await bloc.stream.firstWhere(
        (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.failed,
      );

      // Selecting a tab is navigation; retrying a network call is a separate,
      // labelled decision that the panel offers.
      bloc.add(const NftMainTabChanged(NftBlockchains.polygon));
      await Future<void>.delayed(Duration.zero);

      expect(repo.activateCalls, [NftBlockchains.polygon]);
    });

    test('a failed chain enabled elsewhere recovers', () async {
      await initialise();
      repo.activationErrorToThrow = ApiError(message: 'network down');
      bloc.add(const NftMainChainActivationRequested(NftBlockchains.polygon));
      await bloc.stream.firstWhere(
        (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.failed,
      );

      // The user gives up and enables MATIC from the coins manager instead.
      repo.activatedChains = [NftBlockchains.eth, NftBlockchains.polygon];
      bloc.add(const NftMainChainUpdateRequested());
      await bloc.stream.firstWhere(
        (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.active,
      );

      expect(bloc.state.chainErrors[NftBlockchains.polygon], isNull);
    });

    test('logging out mid-activation discards the result', () async {
      await initialise();
      repo.activationGate = Completer<void>();

      bloc.add(const NftMainChainActivationRequested(NftBlockchains.polygon));
      await bloc.stream.firstWhere(
        (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.activating,
      );

      bloc.add(const NftMainResetRequested());
      await bloc.stream.firstWhere((s) => s.availableChains.isEmpty);
      repo.activationGate!.complete();
      await Future<void>.delayed(Duration.zero);

      // Without the session epoch the post-await emit writes `active` back
      // onto a freshly reset state.
      expect(bloc.state, NftMainState.initial());
    });
  });

  group('NftMainBloc reactivity', () {
    test('an activation-state change recomputes the chain list', () async {
      final repo = _FakeNftsRepo()..activatedChains = [];
      final controller =
          StreamController<Map<AssetId, AssetActivationState>>.broadcast();
      addTearDown(controller.close);

      final bloc = NftMainBloc(
        repo: repo,
        sdk: _FakeSdk(_FakeAuth(), activationStates: controller.stream),
      );
      addTearDown(bloc.close);

      bloc.add(const NftMainChainUpdateRequested());
      await bloc.stream.firstWhere((s) => s.isInitialized);
      expect(bloc.state.sortedChains, isEmpty);

      // ETH comes up elsewhere in the app. Before this subscription existed the
      // page stayed empty until the 60s timer.
      repo.activatedChains = [NftBlockchains.eth];
      controller.add({});
      controller.add({_ethId: _activeState});

      await bloc.stream.firstWhere((s) => s.sortedChains.isNotEmpty);
      expect(bloc.state.sortedChains, [NftBlockchains.eth]);
    });
  });
}

final _ethId = AssetId(
  id: 'ETH',
  name: 'Ethereum',
  symbol: AssetSymbol(assetConfigId: 'ETH'),
  chainId: AssetChainId(chainId: 1),
  derivationPath: "m/44'/60'/0'/0",
  subClass: CoinSubClass.erc20,
);

final _activeState = AssetActivationState.active(_ethId);

NftToken _token(NftBlockchains chain) => NftToken(
  chain: chain,
  tokenAddress: '0xabc',
  tokenId: '1',
  amount: '1',
  ownerOf: '0xdef',
  tokenHash: 'hash',
  blockNumber: 1,
  blockNumberMinted: 1,
  contractType: NftContractType.erc721,
  collectionName: 'collection',
  symbol: 'SYM',
  metaData: null,
  lastTokenUriSync: null,
  lastMetadataSync: null,
  minterAddress: null,
  possibleSpam: false,
  uriMeta: const NftUriMeta(
    tokenName: 'token',
    description: null,
    image: null,
    attributes: null,
    animationUrl: null,
    imageUrl: null,
    imageDetails: null,
    externalUrl: null,
  ),
  tokenUri: null,
);

class _FakeNftsRepo implements NftsRepo {
  /// Mirrors the bundled coins config, where FTM is absent: the catalogue and
  /// geo filtering are the repo's job and are pinned in nft_main_repo_test.
  List<NftBlockchains> supportedChains = const [
    NftBlockchains.eth,
    NftBlockchains.polygon,
    NftBlockchains.bsc,
    NftBlockchains.avalanche,
  ];
  List<NftBlockchains> activatedChains = [];
  List<NftBlockchains> unresolvedChains = [];
  List<NftToken> nftsToReturn = [];
  Object? errorToThrow;

  /// Every activateChain call, in order. Assert the length for dedupe tests.
  final List<NftBlockchains> activateCalls = [];

  /// Non-null holds activateChain open, which is the only way to observe the
  /// `activating` state.
  Completer<void>? activationGate;
  Object? activationErrorToThrow;

  @override
  Future<NftChainActivation> resolveChains(List<NftBlockchains> chains) async =>
      NftChainActivation(
        supported: chains.where(supportedChains.contains).toList(),
        activated: chains.where(activatedChains.contains).toList(),
        unresolved: chains.where(unresolvedChains.contains).toList(),
      );

  @override
  Future<void> activateChain(NftBlockchains chain) async {
    activateCalls.add(chain);
    if (activationGate != null) await activationGate!.future;
    if (activationErrorToThrow != null) throw activationErrorToThrow!;
    // KDF now agrees, so the bloc's verification read succeeds.
    activatedChains = [...activatedChains, chain];
  }

  @override
  Future<List<NftBlockchains>> getActivatedChains(
    List<NftBlockchains> chains,
  ) async => chains.where(activatedChains.contains).toList();

  @override
  Future<List<NftToken>> getNfts(List<NftBlockchains> chains) async {
    if (errorToThrow != null) throw errorToThrow!;
    // The real repo passes `chains` to get_nft_list, so a response only ever
    // carries the chains that were asked for. Returning everything regardless
    // let a per-chain fetch count the same token once per chain.
    return nftsToReturn.where((nft) => chains.contains(nft.chain)).toList();
  }

  @override
  Future<void> updateNft(List<NftBlockchains> chains) async {
    if (errorToThrow != null) throw errorToThrow!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuth implements KomodoDefiLocalAuth {
  @override
  Future<bool> isSignedIn() async => true;

  // An empty stream keeps the bloc's constructor subscription from dispatching
  // a second update and making these tests order-dependent.
  @override
  Stream<KdfUser?> watchCurrentUser() => const Stream<KdfUser?>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdk implements KomodoDefiSdk {
  _FakeSdk(
    this.auth, {
    Stream<Map<AssetId, AssetActivationState>>? activationStates,
  }) : _activationStates =
           activationStates ??
           const Stream<Map<AssetId, AssetActivationState>>.empty();

  @override
  final KomodoDefiLocalAuth auth;

  final Stream<Map<AssetId, AssetActivationState>> _activationStates;

  @override
  Stream<Map<AssetId, AssetActivationState>> watchActivationStates() =>
      _activationStates;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
