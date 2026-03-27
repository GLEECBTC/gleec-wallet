import 'package:komodo_defi_types/komodo_defi_types.dart';
import 'package:test/test.dart';
import 'package:web_dex/model/coin.dart';
import 'package:web_dex/model/coin_type.dart';
import 'package:web_dex/shared/utils/utils.dart';

void testExplorerUrlHelpers() {
  test(
    'getTxExplorerUrl falls back to base explorer when tx pattern is empty',
    () {
      final coin = _coinWithExplorer(
        explorerUrl: 'https://explorer.example/tx/',
        explorerTxUrl: '',
      );

      expect(
        getTxExplorerUrl(coin, 'abc123'),
        'https://explorer.example/tx/abc123',
      );
    },
  );

  test(
    'getTxExplorerUrl keeps 0x prefix behavior on base explorer fallback',
    () {
      final coin = _coinWithExplorer(
        explorerUrl: 'https://etherscan.io/tx/',
        explorerTxUrl: '',
        protocolType: 'ERC20',
        type: CoinType.erc20,
      );

      expect(
        getTxExplorerUrl(coin, 'deadbeef'),
        'https://etherscan.io/tx/0xdeadbeef',
      );
    },
  );
}

Coin _coinWithExplorer({
  required String explorerUrl,
  required String explorerTxUrl,
  String protocolType = 'UTXO',
  CoinType type = CoinType.utxo,
}) {
  final assetId = AssetId(
    id: 'TEST',
    name: 'Test Coin',
    parentId: null,
    symbol: AssetSymbol(assetConfigId: 'TEST'),
    derivationPath: null,
    chainId: AssetChainId(chainId: 0),
    subClass: CoinSubClass.utxo,
  );

  return Coin(
    type: type,
    abbr: 'TEST',
    id: assetId,
    name: 'Test Coin',
    logoImageUrl: null,
    isCustomCoin: false,
    explorerUrl: explorerUrl,
    explorerTxUrl: explorerTxUrl,
    explorerAddressUrl: '',
    protocolType: protocolType,
    protocolData: ProtocolData(platform: '', contractAddress: ''),
    isTestCoin: false,
    coingeckoId: null,
    fallbackSwapContract: null,
    priority: 0,
    state: CoinState.inactive,
    walletOnly: false,
    mode: CoinMode.standard,
    swapContractAddress: null,
  );
}
