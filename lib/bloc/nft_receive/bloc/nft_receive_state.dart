part of 'nft_receive_bloc.dart';

abstract class NftReceiveState extends Equatable {
  const NftReceiveState();

  @override
  List<Object> get props => [];
}

class NftReceiveInitial extends NftReceiveState {}

class NftReceiveLoadSuccess extends NftReceiveState {
  const NftReceiveLoadSuccess({
    required this.asset,
    required this.pubkeys,
    this.selectedAddress,
  });

  final Asset asset;
  final AssetPubkeys pubkeys;
  final PubkeyInfo? selectedAddress;

  NftReceiveLoadSuccess copyWith({
    Asset? asset,
    AssetPubkeys? pubkeys,
    PubkeyInfo? selectedAddress,
  }) {
    return NftReceiveLoadSuccess(
      asset: asset ?? this.asset,
      pubkeys: pubkeys ?? this.pubkeys,
      selectedAddress: selectedAddress ?? this.selectedAddress,
    );
  }

  @override
  List<Object> get props => [
    asset,
    pubkeys,
    if (selectedAddress != null) selectedAddress!,
  ];
}

class NftReceiveLoadFailure extends NftReceiveState {
  const NftReceiveLoadFailure({this.message});

  final String? message;
}
