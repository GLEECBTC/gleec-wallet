import 'package:equatable/equatable.dart' show Equatable;
import 'package:komodo_defi_sdk/komodo_defi_sdk.dart';
import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/app_config/app_config.dart';
import 'package:web_dex/bloc/coins_bloc/asset_coin_extension.dart';
import 'package:web_dex/model/cex_price.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/model/coin_utils.dart';

class Coin extends Equatable {
  Coin({
    required this.type,
    required this.abbr,
    required this.id,
    required this.name,
    required this.explorerUrl,
    required this.explorerTxUrl,
    required this.explorerAddressUrl,
    required this.protocolType,
    required this.protocolData,
    required this.isTestCoin,
    required this.logoImageUrl,
    required this.coingeckoId,
    required this.fallbackSwapContract,
    required this.priority,
    required this.state,
    this.decimals = 8,
    this.parentCoin,
    this.derivationPath,
    this.usdPrice, // Will be deprecated in favor of SDK price manager
    this.coinpaprikaId,
    this.activeByDefault = false,
    this.isCustomCoin = false,
    required String? swapContractAddress,
    required bool walletOnly,
    required this.mode,
  }) : _swapContractAddress = swapContractAddress,
       _walletOnly = walletOnly;

  final String abbr;
  final String name;
  final AssetId id;
  final String? logoImageUrl;
  final String? coingeckoId;
  final String? coinpaprikaId;
  final CoinType type;
  final bool activeByDefault;
  final String protocolType;
  final ProtocolData? protocolData;
  final String explorerUrl;
  final String explorerTxUrl;
  final String explorerAddressUrl;
  final String? derivationPath;
  final int decimals;

  @Deprecated(
    'Use sdk.prices.fiatPrice(id) instead. This value is not updated after initial load and may be inaccurate.',
  )
  CexPrice? usdPrice;

  final bool isTestCoin;
  bool isCustomCoin;

  @Deprecated(
    '$_urgentDeprecationNotice Use the SDK\'s Asset multi-address support instead. The wallet now works with multiple addresses per account.',
  )
  String? address;

  final String? _swapContractAddress;
  String? fallbackSwapContract;

  final bool _walletOnly;
  final int priority;
  Coin? parentCoin;
  final CoinMode mode;
  final CoinState state;

  // Cache for expensive computed properties
  String? _cachedTypeName;
  bool? _cachedisParent;
  String? _cachedDisplayName;

  bool get walletOnly => _walletOnly || appWalletOnlyAssetList.contains(abbr);

  String? get swapContractAddress =>
      _swapContractAddress ?? parentCoin?.swapContractAddress;
  bool get isSuspended => state == CoinState.suspended;
  bool get isActive => state == CoinState.active;
  bool get isActivating => state == CoinState.activating;
  bool get isInactive => state == CoinState.inactive;

  @Deprecated(
    '$_urgentDeprecationNotice Use the SDK\'s Asset.sendableBalance instead. This value is not updated after initial load and may be inaccurate.',
  )
  double sendableBalance = 0;

  String get typeName {
    return _cachedTypeName ??= getCoinTypeName(type, abbr);
  }

  bool get isParent {
    return _cachedisParent ??= isParentCoin(type, abbr);
  }

  String get typeNameWithTestnet => typeName + (isTestCoin ? ' (TESTNET)' : '');

  /// Display-friendly name that disambiguates parent coins on different EVM networks.
  ///
  /// For example, for a parent coin with abbreviation 'ETH-ARB20', this returns
  /// 'Ethereum (ARB20)' so that it is visually distinct from 'Ethereum' (ERC20).
  String get displayName {
    return _cachedDisplayName ??= id.displayName;
  }

  bool get isIrisToken => protocolType == 'TENDERMINTTOKEN';

  bool get need0xPrefixForTxHash => isErcType;

  bool get isErcType => protocolType == 'ERC20' || protocolType == 'ETH';

  bool get isTxMemoSupported =>
      type == CoinType.tendermint || type == CoinType.tendermintToken;

  bool get isCustomFeeSupported =>
      type != CoinType.tendermintToken &&
      type != CoinType.tendermint &&
      type != CoinType.trx &&
      type != CoinType.trc20;

  static bool checkSegwitByAbbr(String abbr) => abbr.contains('-segwit');
  static String normalizeAbbr(String abbr) => abbr.replaceAll('-segwit', '');

  @override
  String toString() {
    return 'Coin($abbr);';
  }

  Coin dummyCopyWithoutProtocolData() {
    return Coin(
      type: type,
      abbr: abbr,
      id: assetId,
      name: name,
      explorerUrl: explorerUrl,
      explorerTxUrl: explorerTxUrl,
      explorerAddressUrl: explorerAddressUrl,
      protocolType: protocolType,
      isTestCoin: isTestCoin,
      isCustomCoin: isCustomCoin,
      logoImageUrl: logoImageUrl,
      coingeckoId: coingeckoId,
      fallbackSwapContract: fallbackSwapContract,
      priority: priority,
      state: state,
      swapContractAddress: swapContractAddress,
      walletOnly: walletOnly,
      mode: mode,
      usdPrice: usdPrice,
      parentCoin: parentCoin,
      derivationPath: derivationPath,
      coinpaprikaId: coinpaprikaId,
      activeByDefault: activeByDefault,
      protocolData: null,
    );
  }

