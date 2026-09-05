part of 'nft_main_bloc.dart';

abstract class NftMainEvent {
  const NftMainEvent();
}

class NftMainChainUpdateRequested extends NftMainEvent {
  const NftMainChainUpdateRequested();
}

class NftMainUpdateNftsStopped extends NftMainEvent {
  const NftMainUpdateNftsStopped();
}

class NftMainUpdateNftsStarted extends NftMainEvent {
  const NftMainUpdateNftsStarted();
}

class NftMainResetRequested extends NftMainEvent {
  const NftMainResetRequested();
}

class NftMainTabChanged extends NftMainEvent {
  const NftMainTabChanged(this.chain);
  final NftBlockchains chain;
}

/// Asks the bloc to enable [chain]'s parent coin so its NFTs become fetchable.
///
/// Raised by a tap on an inactive tab and by the explicit retry button - never
/// by the periodic refresh, which must not activate anything.
class NftMainChainActivationRequested extends NftMainEvent {
  const NftMainChainActivationRequested(this.chain);
  final NftBlockchains chain;
}

class NftMainChainNftsRefreshed extends NftMainEvent {
  const NftMainChainNftsRefreshed(this.chain);
  final NftBlockchains chain;
}
