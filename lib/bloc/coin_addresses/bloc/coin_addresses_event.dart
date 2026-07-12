import 'package:equatable/equatable.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart' show PubkeyInfo;

abstract class CoinAddressesEvent extends Equatable {
  const CoinAddressesEvent();

  @override
  List<Object?> get props => [];
}

class CoinAddressesAddressCreationSubmitted extends CoinAddressesEvent {
  const CoinAddressesAddressCreationSubmitted();
}

class CoinAddressesStarted extends CoinAddressesEvent {
  const CoinAddressesStarted();
}

class CoinAddressesSubscriptionRequested extends CoinAddressesEvent {
  const CoinAddressesSubscriptionRequested();
}

/// Revalidates the short-lived remote receive permission and authoritative
/// GasFree account status without rebuilding or hiding retained address rows.
class CoinAddressesGaslessReceiveRefreshRequested extends CoinAddressesEvent {
  const CoinAddressesGaslessReceiveRefreshRequested();
}

class CoinAddressesZeroBalanceVisibilityChanged extends CoinAddressesEvent {
  final bool hideZeroBalance;

  const CoinAddressesZeroBalanceVisibilityChanged(this.hideZeroBalance);

  @override
  List<Object?> get props => [hideZeroBalance];
}

/// Emitted when the pubkeys watcher emits an updated set of keys (and balances)
class CoinAddressesPubkeysUpdated extends CoinAddressesEvent {
  final List<PubkeyInfo> addresses;
  const CoinAddressesPubkeysUpdated(this.addresses);

  @override
  List<Object?> get props => [addresses];
}

/// Emitted when the pubkeys watcher reports an error
class CoinAddressesPubkeysSubscriptionFailed extends CoinAddressesEvent {
  final String error;
  const CoinAddressesPubkeysSubscriptionFailed(this.error);

  @override
  List<Object?> get props => [error];
}
