import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_capability_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_product_policy.dart';
import 'package:web_dex/features/unified_swap/domain/unified_swap_quote_models.dart';

@immutable
class UnifiedSwapNetworkIdentity extends Equatable {
  const UnifiedSwapNetworkIdentity({
    required this.chainFamily,
    required this.chainId,
  });

  final UnifiedSwapChainFamily chainFamily;
  final String chainId;

  bool matches(UnifiedSwapAssetIdentity asset) =>
      asset.chainFamily == chainFamily && asset.chainId == chainId;

  @override
  List<Object?> get props => [chainFamily, chainId];
}

@immutable
class UnifiedSwapAssetOption extends Equatable {
  const UnifiedSwapAssetOption({
    required this.identity,
    required this.tokenTrust,
  });

  final UnifiedSwapAssetIdentity identity;
  final UnifiedSwapTokenTrust tokenTrust;

  UnifiedSwapNetworkIdentity get network => UnifiedSwapNetworkIdentity(
    chainFamily: identity.chainFamily,
    chainId: identity.chainId,
  );

  @override
  List<Object?> get props => [identity, tokenTrust];
}

@immutable
class UnifiedSwapRoutePair extends Equatable {
  const UnifiedSwapRoutePair({required this.source, required this.destination});

  final UnifiedSwapAssetIdentity source;
  final UnifiedSwapAssetIdentity destination;

  @override
  List<Object?> get props => [source, destination];
}

/// Exact, fail-closed wallet choices derived from the intersection of the
/// active software-key wallet and KDF's current executable capabilities.
@immutable
class UnifiedSwapSelectionInventory extends Equatable {
  UnifiedSwapSelectionInventory({
    required List<UnifiedSwapAssetOption> sources,
    required List<UnifiedSwapAssetOption> destinations,
    required List<UnifiedSwapRoutePair> pairs,
  }) : sources = List.unmodifiable(sources),
       destinations = List.unmodifiable(destinations),
       pairs = List.unmodifiable(pairs) {
    if (_hasDuplicateIdentities(this.sources) ||
        _hasDuplicateIdentities(this.destinations) ||
        this.pairs.toSet().length != this.pairs.length ||
        this.pairs.any(
          (pair) =>
              !this.sources.any(
                (option) => option.identity.sameIdentity(pair.source),
              ) ||
              !this.destinations.any(
                (option) => option.identity.sameIdentity(pair.destination),
              ),
        )) {
      throw ArgumentError(
        'Selection inventory must contain exact unique pairs',
      );
    }
  }

  final List<UnifiedSwapAssetOption> sources;
  final List<UnifiedSwapAssetOption> destinations;
  final List<UnifiedSwapRoutePair> pairs;

  bool get isEmpty => pairs.isEmpty;

  UnifiedSwapAssetOption? sourceOption(UnifiedSwapAssetIdentity identity) =>
      _singleOption(sources, identity);

  UnifiedSwapAssetOption? destinationOption(
    UnifiedSwapAssetIdentity identity,
  ) => _singleOption(destinations, identity);

  bool supportsPair(
    UnifiedSwapAssetIdentity source,
    UnifiedSwapAssetIdentity destination,
  ) => pairs.any(
    (pair) =>
        pair.source.sameIdentity(source) &&
        pair.destination.sameIdentity(destination),
  );

  List<UnifiedSwapAssetOption> destinationsFor(
    UnifiedSwapAssetIdentity source,
  ) => List.unmodifiable(
    destinations.where(
      (destination) => pairs.any(
        (pair) =>
            pair.source.sameIdentity(source) &&
            pair.destination.sameIdentity(destination.identity),
      ),
    ),
  );

  List<UnifiedSwapNetworkIdentity> sourceNetworks() => _networks(sources);

  List<UnifiedSwapNetworkIdentity> destinationNetworksFor(
    UnifiedSwapAssetIdentity source,
  ) => _networks(destinationsFor(source));

  @override
  List<Object?> get props => [sources, destinations, pairs];
}

@immutable
class UnifiedSwapSourceAddressOption extends Equatable {
  UnifiedSwapSourceAddressOption({
    required this.selection,
    required this.address,
    required String balance,
    required this.isActive,
    this.label,
  }) : balance = _canonicalAmount(balance) {
    if (!selection.isExecutable ||
        address.trim() != address ||
        address.isEmpty ||
        (label != null && (label!.trim() != label || label!.isEmpty))) {
      throw ArgumentError('Source address option must be exact and executable');
    }
  }

  final UnifiedSwapSourceSelection selection;
  final String address;
  final String balance;
  final bool isActive;
  final String? label;

  @override
  List<Object?> get props => [selection, address, balance, isActive, label];
}

abstract interface class UnifiedSwapSelectionGateway {
  Future<UnifiedSwapSelectionInventory?> selectionInventory();

  Future<List<UnifiedSwapSourceAddressOption>> sourceAddressOptions(
    UnifiedSwapAssetIdentity source,
  );

  Future<UnifiedSwapIntent?> selectSourceAsset(
    UnifiedSwapIntent current,
    UnifiedSwapAssetIdentity source,
  );

  Future<UnifiedSwapIntent?> selectDestinationAsset(
    UnifiedSwapIntent current,
    UnifiedSwapAssetIdentity destination,
  );

  Future<UnifiedSwapIntent?> selectSourceAddress(
    UnifiedSwapIntent current,
    UnifiedSwapSourceSelection selection,
  );
}

bool _hasDuplicateIdentities(List<UnifiedSwapAssetOption> options) {
  for (var index = 0; index < options.length; index++) {
    for (var other = index + 1; other < options.length; other++) {
      if (options[index].identity.sameIdentity(options[other].identity)) {
        return true;
      }
    }
  }
  return false;
}

UnifiedSwapAssetOption? _singleOption(
  List<UnifiedSwapAssetOption> options,
  UnifiedSwapAssetIdentity identity,
) {
  final matches = options
      .where((option) => option.identity.sameIdentity(identity))
      .toList(growable: false);
  return matches.length == 1 ? matches.single : null;
}

List<UnifiedSwapNetworkIdentity> _networks(
  List<UnifiedSwapAssetOption> options,
) {
  final result = <UnifiedSwapNetworkIdentity>[];
  for (final option in options) {
    if (!result.contains(option.network)) result.add(option.network);
  }
  result.sort((left, right) {
    final family = left.chainFamily.name.compareTo(right.chainFamily.name);
    return family != 0 ? family : left.chainId.compareTo(right.chainId);
  });
  return List.unmodifiable(result);
}

String _canonicalAmount(String value) {
  if (!RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw ArgumentError.value(value, 'balance', 'must be a canonical amount');
  }
  return value;
}
