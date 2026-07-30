import 'package:equatable/equatable.dart';
import 'package:komodo_defi_rpc_methods/komodo_defi_rpc_methods.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/gasless/tron_gasless_receive_reason.dart';

enum FormStatus { initial, submitting, success, failure }

enum GaslessReceiveStatus {
  initial,
  checking,
  ready,
  stale,
  temporarilyUnavailable,
  disabled,
  unsupported,
  securityMismatch,
}

class CoinAddressesState extends Equatable {
  final FormStatus status;
  final FormStatus createAddressStatus;
  final String? errorMessage;
  final List<PubkeyInfo> addresses;
  final bool hideZeroBalance;
  final Set<CantCreateNewAddressReason>? cantCreateNewAddressReasons;
  final NewAddressState? newAddressState;
  final GaslessReceiveStatus gaslessReceiveStatus;
  final GaslessReceiveReasonCode? gaslessReceiveReason;
  final String? verifiedGasfreeAddress;
  final String? gaslessReceiveWalletPubkeyHash;
  final GaslessAccountStatusResponse? gaslessAccountStatus;
  final DateTime? gaslessAccountStatusObservedAt;

  const CoinAddressesState({
    this.status = FormStatus.initial,
    this.createAddressStatus = FormStatus.initial,
    this.errorMessage,
    this.addresses = const [],
    this.hideZeroBalance = false,
    this.cantCreateNewAddressReasons,
    this.newAddressState,
    this.gaslessReceiveStatus = GaslessReceiveStatus.initial,
    this.gaslessReceiveReason,
    this.verifiedGasfreeAddress,
    this.gaslessReceiveWalletPubkeyHash,
    this.gaslessAccountStatus,
    this.gaslessAccountStatusObservedAt,
  });

  CoinAddressesState copyWith({
    FormStatus Function()? status,
    FormStatus Function()? createAddressStatus,
    String? Function()? errorMessage,
    List<PubkeyInfo> Function()? addresses,
    bool Function()? hideZeroBalance,
    Set<CantCreateNewAddressReason>? Function()? cantCreateNewAddressReasons,
    NewAddressState? Function()? newAddressState,
    GaslessReceiveStatus Function()? gaslessReceiveStatus,
    GaslessReceiveReasonCode? Function()? gaslessReceiveReason,
    String? Function()? verifiedGasfreeAddress,
    String? Function()? gaslessReceiveWalletPubkeyHash,
    GaslessAccountStatusResponse? Function()? gaslessAccountStatus,
    DateTime? Function()? gaslessAccountStatusObservedAt,
  }) {
    return CoinAddressesState(
      status: status == null ? this.status : status(),
      createAddressStatus: createAddressStatus == null
          ? this.createAddressStatus
          : createAddressStatus(),
      errorMessage: errorMessage == null ? this.errorMessage : errorMessage(),
      addresses: addresses == null ? this.addresses : addresses(),
      hideZeroBalance: hideZeroBalance == null
          ? this.hideZeroBalance
          : hideZeroBalance(),
      cantCreateNewAddressReasons: cantCreateNewAddressReasons == null
          ? this.cantCreateNewAddressReasons
          : cantCreateNewAddressReasons(),
      newAddressState: newAddressState == null
          ? this.newAddressState
          : newAddressState(),
      gaslessReceiveStatus: gaslessReceiveStatus == null
          ? this.gaslessReceiveStatus
          : gaslessReceiveStatus(),
      gaslessReceiveReason: gaslessReceiveReason == null
          ? this.gaslessReceiveReason
          : gaslessReceiveReason(),
      verifiedGasfreeAddress: verifiedGasfreeAddress == null
          ? this.verifiedGasfreeAddress
          : verifiedGasfreeAddress(),
      gaslessReceiveWalletPubkeyHash: gaslessReceiveWalletPubkeyHash == null
          ? this.gaslessReceiveWalletPubkeyHash
          : gaslessReceiveWalletPubkeyHash(),
      gaslessAccountStatus: gaslessAccountStatus == null
          ? this.gaslessAccountStatus
          : gaslessAccountStatus(),
      gaslessAccountStatusObservedAt: gaslessAccountStatusObservedAt == null
          ? this.gaslessAccountStatusObservedAt
          : gaslessAccountStatusObservedAt(),
    );
  }

  CoinAddressesState resetWith({
    FormStatus Function()? status,
    FormStatus Function()? createAddressStatus,
    String? Function()? errorMessage,
    List<PubkeyInfo> Function()? addresses,
    bool Function()? hideZeroBalance,
    Set<CantCreateNewAddressReason>? Function()? cantCreateNewAddressReasons,
    NewAddressState? Function()? newAddressState,
    GaslessReceiveStatus Function()? gaslessReceiveStatus,
    GaslessReceiveReasonCode? Function()? gaslessReceiveReason,
    String? Function()? verifiedGasfreeAddress,
    String? Function()? gaslessReceiveWalletPubkeyHash,
    GaslessAccountStatusResponse? Function()? gaslessAccountStatus,
    DateTime? Function()? gaslessAccountStatusObservedAt,
  }) {
    return CoinAddressesState(
      status: status == null ? FormStatus.initial : status(),
      createAddressStatus: createAddressStatus == null
          ? FormStatus.initial
          : createAddressStatus(),
      errorMessage: errorMessage == null ? null : errorMessage(),
      addresses: addresses == null ? [] : addresses(),
      hideZeroBalance: hideZeroBalance == null ? false : hideZeroBalance(),
      cantCreateNewAddressReasons: cantCreateNewAddressReasons == null
          ? null
          : cantCreateNewAddressReasons(),
      newAddressState: newAddressState == null ? null : newAddressState(),
      gaslessReceiveStatus: gaslessReceiveStatus == null
          ? GaslessReceiveStatus.initial
          : gaslessReceiveStatus(),
      gaslessReceiveReason: gaslessReceiveReason == null
          ? null
          : gaslessReceiveReason(),
      verifiedGasfreeAddress: verifiedGasfreeAddress == null
          ? null
          : verifiedGasfreeAddress(),
      gaslessReceiveWalletPubkeyHash: gaslessReceiveWalletPubkeyHash == null
          ? null
          : gaslessReceiveWalletPubkeyHash(),
      gaslessAccountStatus: gaslessAccountStatus == null
          ? null
          : gaslessAccountStatus(),
      gaslessAccountStatusObservedAt: gaslessAccountStatusObservedAt == null
          ? null
          : gaslessAccountStatusObservedAt(),
    );
  }

  @override
  List<Object?> get props => [
    status,
    createAddressStatus,
    errorMessage,
    addresses,
    hideZeroBalance,
    cantCreateNewAddressReasons,
    newAddressState,
    gaslessReceiveStatus,
    gaslessReceiveReason,
    verifiedGasfreeAddress,
    gaslessReceiveWalletPubkeyHash,
    gaslessAccountStatus,
    gaslessAccountStatusObservedAt,
  ];
}
