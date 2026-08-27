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

    test('an unresolved chain never becomes a tab', () async {
      repo.activatedChains = [NftBlockchains.eth];
      repo.unresolvedChains = [NftBlockchains.bsc];

      final state = await runUpdate();

      // Intent may hold the spinner, but only live activation makes a tab.
      expect(state.sortedChains, [NftBlockchains.eth]);
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

    test(
      'a fetch failure surfaces as an error, not an empty chain list',
      () async {
        repo.activatedChains = [NftBlockchains.eth];
        repo.errorToThrow = ApiError(message: 'boom');

        final state = await runUpdate();

        expect(state.error, isNotNull);
      },
    );
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
  List<NftBlockchains> activatedChains = [];
  List<NftBlockchains> unresolvedChains = [];
  List<NftToken> nftsToReturn = [];
  Object? errorToThrow;

  @override
  Future<NftChainActivation> resolveChains(List<NftBlockchains> chains) async =>
      NftChainActivation(
        activated: chains.where(activatedChains.contains).toList(),
        unresolved: chains.where(unresolvedChains.contains).toList(),
      );

  @override
  Future<List<NftBlockchains>> getActivatedChains(
    List<NftBlockchains> chains,
  ) async => chains.where(activatedChains.contains).toList();

  @override
  Future<List<NftToken>> getNfts(List<NftBlockchains> chains) async {
    if (errorToThrow != null) throw errorToThrow!;
    return nftsToReturn;
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
