import 'dart:async';

import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
// `KomodoDefiSdk.auth` is typed as the concrete `KomodoDefiLocalAuth`, which
// the SDK barrel does not re-export, so faking it means importing the package
// directly.
import 'package:komodo_defi_local_auth/komodo_defi_local_auth.dart';
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/bloc/nfts/nft_main_bloc.dart';
import 'package:web_dex/bloc/nfts/nft_main_repo.dart';
import 'package:web_dex/model/nft.dart';
import 'package:web_dex/views/nfts/nft_tabs/nft_tabs.dart';

/// Renders the tab strip the reported bug was about: a fresh wallet showed only
/// "Ethereum" because a chain had to be activated before it could be a tab.
///
/// These assert what the user actually sees, which the bloc tests cannot: that
/// every supported chain is painted, and that a chain nobody has enabled does
/// not claim "0 items".
void testNftTabsWidget() {
  group('NFT tab strip', () {
    late _FakeNftsRepo repo;
    late NftMainBloc bloc;

    setUp(() {
      repo = _FakeNftsRepo()..activatedChains = [NftBlockchains.eth];
      bloc = NftMainBloc(repo: repo, sdk: _FakeSdk(_FakeAuth()));
      addTearDown(bloc.close);
    });

    /// Brings the bloc to its first painted state.
    ///
    /// Runs through [WidgetTester.runAsync] because a testWidgets body executes
    /// under FakeAsync, where awaiting a bloc stream simply never completes.
    Future<void> initialise(WidgetTester tester) async {
      await tester.runAsync(() async {
        bloc.add(const NftMainChainUpdateRequested());
        await bloc.stream.firstWhere((s) => s.isInitialized);
      });
    }

    Future<void> pumpTabs(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: newThemeDark,
          home: BlocProvider<NftMainBloc>.value(
            value: bloc,
            child: Scaffold(body: NftTabs(tabs: bloc.state.availableChains)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('paints every supported chain, not just the enabled one', (
      tester,
    ) async {
      await initialise(tester);
      await pumpTabs(tester);

      expect(find.byKey(const Key('nft-tab-eth')), findsOneWidget);
      expect(find.byKey(const Key('nft-tab-polygon')), findsOneWidget);
      expect(find.byKey(const Key('nft-tab-bsc')), findsOneWidget);
      expect(find.byKey(const Key('nft-tab-avalanche')), findsOneWidget);
      // FTM is absent from the coins config, so Fantom must never be offered.
      expect(find.byKey(const Key('nft-tab-fantom')), findsNothing);
    });

    testWidgets('an un-enabled chain says so instead of claiming 0 items', (
      tester,
    ) async {
      await initialise(tester);
      await pumpTabs(tester);

      // `$chain` interpolates NftBlockchains' overridden toString.
      expect(find.byKey(const Key('ntf-tab-count-ETH')), findsOneWidget);
      expect(find.byKey(const Key('nft-tab-status-Polygon')), findsOneWidget);
      // Why nftCount stays null for a chain that was never queried.
      expect(find.byKey(const Key('ntf-tab-count-Polygon')), findsNothing);
    });

    testWidgets('an enabling chain shows a spinner, not a count', (
      tester,
    ) async {
      await initialise(tester);
      await tester.runAsync(() async {
        repo.activationGate = Completer<void>();
        bloc.add(const NftMainChainActivationRequested(NftBlockchains.polygon));
        await bloc.stream.firstWhere(
          (s) =>
              s.statusOf(NftBlockchains.polygon) == NftChainStatus.activating,
        );
      });

      await pumpTabs(tester);

      expect(
        find.byKey(const Key('nft-tab-activating-Polygon')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ntf-tab-count-Polygon')), findsNothing);
      repo.activationGate!.complete();
    });

    testWidgets('tapping an un-enabled tab asks to enable it', (tester) async {
      await initialise(tester);
      await pumpTabs(tester);

      await tester.tap(find.byKey(const Key('nft-tab-polygon')));
      await tester.pump();
      // The bloc was built in setUp, so its handlers run in the real zone that
      // a FakeAsync pump never advances. runAsync is what lets them finish.
      await tester.runAsync(() async {
        await bloc.stream.firstWhere(
          (s) => s.statusOf(NftBlockchains.polygon) == NftChainStatus.active,
        );
      });
      // Flushes the tab's 300ms ensureVisible animation, which would otherwise
      // leave a pending timer at teardown.
      await tester.pumpAndSettle();

      expect(repo.activateCalls, [NftBlockchains.polygon]);
    });
  });
}

class _FakeNftsRepo implements NftsRepo {
  /// Mirrors the bundled coins config, where FTM is absent.
  List<NftBlockchains> supportedChains = const [
    NftBlockchains.eth,
    NftBlockchains.polygon,
    NftBlockchains.bsc,
    NftBlockchains.avalanche,
  ];
  List<NftBlockchains> activatedChains = [];
  final List<NftBlockchains> activateCalls = [];
  Completer<void>? activationGate;

  @override
  Future<NftChainActivation> resolveChains(List<NftBlockchains> chains) async =>
      NftChainActivation(
        supported: chains.where(supportedChains.contains).toList(),
        activated: chains.where(activatedChains.contains).toList(),
        unresolved: const [],
      );

  @override
  Future<List<NftBlockchains>> getActivatedChains(
    List<NftBlockchains> chains,
  ) async => chains.where(activatedChains.contains).toList();

  @override
  Future<void> activateChain(NftBlockchains chain) async {
    activateCalls.add(chain);
    if (activationGate != null) await activationGate!.future;
    activatedChains = [...activatedChains, chain];
  }

  @override
  Future<List<NftToken>> getNfts(List<NftBlockchains> chains) async => [];

  @override
  Future<void> updateNft(List<NftBlockchains> chains) async {}

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
  _FakeSdk(this.auth);

  @override
  final KomodoDefiLocalAuth auth;

  @override
  Stream<Map<AssetId, AssetActivationState>> watchActivationStates() =>
      const Stream<Map<AssetId, AssetActivationState>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
