part of 'nft_main_bloc.dart';

/// Where a chain stands for this wallet. `activating` covers both a tap the
/// user just made and a chain the wallet intends that KDF has not brought up:
/// indistinguishable to the user.
enum NftChainStatus { inactive, activating, active, failed }

class NftMainState extends Equatable {
  const NftMainState({
    required this.nfts,
    required this.selectedChain,
    required this.nftCount,
    required this.sortedChains,
    required this.availableChains,
    required this.chainStatus,
    required this.chainErrors,
    required this.isInitialized,
    required this.updatingChains,
    this.error,
  });

  factory NftMainState.initial() => const NftMainState(
    nfts: {},
    isInitialized: false,
    updatingChains: {},
    selectedChain: NftBlockchains.eth,
    nftCount: {},
    sortedChains: [],
    availableChains: [],
    chainStatus: {},
    chainErrors: {},
  );

  final Map<NftBlockchains, List<NftToken>?> nfts;
  final NftBlockchains selectedChain;
  final bool isInitialized;
  final Map<NftBlockchains, bool> updatingChains;

  /// NFTs held per chain. Only a chain that answered a `get_nft_list` carries
  /// a count; absence is what makes a tab say "not enabled" rather than
  /// "0 items" about a chain nobody queried.
  final Map<NftBlockchains, int?> nftCount;

  /// Activated chains that answered, ordered by count. Separate from
  /// [availableChains] so the counted set stays exactly the queried set.
  final List<NftBlockchains> sortedChains;

  /// The tab strip, in [NftBlockchains] declaration order: every catalogue
  /// chain allowed in the user's region, activated or not.
  final List<NftBlockchains> availableChains;

  final Map<NftBlockchains, NftChainStatus> chainStatus;

  /// Per-chain failures, scoped so one flaky chain cannot blank the page and
  /// take the working tabs with it.
  final Map<NftBlockchains, BaseError> chainErrors;

  /// Page-level failure: we could not determine the chain list at all.
  /// Per-chain failures live in [chainErrors].
  final BaseError? error;

  NftChainStatus statusOf(NftBlockchains chain) =>
      chainStatus[chain] ?? NftChainStatus.inactive;

  @override
  List<Object?> get props => [
    nfts,
    selectedChain,
    nftCount,
    sortedChains,
    availableChains,
    chainStatus,
    chainErrors,
    error,
    updatingChains,
    isInitialized,
  ];

  NftMainState copyWith({
    Map<NftBlockchains, List<NftToken>?> Function()? nfts,
    NftBlockchains Function()? selectedChain,
    bool Function()? isInitialized,
    Map<NftBlockchains, int?> Function()? nftCount,
    List<NftBlockchains> Function()? sortedChains,
    List<NftBlockchains> Function()? availableChains,
    Map<NftBlockchains, NftChainStatus> Function()? chainStatus,
    Map<NftBlockchains, BaseError> Function()? chainErrors,
    BaseError? Function()? error,
    Map<NftBlockchains, bool> Function()? updatingChains,
  }) {
    return NftMainState(
      nfts: nfts != null ? nfts() : this.nfts,
      selectedChain: selectedChain != null
          ? selectedChain()
          : this.selectedChain,
      nftCount: nftCount != null ? nftCount() : this.nftCount,
      sortedChains: sortedChains != null ? sortedChains() : this.sortedChains,
      availableChains: availableChains != null
          ? availableChains()
          : this.availableChains,
      chainStatus: chainStatus != null ? chainStatus() : this.chainStatus,
      chainErrors: chainErrors != null ? chainErrors() : this.chainErrors,
      isInitialized: isInitialized != null
          ? isInitialized()
          : this.isInitialized,
      error: error != null ? error() : this.error,
      updatingChains: updatingChains != null
          ? updatingChains()
          : this.updatingChains,
    );
  }
}
