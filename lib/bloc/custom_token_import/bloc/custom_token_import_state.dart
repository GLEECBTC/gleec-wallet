import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';

enum FormStatus { initial, submitting, success, failure }

class CustomTokenImportState extends Equatable {
  const CustomTokenImportState({
    required this.formStatus,
    required this.importStatus,
    required this.network,
    required this.address,
    required this.formErrorMessage,
    required this.importErrorMessage,
    required this.coin,
    required this.coinBalance,
    required this.coinBalanceUsd,
    required this.supportedNetworks,
  });

  CustomTokenImportState.defaults({
    this.network = CoinSubClass.erc20,
    this.address = '',
    this.formStatus = FormStatus.initial,
    this.importStatus = FormStatus.initial,
    this.formErrorMessage = '',
    this.importErrorMessage = '',
    this.coin,
    this.supportedNetworks = const [],
  }) : coinBalance = Decimal.zero,
       coinBalanceUsd = Decimal.zero;

  final FormStatus formStatus;
  final FormStatus importStatus;
  final CoinSubClass network;
  final String address;
  final String formErrorMessage;
  final String importErrorMessage;
  final Asset? coin;
  final Decimal coinBalance;
  final Decimal coinBalanceUsd;
  final Iterable<CoinSubClass> supportedNetworks;

  CustomTokenImportState copyWith({
    FormStatus? formStatus,
    FormStatus? importStatus,
    CoinSubClass? network,
    String? address,
    String? formErrorMessage,
    String? importErrorMessage,
    Asset? Function()? tokenData,
    Decimal? tokenBalance,
    Decimal? tokenBalanceUsd,
    Iterable<CoinSubClass>? supportedNetworks,
  }) {
    return CustomTokenImportState(
      formStatus: formStatus ?? this.formStatus,
      importStatus: importStatus ?? this.importStatus,
      network: network ?? this.network,
      address: address ?? this.address,
      formErrorMessage: formErrorMessage ?? this.formErrorMessage,
      importErrorMessage: importErrorMessage ?? this.importErrorMessage,
      coin: tokenData?.call() ?? coin,
      supportedNetworks: supportedNetworks ?? this.supportedNetworks,
      coinBalance: tokenBalance ?? coinBalance,
      coinBalanceUsd: tokenBalanceUsd ?? coinBalanceUsd,
    );
  }

  @override
  List<Object?> get props => [
    formStatus,
    importStatus,
    network,
    address,
    formErrorMessage,
    importErrorMessage,
    coin,
    coinBalance,
    supportedNetworks,
  ];
}