  AssetId get assetId => id;
  Asset toSdkAsset(KomodoDefiSdk sdk) => getSdkAsset(sdk, abbr);

  Coin copyWith({
    CoinType? type,
    String? abbr,
    AssetId? id,
    String? name,
    String? explorerUrl,
    String? explorerTxUrl,
    String? explorerAddressUrl,
    String? protocolType,
    String? logoImageUrl,
    ProtocolData? protocolData,
    bool? isTestCoin,
    String? coingeckoId,
    String? fallbackSwapContract,
    int? priority,
    CoinState? state,
    int? decimals,
    Coin? parentCoin,
    String? derivationPath,
    CexPrice? usdPrice,
    String? coinpaprikaId,
    bool? activeByDefault,
    String? swapContractAddress,
    bool? walletOnly,
    CoinMode? mode,
    String? address,
    double? sendableBalance,
    bool? isCustomCoin,
  }) {
    return Coin(
        type: type ?? this.type,
        abbr: abbr ?? this.abbr,
        id: id ?? this.id,
        name: name ?? this.name,
        logoImageUrl: logoImageUrl ?? this.logoImageUrl,
        explorerUrl: explorerUrl ?? this.explorerUrl,
        explorerTxUrl: explorerTxUrl ?? this.explorerTxUrl,
        explorerAddressUrl: explorerAddressUrl ?? this.explorerAddressUrl,
        protocolType: protocolType ?? this.protocolType,
        protocolData: protocolData ?? this.protocolData,
        isTestCoin: isTestCoin ?? this.isTestCoin,
        coingeckoId: coingeckoId ?? this.coingeckoId,
        fallbackSwapContract: fallbackSwapContract ?? this.fallbackSwapContract,
        priority: priority ?? this.priority,
        state: state ?? this.state,
        decimals: decimals ?? this.decimals,
        parentCoin: parentCoin ?? this.parentCoin,
        derivationPath: derivationPath ?? this.derivationPath,
        usdPrice: usdPrice ?? this.usdPrice,
        coinpaprikaId: coinpaprikaId ?? this.coinpaprikaId,
        activeByDefault: activeByDefault ?? this.activeByDefault,
        swapContractAddress: swapContractAddress ?? _swapContractAddress,
        walletOnly: walletOnly ?? _walletOnly,
        mode: mode ?? this.mode,
        isCustomCoin: isCustomCoin ?? this.isCustomCoin,
      )
      ..address = address ?? this.address
      ..sendableBalance = sendableBalance ?? this.sendableBalance;
  }

  // Only use AssetId for equality checks, not any of the
  // legacy fields here.
  @override
  List<Object?> get props => [
    id,
    // Legacy fields still updated and used in the app, so we keep them
    // in the props list for now to maintain the desired state updates.
    state, type, abbr, usdPrice, isTestCoin, parentCoin, address,
  ];
}

extension LegacyCoinToSdkAsset on Coin {
  Asset toSdkAsset(KomodoDefiSdk sdk) => getSdkAsset(sdk, abbr);
}

class ProtocolData {
  ProtocolData({required this.platform, required this.contractAddress});

  factory ProtocolData.fromJson(Map<String, dynamic> json) => ProtocolData(
    platform: json['platform'],
    contractAddress: json['contract_address'] ?? '',
  );

  String platform;
  String contractAddress;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'platform': platform,
      'contract_address': contractAddress,
    };
  }
}

class CoinNode {
  const CoinNode({required this.url, required this.guiAuth});
  static CoinNode fromJson(Map<String, dynamic> json) => CoinNode(
    url: json['url'],
    guiAuth: (json['gui_auth'] ?? json['komodo_proxy']) ?? false,
  );
  final bool guiAuth;
  final String url;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'url': url,
    'gui_auth': guiAuth,
    'komodo_proxy': guiAuth,
  };
}

enum CoinMode { segwit, standard, hw }

enum CoinState { inactive, activating, active, suspended, hidden }

extension CoinListExtension on List<Coin> {
  Map<String, Coin> toMap() {
    return Map.fromEntries(map((coin) => MapEntry(coin.abbr, coin)));
  }
}

const String _urgentDeprecationNotice =
    '(URGENT) This must be fixed before the next release.';

/// Extension to filter a list of coins to unique elements based on a given ID function.
/// If no ID function is provided, the elements themselves are used as IDs.
///
/// Helper method to get unique items from a list, given that the equality check for Coin is
/// based on transient fields that can change for the same coin.
extension Unique<E, Id> on List<E> {
  List<E> unique(Id Function(E element) id, [bool inplace = true]) {
    final ids = <dynamic>{};
    var list = inplace ? this : List<E>.from(this);
    list.retainWhere((x) => ids.add(id(x)));
    return list;
  }
}
