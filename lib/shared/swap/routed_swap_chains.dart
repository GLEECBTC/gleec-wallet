import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:web_dex/shared/swap/swap_networks.dart';

/// The EVM chain ids the routing provider served on 2026-09-24
/// (`GET /v1/chains?chainTypes=EVM`), for assets that are not active yet.
///
/// KDF's `routed_swap::supported_coins` lists active coins only, and nothing
/// else tells the wallet whether an inactive asset's network is routable, so
/// this decides what the picker offers before activation. Once an asset is
/// active, KDF's own list decides — a network dropped here is caught then.
/// Refresh the set when the provider adds networks.
const Set<int> routedSwapChainIds = {
  1,
  10,
  14,
  25,
  30,
  40,
  50,
  56,
  88,
  100,
  122,
  130,
  137,
  143,
  146,
  196,
  204,
  232,
  252,
  288,
  324,
  480,
  747,
  988,
  999,
  1088,
  1135,
  1329,
  1337,
  1480,
  1625,
  1672,
  1776,
  1868,
  2020,
  2741,
  2818,
  4217,
  4326,
  4663,
  5000,
  5031,
  5042,
  8217,
  8453,
  9745,
  13371,
  16661,
  33139,
  34443,
  42161,
  42170,
  42220,
  42793,
  43111,
  43114,
  57073,
  59144,
  60808,
  80094,
  81457,
  84532,
  98866,
  421614,
  534352,
  747474,
  3586256,
  5042002,
  11155111,
  11155420,
};

/// Whether [asset] should be routable once active: an EVM asset on a network
/// the provider serves.
bool isRoutedSwapCandidate(AssetId asset) {
  final chainId = SwapNetworks.evmChainIdOf(asset);
  return chainId != null && routedSwapChainIds.contains(chainId);
}
