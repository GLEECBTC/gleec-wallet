import 'package:web_dex/mm2/mm2_api/rpc/base.dart';
import 'package:web_dex/model/wallet.dart';

class MyTxHistoryV2Request
    implements BaseRequest, BaseRequestWithParams<MyTxHistoryV2ParamsRequest> {
  MyTxHistoryV2Request({required String coin, required WalletType type})
      : params = MyTxHistoryV2ParamsRequest(coin: coin, type: type);
  @override
  late String userpass;

  @override
  final String method = 'my_tx_history';

  @override
  final MyTxHistoryV2ParamsRequest params;

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
        'userpass': userpass,
        'mmrpc': '2.0',
        'method': method,
        'params': params.toJson(),
      };
}

class MyTxHistoryV2ParamsRequest {
  const MyTxHistoryV2ParamsRequest({required this.coin, required this.type});
  final String coin;
  final WalletType type;

  Map<String, dynamic> toJson() {
    if (type == WalletType.trezor) {
      return <String, dynamic>{
        'coin': coin,
        'limit': 10000,
        'target': {
          'type': 'account_id',
          'account_id': 0,
        }
      };
    }
    return <String, dynamic>{
      'coin': coin,
      'limit': 10000 // https://github.com/GLEECBTC/WebDEX/issues/795
    };
  }
}
